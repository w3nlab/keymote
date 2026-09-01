import AVFoundation
import Foundation
import Speech
import SriVibeCore

enum VoiceTranscriptionState: Equatable {
    case idle, recording, transcribing
}

enum VoiceTranscriptionError: LocalizedError {
    case microphoneDenied, speechDenied, localRecognitionUnavailable, notRecording, emptyTranscript, recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone permission is required"
        case .speechDenied: "Speech Recognition permission is required"
        case .localRecognitionUnavailable: "On-device Speech Recognition is unavailable for the current language"
        case .notRecording: "No recording is in progress"
        case .emptyTranscript: "No speech was recognized"
        case let .recognitionFailed(message): "Speech Recognition failed: \(message)"
        }
    }
}

private final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func set(_ value: String) { lock.lock(); self.value = value; lock.unlock() }
    func get() -> String { lock.lock(); defer { lock.unlock() }; return value }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    func reset() { lock.lock(); value = 0; lock.unlock() }
    func get() -> Int { lock.lock(); defer { lock.unlock() }; return value }
}

private final class LockedAudioStats: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: Float = 0
    private var sumSquares: Double = 0
    private var samples = 0

    func add(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        var localPeak: Float = 0
        var localSum: Double = 0
        let count = Int(buffer.frameLength)
        for index in 0..<count {
            let value = abs(channel[index])
            localPeak = max(localPeak, value)
            localSum += Double(value * value)
        }
        lock.lock()
        peak = max(peak, localPeak)
        sumSquares += localSum
        samples += count
        lock.unlock()
    }

    func summary() -> String {
        lock.lock(); defer { lock.unlock() }
        let rms = samples > 0 ? sqrt(sumSquares / Double(samples)) : 0
        return String(format: "peak=%.5f rms=%.5f samples=%d", peak, rms, samples)
    }

    func reset() {
        lock.lock(); peak = 0; sumSquares = 0; samples = 0; lock.unlock()
    }
}

private final class SpeechResultWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Never>?
    private var finished = false

    func wait(timeoutNanoseconds: UInt64) async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            install(continuation)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .nanoseconds(Int(timeoutNanoseconds))) {
                self.finish("")
            }
        }
    }

    func finish(_ value: String) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    private func install(_ continuation: CheckedContinuation<String, Never>) {
        lock.lock()
        if finished { lock.unlock(); continuation.resume(returning: "") }
        else { self.continuation = continuation; lock.unlock() }
    }
}

@MainActor
final class VoiceTranscriptionService {
    var onDiagnostic: ((String) -> Void)?
    private let engine = AVAudioEngine()
    private let gateway: CloudModelGateway
    private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var fileURL: URL?
    private let localText = LockedText()
    private let recognitionError = LockedText()
    private let recognitionCallbackCount = LockedCounter()
    private var speechResultWaiter: SpeechResultWaiter?
    private let audioFrameCount = LockedCounter()
    private let audioStats = LockedAudioStats()
    private var startedAt: Date?
    private(set) var state: VoiceTranscriptionState = .idle

    init(gateway: CloudModelGateway = CloudModelGateway()) { self.gateway = gateway }

