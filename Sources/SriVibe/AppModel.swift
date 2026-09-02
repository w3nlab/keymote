import AppKit
import AVFoundation
import Combine
import os
import Speech
import SwiftUI
import UniformTypeIdentifiers
import SriVibeCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var devices: [RemoteDevice] = []
    @Published var configuration: AppConfiguration
    @Published private(set) var currentProfile: AppProfile = .default
    @Published private(set) var lastMessage = "Waiting for a paired Siri Remote" {
        didSet { statusRevision += 1 }
    }
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var statusRevision = 0
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var voiceState: VoiceTranscriptionState = .idle
    @Published private(set) var liveTranscript = ""
    @Published private(set) var microphoneGranted = false
    @Published private(set) var speechRecognitionGranted = false
    var onDockVisibilityChanged: ((Bool) -> Void)?
    var onAppearanceChanged: ((AppAppearance) -> Void)?

    private let store = ConfigurationStore()
    private let monitor = HIDRemoteMonitor()
    private let executor = ActionExecutor()
    private let voiceService = VoiceTranscriptionService()
    private let credentialStore = InstallationKeyStore()
    private let nativeMediaEventSuppressor = NativeMediaEventSuppressor()
    private let touchpadEventDiagnostics = TouchpadEventDiagnostics()
    private let logger = Logger(subsystem: "app.keymote.remote", category: "runtime")
    private let diagnosticInputMode = CommandLine.arguments.contains("--diagnose-input")
        || CommandLine.arguments.contains("--diagnose-touchpad")
    private let touchpadDiagnosticMode = CommandLine.arguments.contains("--diagnose-touchpad")
    private var gestureEngine: ButtonGestureEngine
    private var holdTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var injectedLiveTranscript = ""
    private var liveSpeechSegment = ""

    init() {
        let loaded = ConfigurationStore().load()
        configuration = loaded
        gestureEngine = ButtonGestureEngine(holdThresholdMilliseconds: loaded.holdThresholdMilliseconds)
        monitor.captureRawInput = touchpadDiagnosticMode
        monitor.onDevicesChanged = { [weak self] devices in Task { @MainActor in self?.setDevices(devices) } }
        monitor.onButtonEvent = { [weak self] button, isPressed in Task { @MainActor in self?.handle(button, isPressed: isPressed) } }
        monitor.onStatus = { [weak self] message in Task { @MainActor in self?.lastMessage = message } }
        monitor.onDiagnostic = { [weak self] line in Task { @MainActor in self?.recordDiagnostic(line) } }
        monitor.onDeviceDisconnected = { [weak self] in Task { @MainActor in self?.gestureEngine.cancelAll() } }
        touchpadEventDiagnostics.onDiagnostic = { [weak self] line in Task { @MainActor in self?.recordDiagnostic(line) } }
        voiceService.onDiagnostic = { [weak self] line in self?.recordDiagnostic(line) }
        voiceService.onPartialTranscript = { [weak self] text in
            Task { @MainActor in self?.receivePartialTranscript(text) }
        }
    }

    var selectedDevice: RemoteDevice? { devices.first { $0.id == configuration.selectedDeviceID } }
    var showsInDock: Bool { configuration.showsInDock ?? true }
    var language: AppLanguage { configuration.interfaceLanguage ?? .english }
    var appearance: AppAppearance { configuration.appearance ?? .system }
    var voiceInputMode: VoiceInputMode { configuration.voiceInputMode ?? .disabled }
    var transcriptionSource: TranscriptionSource { configuration.transcriptionSource ?? .localSpeech }
    var speechRecognitionLanguage: SpeechRecognitionLanguage { configuration.speechRecognitionLanguage ?? .automatic }
    var voiceTranscriptionTiming: VoiceTranscriptionTiming { configuration.voiceTranscriptionTiming ?? .afterRecording }
    var cloudTranscriptionProvider: CloudProvider { configuration.cloudTranscriptionProvider ?? .openAI }
    var tvApplicationName: String { configuration.tvApplicationName ?? "ChatGPT" }
    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var statusText: String {
        if diagnosticInputMode { return L10n.text("diagnosticMode", language) }
        if let selectedDevice { return L10n.format("connected", language, selectedDevice.name) }
        return localizedStatus(lastMessage)
    }
    var statusSymbol: String { selectedDevice == nil ? "dot.radiowaves.left.and.right" : "dot.radiowaves.right" }

    func start() {
        refreshPermissions(request: true)
        refreshVoicePermissions()
        nativeMediaEventSuppressor.start()
        if touchpadDiagnosticMode { touchpadEventDiagnostics.start() }
        observeFrontmostApplication()
        monitor.start(selectedID: configuration.selectedDeviceID)
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flushHolds() }
        }
    }

    func stop() {
        holdTimer?.invalidate()
        monitor.stop()
        nativeMediaEventSuppressor.stop()
        touchpadEventDiagnostics.stop()
        executor.cancelApplicationSwitcher()
        executor.stopVolumeAdjustment()
        voiceService.cancel()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }

    func refreshPermissions(request: Bool = false) {
        inputMonitoringGranted = PermissionManager.inputMonitoring(request: request)
        accessibilityGranted = PermissionManager.accessibility(request: request)
        statusRevision += 1
    }

    func refreshVoicePermissions() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        speechRecognitionGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
        statusRevision += 1
    }

    func requestVoicePermissions() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                _ = await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
                }
            }
            refreshVoicePermissions()
        }
    }

    func selectDevice(_ id: String?) {
        gestureEngine.cancelAll()
        configuration.selectedDeviceID = id
        persist()
        monitor.selectDevice(id)
        statusRevision += 1
    }

    func reconnect() { monitor.reconnect() }

    func setShowsInDock(_ show: Bool) {
        configuration.showsInDock = show
        persist()
        onDockVisibilityChanged?(show)
    }

    func setLanguage(_ language: AppLanguage) {
        configuration.interfaceLanguage = language
        persist()
        statusRevision += 1
    }

    func setAppearance(_ appearance: AppAppearance) {
        configuration.appearance = appearance
        persist()
        onAppearanceChanged?(appearance)
    }

    func chooseTVApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
        configuration.tvApplicationBundleIdentifier = identifier
        configuration.tvApplicationName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        persist()
        statusRevision += 1
    }

    func updateHoldThreshold(_ milliseconds: Int) {
        configuration.holdThresholdMilliseconds = milliseconds
        gestureEngine = ButtonGestureEngine(holdThresholdMilliseconds: milliseconds)
        persist()
    }

    func setVoiceInputMode(_ mode: VoiceInputMode) {
        guard mode != .remoteMicrophoneExperimental else {
            lastMessage = language == .chinese ? "遥控器麦克风方案尚未实现" : "Siri Remote microphone is not implemented"
            return
        }
        if voiceState != .idle { voiceService.cancel(); voiceState = .idle }
        configuration.voiceInputMode = mode
        persist()
    }

    func setTranscriptionSource(_ source: TranscriptionSource) {
        configuration.transcriptionSource = source
        persist()
    }

    func setSpeechRecognitionLanguage(_ language: SpeechRecognitionLanguage) {
        configuration.speechRecognitionLanguage = language
        persist()
    }

    func setVoiceTranscriptionTiming(_ timing: VoiceTranscriptionTiming) {
        configuration.voiceTranscriptionTiming = timing
        persist()
    }

    func setCloudTranscriptionProvider(_ provider: CloudProvider) {
        guard provider.supportsTranscription else { return }
        configuration.cloudTranscriptionProvider = provider
        persist()
    }

    func cloudConfiguration(for provider: CloudProvider) -> CloudProviderConfiguration {
        configuration.cloudProviders?[provider] ?? CloudProviderConfiguration()
    }

    func saveCloudConfiguration(_ value: CloudProviderConfiguration, provider: CloudProvider, plainAPIKey: String?) {
        var copy = value
        if let plainAPIKey, !plainAPIKey.isEmpty {
            do { copy.encryptedAPIKey = try credentialStore.encrypt(plainAPIKey) }
            catch { lastMessage = error.localizedDescription; return }
        }
        var providers = configuration.cloudProviders ?? [:]
        providers[provider] = copy
        configuration.cloudProviders = providers
        persist()
    }

    func testCloudProvider(_ provider: CloudProvider) {
        let configuration = cloudConfiguration(for: provider)
        lastMessage = language == .chinese ? "正在测试 \(provider.rawValue)…" : "Testing \(provider.rawValue)…"
        Task {
            do {
                _ = try await CloudModelGateway().generateText("Reply only with OK.", provider: provider, configuration: configuration)
                lastMessage = language == .chinese ? "\(provider.rawValue) 连接成功" : "\(provider.rawValue) connection succeeded"
            } catch { lastMessage = error.localizedDescription }
        }
    }

    func action(for button: RemoteButton, gesture: ButtonGesture, profile: AppProfile) -> RemoteAction {
        let action = configuredAction(for: button, gesture: gesture, profile: profile)
        guard action == .useDefault, profile != .default else { return action }
        return configuration.mappings[.default]?.action(for: button, gesture: gesture) ?? .none
    }

    func configuredAction(for button: RemoteButton, gesture: ButtonGesture, profile: AppProfile) -> RemoteAction {
        configuration.mappings[profile]?.action(for: button, gesture: gesture) ?? .none
    }

    func setAction(_ action: RemoteAction, for button: RemoteButton, gesture: ButtonGesture, profile: AppProfile) {
        guard AppConfiguration.allowedActions(for: profile).contains(action) else { return }
        var mapping = configuration.mappings[profile] ?? ProfileMappings()
        mapping.set(action, for: button, gesture: gesture)
        configuration.mappings[profile] = mapping
        persist()
        if action == .launchSelectedApplication, button == .tv { chooseTVApplication() }
    }

    private func setDevices(_ next: [RemoteDevice]) {
        devices = next
        statusRevision += 1
        if configuration.selectedDeviceID == nil, let first = next.first {
            selectDevice(first.id)
        }
    }

    private func observeFrontmostApplication() {
        updateProfile()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.updateProfile() } }
    }

    private func updateProfile() {
        let next = AppProfile.forBundleIdentifier(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        guard currentProfile != next else { return }
        currentProfile = next
        if voiceState != .idle {
            voiceService.cancel()
            voiceState = .idle
            lastMessage = language == .chinese ? "因切换应用已取消录音" : "Recording cancelled because the active profile changed"
        }
        statusRevision += 1
    }

    private func handle(_ button: RemoteButton, isPressed: Bool) {
        if button == .playPause, isPressed {
            nativeMediaEventSuppressor.suppressNextPlayPauseEvent()
        }
        if button == .volumeUp || button == .volumeDown {
            let hasVolumeTapMapping = action(for: button, gesture: .tap, profile: currentProfile) != .none
            if hasVolumeTapMapping {
                if isPressed { nativeMediaEventSuppressor.beginSuppressingVolume(up: button == .volumeUp) }
                else { nativeMediaEventSuppressor.endSuppressingVolume(up: button == .volumeUp) }
            }
        }
        if isPressed { gestureEngine.press(button, at: Date()) }
        else {
            if button == .volumeUp || button == .volumeDown { executor.stopVolumeAdjustment() }
            perform(gestureEngine.release(button, at: Date()))
        }
    }

    private func flushHolds() { perform(gestureEngine.advance(to: Date())) }

    private func perform(_ outputs: [GestureOutput]) {
        guard !outputs.isEmpty else { return }
        updateProfile()
        for case let .perform(button, gesture) in outputs {
            if let switcherResult = performApplicationSwitcherAction(for: button) {
                lastMessage = switcherResult
                recordDiagnostic("Application switcher: \(switcherResult)")
                continue
            }
            let actionProfile: AppProfile = button == .tv ? .default : currentProfile
            let action = self.action(for: button, gesture: gesture, profile: actionProfile)
            recordDiagnostic("\(currentProfile.rawValue): \(button.rawValue) \(gesture.rawValue) → \(action.rawValue)")
            if diagnosticInputMode {
                lastMessage = "Captured \(button.rawValue) \(gesture.rawValue)"
                continue
            }
            if action == .toggleVoiceTranscription {
                guard voiceInputMode == .macMicrophone else {
                    lastMessage = language == .chinese ? "请先在设备设置中启用 Mac 麦克风转写" : "Enable Mac microphone transcription in Device settings first"
                    continue
                }
                toggleVoiceTranscription()
                continue
            }
            guard accessibilityGranted else {
                lastMessage = "Accessibility permission is required to perform actions"
                continue
            }
            if action != .none {
                let result = executor.execute(action, for: currentProfile, tvApplicationBundleIdentifier: configuration.tvApplicationBundleIdentifier)
                lastMessage = result
                recordDiagnostic("Action result: \(result)")
            }
        }
    }

    private func toggleVoiceTranscription() {
        recordDiagnostic("Voice: Siri tap received state=\(voiceState) mode=\(voiceInputMode.rawValue) profile=\(currentProfile.rawValue)")
        if voiceState == .idle {
            let source = transcriptionSource
            let recognitionLanguage = speechRecognitionLanguage
            let timing = voiceTranscriptionTiming
            if source == .cloud {
                let provider = cloudTranscriptionProvider
                guard provider.supportsTranscription else {
                    lastMessage = language == .chinese ? "Claude 当前不支持云端语音转写" : "Claude does not support cloud transcription"
                    return
                }
                let cloud = cloudConfiguration(for: provider)
                guard cloud.isEnabled, cloud.encryptedAPIKey != nil, !cloud.transcriptionModel.isEmpty else {
                    lastMessage = language == .chinese ? "请先配置云端转写提供者和模型" : "Configure a cloud transcription provider and model first"
                    return
                }
            }
            // Reserve the toggle immediately so repeated HID events cannot
            // launch multiple concurrent audio/Speech initialization tasks.
            voiceState = .transcribing
            liveTranscript = ""
            injectedLiveTranscript = ""
            liveSpeechSegment = ""
            lastMessage = language == .chinese ? "正在启动录音…" : "Starting recording…"
            Task {
                do {
                    try await voiceService.start(source: source, localeIdentifier: recognitionLanguage.localeIdentifier, timing: timing)
                    voiceState = .recording
                    lastMessage = language == .chinese ? "正在录音，再次轻按 Siri 键结束" : "Recording — tap Siri again to stop"
                } catch {
                    voiceState = .idle
                    lastMessage = error.localizedDescription
                    recordDiagnostic("Voice: start failed: \(error.localizedDescription)")
                    refreshVoicePermissions()
                }
            }
        } else if voiceState == .recording {
            voiceState = .transcribing
            lastMessage = language == .chinese ? "正在转写…" : "Transcribing…"
            let source = transcriptionSource
            let provider = cloudTranscriptionProvider
            let cloud = cloudConfiguration(for: provider)
            let languageCode = speechRecognitionLanguage.languageCode ?? Locale.autoupdatingCurrent.language.languageCode?.identifier
            Task {
                do {
                    let text = try await voiceService.stop(source: source, cloudProvider: provider, cloudConfiguration: cloud, languageCode: languageCode)
                    recordDiagnostic("Voice: transcription returned length=\(text.count)")
                    let copied: Bool
                    let pasted: Bool
                    if accessibilityGranted {
                        let hasLiveText = voiceTranscriptionTiming == .realtime && !injectedLiveTranscript.isEmpty
                        if hasLiveText, text == injectedLiveTranscript {
                            NSPasteboard.general.clearContents()
                            copied = NSPasteboard.general.setString(text, forType: .string)
                            pasted = copied // The final text is already at the cursor.
                        } else if hasLiveText {
                            pasted = executor.replaceTransientTextAtCursor(previous: injectedLiveTranscript, with: text)
                            copied = pasted
                        } else {
                            NSPasteboard.general.clearContents()
                            copied = NSPasteboard.general.setString(text, forType: .string)
                            pasted = copied && executor.pasteFromClipboard()
                        }
                        if pasted { injectedLiveTranscript = text }
                    } else {
                        NSPasteboard.general.clearContents()
                        copied = NSPasteboard.general.setString(text, forType: .string)
                        pasted = false
                    }
                    liveTranscript = text
                    liveSpeechSegment = ""
                    recordDiagnostic("Voice: clipboard write=\(copied)")
                    recordDiagnostic("Voice: paste attempted=\(accessibilityGranted) result=\(pasted)")
                    lastMessage = accessibilityGranted
                        ? (language == .chinese ? "已转写并粘贴" : "Transcribed and pasted")
                        : (language == .chinese ? "已转写并复制到剪贴板（需要辅助功能权限以自动粘贴）" : "Transcribed and copied; Accessibility is required to paste")
                    recordDiagnostic("Voice transcription completed using \(source.rawValue)")
                } catch {
                    lastMessage = error.localizedDescription
                    recordDiagnostic("Voice transcription failed: \(error.localizedDescription)")
                }
                voiceState = .idle
            }
        }
    }

    private func receivePartialTranscript(_ text: String) {
        guard voiceTranscriptionTiming == .realtime, voiceState == .recording else { return }
        liveTranscript = text
        guard accessibilityGranted else { return }
        applyLiveSpeechCandidate(text)
    }

    /// Speech may restart its partial hypothesis after a short pause. Keep the
    /// text that was already committed to the target app and only revise the
    /// current trailing hypothesis.
    private func applyLiveSpeechCandidate(_ candidate: String) {
        guard !candidate.isEmpty else { return }
        guard candidate != liveSpeechSegment else { return }

        if liveSpeechSegment.isEmpty {
            replaceLiveSuffix(previous: "", with: candidate)
            return
        }

        let prefixLength = commonPrefixLength(liveSpeechSegment, candidate)
        // A meaningful shared prefix means Speech is revising the same phrase.
        // Otherwise it has begun a new utterance after a pause: append it.
        if prefixLength >= 2 {
            let previousSuffix = String(liveSpeechSegment.dropFirst(prefixLength))
            let replacementSuffix = String(candidate.dropFirst(prefixLength))
            replaceLiveSuffix(previous: previousSuffix, with: replacementSuffix, replacingSegmentWith: candidate)
        } else {
            let separator = injectedLiveTranscript.isEmpty || injectedLiveTranscript.hasSuffix(" ") || injectedLiveTranscript.hasSuffix("\n") ? "" : " "
            replaceLiveSuffix(previous: "", with: separator + candidate, replacingSegmentWith: candidate)
        }
    }

    private func replaceLiveSuffix(previous: String, with replacement: String, replacingSegmentWith segment: String? = nil) {
        guard executor.replaceTransientTextAtCursor(previous: previous, with: replacement) else {
            recordDiagnostic("Voice: live text update failed")
            return
        }
        if !previous.isEmpty { injectedLiveTranscript.removeLast(previous.count) }
        injectedLiveTranscript += replacement
        liveSpeechSegment = segment ?? replacement
        liveTranscript = injectedLiveTranscript
        recordDiagnostic("Voice: live text updated length=\(injectedLiveTranscript.count)")
    }

    private func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }


    private func performApplicationSwitcherAction(for button: RemoteButton) -> String? {
        guard executor.isApplicationSwitcherActive else { return nil }
        switch button {
        case .left: return executor.moveApplicationSwitcherSelection(forward: false)
        case .right: return executor.moveApplicationSwitcherSelection(forward: true)
        case .center: return executor.confirmApplicationSwitcher()
        case .back: return executor.cancelApplicationSwitcher()
        default: return nil
        }
    }

    private func persist() { store.save(configuration) }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.joined(separator: "\n"), forType: .string)
        lastMessage = "Diagnostics copied to clipboard"
    }

    private func recordDiagnostic(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        diagnostics.append("\(timestamp) \(line)")
        if diagnostics.count > 200 { diagnostics.removeFirst(diagnostics.count - 200) }
        logger.notice("\(line, privacy: .public)")
    }

    private func localizedStatus(_ status: String) -> String {
        let keys: [String: String] = [
            "Waiting for a paired Siri Remote": "waiting",
            "Accessibility permission is required to perform actions": "accessibilityNeeded",
            "Diagnostics copied to clipboard": "diagnosticsCopied"
        ]
        return keys[status].map { L10n.text($0, language) } ?? status
    }
}