    func start(source: TranscriptionSource) async throws {
        guard state == .idle else { return }
        onDiagnostic?("Voice: start requested source=\(source.rawValue)")
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        onDiagnostic?("Voice: microphone authorization=\(microphone.rawValue)")
        guard microphone == .authorized else {
            if microphone == .notDetermined {
                let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard allowed else { throw VoiceTranscriptionError.microphoneDenied }
            } else { throw VoiceTranscriptionError.microphoneDenied }
            return try await start(source: source)
        }
        if source == .localSpeech { try await prepareLocalRecognition() }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Keymote-\(UUID().uuidString).wav")
        let captureFile = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        audioFile = captureFile
        fileURL = url
        let captureRequest = speechRequest
        let frameCounter = audioFrameCount
        let stats = audioStats
        audioFrameCount.reset()
        audioStats.reset()
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { @Sendable [captureFile, captureRequest, frameCounter, stats] buffer, _ in
            frameCounter.increment()
            stats.add(buffer)
            try? captureFile.write(from: buffer)
            captureRequest?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        startedAt = Date()
        state = .recording
        onDiagnostic?("Voice: audio engine started sampleRate=\(Int(format.sampleRate)) channels=\(format.channelCount)")
    }

    func stop(source: TranscriptionSource, cloudProvider: CloudProvider?, cloudConfiguration: CloudProviderConfiguration?, languageCode: String?) async throws -> String {
        guard state == .recording else { throw VoiceTranscriptionError.notRecording }
        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        state = .transcribing
        let durationText = String(format: "%.2f", duration)
        onDiagnostic?("Voice: stop requested duration=\(durationText)s frames=\(audioFrameCount.get()) \(audioStats.summary())")
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        speechRequest?.endAudio()
        defer { cleanup() }

        switch source {
        case .localSpeech:
            // Wait for Speech's final callback instead of cancelling after a
            // fixed short delay. Recognition can take longer on first use.
            let waiter = speechResultWaiter
            _ = await waiter?.wait(timeoutNanoseconds: 5_000_000_000)
            let text = localText.get().trimmingCharacters(in: .whitespacesAndNewlines)
            let error = recognitionError.get()
            let errorText = error.isEmpty ? "none" : error
            onDiagnostic?("Voice: local Speech result length=\(text.count) callbacks=\(recognitionCallbackCount.get()) error=\(errorText)")
            if text.isEmpty, !error.isEmpty { throw VoiceTranscriptionError.recognitionFailed(error) }
            guard !text.isEmpty else { throw VoiceTranscriptionError.emptyTranscript }
            return text
        case .cloud:
            guard let cloudProvider, let cloudConfiguration, let url = fileURL else { throw CloudModelError.notConfigured(.openAI) }
            let data = try Data(contentsOf: url)
            onDiagnostic?("Voice: cloud upload prepared provider=\(cloudProvider.rawValue) model=\(cloudConfiguration.transcriptionModel) bytes=\(data.count)")
            let transcript = try await gateway.transcribe(audio: data, provider: cloudProvider, configuration: cloudConfiguration, languageCode: languageCode)
            guard !transcript.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw VoiceTranscriptionError.emptyTranscript }
            return transcript.text
        }
    }

    func cancel() {
        guard state != .idle else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        recognitionTask?.cancel()
        onDiagnostic?("Voice: recording cancelled")
        cleanup()
    }

    private func prepareLocalRecognition() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        onDiagnostic?("Voice: Speech authorization=\(status.rawValue)")
        if status == .notDetermined {
            onDiagnostic?("Voice: requesting Speech authorization")
            let result = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            onDiagnostic?("Voice: Speech authorization response=\(result.rawValue)")
            guard result == .authorized else { throw VoiceTranscriptionError.speechDenied }
        } else if status != .authorized {
            throw VoiceTranscriptionError.speechDenied
        }
        let current = Locale.autoupdatingCurrent
        let language = current.language.languageCode?.identifier ?? "en"
        let region = current.region?.identifier ?? "US"
        let locale = Locale(identifier: "\(language)-\(region)")
        // Do not synchronously query supportsOnDeviceRecognition here. On
        // recent macOS releases that property can block while the speech
        // model is being loaded. The recognition task reports availability
        // errors asynchronously instead.
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw VoiceTranscriptionError.localRecognitionUnavailable
        }
        onDiagnostic?("Voice: local Speech recognizer ready locale=\(locale.identifier)")
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        localText.set("")
        recognitionError.set("")
        recognitionCallbackCount.reset()
        speechRequest = request
        let textStore = localText
        let waiter = SpeechResultWaiter()
        speechResultWaiter = waiter
        let callbackCount = recognitionCallbackCount
        let callbackError = recognitionError
        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            callbackCount.increment()
            if let error { callbackError.set(error.localizedDescription) }
            if let result {
                let text = result.bestTranscription.formattedString
                textStore.set(text)
                if result.isFinal { waiter.finish(text) }
            }
        }
    }

    private func cleanup() {
        recognitionTask?.cancel()
        recognitionTask = nil
        speechRequest = nil
        speechResultWaiter = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        audioFile = nil
        startedAt = nil
        state = .idle
        onDiagnostic?("Voice: resources cleaned up")
    }
}
