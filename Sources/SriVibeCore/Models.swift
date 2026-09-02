import Foundation

public enum RemoteButton: String, CaseIterable, Codable, Hashable, Sendable {
    case up, down, left, right, center, back, tv, playPause, mute, volumeUp, volumeDown, siri
}

public enum ButtonGesture: String, CaseIterable, Codable, Hashable, Sendable {
    case tap, hold
}

public enum AppLanguage: String, CaseIterable, Codable, Hashable, Sendable {
    case english, chinese
}

public enum AppAppearance: String, CaseIterable, Codable, Hashable, Sendable {
    case system, light, dark
}

public enum VoiceInputMode: String, CaseIterable, Codable, Hashable, Sendable {
    case disabled
    case macMicrophone
    /// Reserved for the Siri Remote private BLE microphone path. It is not
    /// selectable by the shipping application yet.
    case remoteMicrophoneExperimental
}

public enum TranscriptionSource: String, CaseIterable, Codable, Hashable, Sendable {
    case localSpeech
    case cloud
}

public enum SpeechRecognitionLanguage: String, CaseIterable, Codable, Hashable, Sendable {
    case automatic
    case englishUS
    case chineseSimplified

    public var localeIdentifier: String? {
        switch self {
        case .automatic: nil
        case .englishUS: "en-US"
        case .chineseSimplified: "zh-CN"
        }
    }

    public var languageCode: String? {
        switch self {
        case .automatic: nil
        case .englishUS: "en"
        case .chineseSimplified: "zh"
        }
    }
}

public enum VoiceTranscriptionTiming: String, CaseIterable, Codable, Hashable, Sendable {
    case afterRecording
    case realtime
}

public enum CloudProvider: String, CaseIterable, Codable, Hashable, Sendable {
    case anthropic
    case openAI
    case openRouter

    public var supportsTranscription: Bool { self != .anthropic }
}

public struct CloudProviderConfiguration: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// AES-GCM combined representation, encrypted with a per-installation key.
    public var encryptedAPIKey: String?
    public var transcriptionModel: String
    public var textModel: String

    public init(isEnabled: Bool = false, encryptedAPIKey: String? = nil, transcriptionModel: String = "", textModel: String = "") {
        self.isEnabled = isEnabled
        self.encryptedAPIKey = encryptedAPIKey
        self.transcriptionModel = transcriptionModel
        self.textModel = textModel
    }
}

public enum RemoteAction: String, CaseIterable, Codable, Hashable, Sendable {
    case none
    case useDefault
    case toggleVoiceTranscription
    case arrowUp, arrowDown, arrowLeft, arrowRight
    case confirm, escape, delete
    case nextTerminalTab, previousTerminalTab
    case togglePlayPause
    case toggleMute
    case quitApplication
    case adjustVolumeUp, adjustVolumeDown
    case switchApplication, exitApplicationSwitcher
    case launchSelectedApplication
    /// Legacy value retained only to migrate existing configurations.
    case activateChatGPT
}

public enum AppProfile: String, CaseIterable, Codable, Hashable, Sendable {
    case `default`, terminal, ghostty, otty, kitty, chrome, edge, chatGPT

    public static func forBundleIdentifier(_ identifier: String?) -> AppProfile {
        switch identifier {
        case "com.apple.Terminal": .terminal
        case "com.mitchellh.ghostty": .ghostty
        case "io.appmakes.otty": .otty
        case "net.kovidgoyal.kitty": .kitty
        case "com.google.Chrome": .chrome
        case "com.microsoft.edgemac": .edge
        case "com.openai.chat": .chatGPT
        default: .default
        }
    }

    public var supportsTabs: Bool {
        self == .terminal || self == .ghostty || self == .otty || self == .kitty || self == .chrome || self == .edge
    }
}

public struct ButtonBinding: Codable, Hashable, Sendable, Identifiable {
    public var button: RemoteButton
    public var gesture: ButtonGesture
    public var action: RemoteAction

    public var id: String { "\(button.rawValue).\(gesture.rawValue)" }

    public init(button: RemoteButton, gesture: ButtonGesture, action: RemoteAction) {
        self.button = button
        self.gesture = gesture
        self.action = action
    }
}

public struct ProfileMappings: Codable, Hashable, Sendable {
    public var bindings: [ButtonBinding]

    public init(bindings: [ButtonBinding] = []) { self.bindings = bindings }

    public func action(for button: RemoteButton, gesture: ButtonGesture) -> RemoteAction {
        bindings.first(where: { $0.button == button && $0.gesture == gesture })?.action ?? .none
    }

    public mutating func set(_ action: RemoteAction, for button: RemoteButton, gesture: ButtonGesture) {
        bindings.removeAll { $0.button == button && $0.gesture == gesture }
        bindings.append(ButtonBinding(button: button, gesture: gesture, action: action))
    }
}

public struct AppConfiguration: Codable, Hashable, Sendable {
    public var holdThresholdMilliseconds: Int
    public var selectedDeviceID: String?
    /// Nil is retained for configurations saved before Dock visibility existed.
    public var showsInDock: Bool?
    /// Nil is retained for configurations saved before language and theme preferences existed.
    public var interfaceLanguage: AppLanguage?
    public var appearance: AppAppearance?
    public var tvApplicationBundleIdentifier: String?
    public var tvApplicationName: String?
    public var voiceInputMode: VoiceInputMode?
    public var transcriptionSource: TranscriptionSource?
    public var speechRecognitionLanguage: SpeechRecognitionLanguage?
    public var voiceTranscriptionTiming: VoiceTranscriptionTiming?
    public var cloudTranscriptionProvider: CloudProvider?
    public var cloudProviders: [CloudProvider: CloudProviderConfiguration]?
    public var mappings: [AppProfile: ProfileMappings]

    public init(holdThresholdMilliseconds: Int = 600, selectedDeviceID: String? = nil, showsInDock: Bool? = true, interfaceLanguage: AppLanguage? = .english, appearance: AppAppearance? = .system, tvApplicationBundleIdentifier: String? = nil, tvApplicationName: String? = nil, voiceInputMode: VoiceInputMode? = .disabled, transcriptionSource: TranscriptionSource? = .localSpeech, speechRecognitionLanguage: SpeechRecognitionLanguage? = .automatic, voiceTranscriptionTiming: VoiceTranscriptionTiming? = .afterRecording, cloudTranscriptionProvider: CloudProvider? = .openAI, cloudProviders: [CloudProvider: CloudProviderConfiguration]? = nil, mappings: [AppProfile: ProfileMappings] = AppConfiguration.defaultMappings) {
        self.holdThresholdMilliseconds = min(1_500, max(300, holdThresholdMilliseconds))
        self.selectedDeviceID = selectedDeviceID
        self.showsInDock = showsInDock
        self.interfaceLanguage = interfaceLanguage
        self.appearance = appearance
        self.tvApplicationBundleIdentifier = tvApplicationBundleIdentifier
        self.tvApplicationName = tvApplicationName
        self.voiceInputMode = voiceInputMode
        self.transcriptionSource = transcriptionSource
        self.speechRecognitionLanguage = speechRecognitionLanguage
        self.voiceTranscriptionTiming = voiceTranscriptionTiming
        self.cloudTranscriptionProvider = cloudTranscriptionProvider
        self.cloudProviders = cloudProviders
        self.mappings = mappings
    }

    public static let defaultMappings: [AppProfile: ProfileMappings] = {
        let universalBindings: [ButtonBinding] = [
            .init(button: .up, gesture: .tap, action: .arrowUp),
            .init(button: .down, gesture: .tap, action: .arrowDown),
            .init(button: .left, gesture: .tap, action: .arrowLeft),
            .init(button: .right, gesture: .tap, action: .arrowRight),
            .init(button: .center, gesture: .tap, action: .confirm),
            .init(button: .back, gesture: .tap, action: .escape),
            .init(button: .back, gesture: .hold, action: .quitApplication),
            .init(button: .tv, gesture: .tap, action: .launchSelectedApplication),
            .init(button: .tv, gesture: .hold, action: .switchApplication),
            .init(button: .playPause, gesture: .tap, action: .togglePlayPause),
            .init(button: .mute, gesture: .tap, action: .toggleMute),
            .init(button: .siri, gesture: .tap, action: .toggleVoiceTranscription),
            .init(button: .siri, gesture: .hold, action: .none)
        ]
        var terminal = ProfileMappings(bindings: universalBindings.filter { $0.button != .playPause } + [
            .init(button: .volumeUp, gesture: .tap, action: .nextTerminalTab),
            .init(button: .volumeDown, gesture: .tap, action: .previousTerminalTab)
        ])
        var browser = ProfileMappings(bindings: [
            .init(button: .up, gesture: .tap, action: .arrowUp),
            .init(button: .down, gesture: .tap, action: .arrowDown),
            .init(button: .left, gesture: .tap, action: .arrowLeft),
            .init(button: .right, gesture: .tap, action: .arrowRight),
            .init(button: .playPause, gesture: .tap, action: .togglePlayPause),
            .init(button: .volumeUp, gesture: .tap, action: .nextTerminalTab),
            .init(button: .volumeDown, gesture: .tap, action: .previousTerminalTab),
            .init(button: .volumeUp, gesture: .hold, action: .adjustVolumeUp),
            .init(button: .volumeDown, gesture: .hold, action: .adjustVolumeDown),
            .init(button: .siri, gesture: .tap, action: .toggleVoiceTranscription),
            .init(button: .siri, gesture: .hold, action: .none)
        ])
        let universal = ProfileMappings(bindings: universalBindings)
        var noPlayPause = ProfileMappings(bindings: universalBindings.filter { $0.button != .playPause })
        terminal.set(.useDefault, for: .tv, gesture: .tap)
        terminal.set(.useDefault, for: .tv, gesture: .hold)
        browser.set(.useDefault, for: .tv, gesture: .tap)
        browser.set(.useDefault, for: .tv, gesture: .hold)
        noPlayPause.set(.useDefault, for: .tv, gesture: .tap)
        noPlayPause.set(.useDefault, for: .tv, gesture: .hold)
        return [
            .default: universal,
            .terminal: terminal,
            .ghostty: terminal,
            .otty: terminal,
            .kitty: terminal,
            .chrome: browser,
            .edge: browser,
            .chatGPT: noPlayPause
        ]
    }()

    public static func allowedActions(for profile: AppProfile) -> [RemoteAction] {
        var actions: [RemoteAction] = [.none, .toggleVoiceTranscription, .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .confirm, .escape, .delete, .togglePlayPause, .toggleMute, .quitApplication, .adjustVolumeUp, .adjustVolumeDown, .switchApplication, .exitApplicationSwitcher, .launchSelectedApplication]
        if profile != .default { actions.insert(.useDefault, at: 1) }
        if profile.supportsTabs {
            actions.insert(.nextTerminalTab, at: 7)
            actions.insert(.previousTerminalTab, at: 8)
        }
        return actions
    }

    public func normalized() -> AppConfiguration {
        var copy = self
        copy.voiceInputMode = copy.voiceInputMode ?? .disabled
        copy.transcriptionSource = copy.transcriptionSource ?? .localSpeech
        copy.speechRecognitionLanguage = copy.speechRecognitionLanguage ?? .automatic
        copy.voiceTranscriptionTiming = copy.voiceTranscriptionTiming ?? .afterRecording
        copy.cloudTranscriptionProvider = copy.cloudTranscriptionProvider ?? .openAI
        var providers = copy.cloudProviders ?? [:]
        for provider in CloudProvider.allCases where providers[provider] == nil {
            providers[provider] = CloudProviderConfiguration()
        }
        copy.cloudProviders = providers
        for profile in AppProfile.allCases {
            var mapping = copy.mappings[profile] ?? ProfileMappings()
            let allowed = Set(Self.allowedActions(for: profile))
            mapping.bindings = mapping.bindings.map {
                let action: RemoteAction = $0.action == .activateChatGPT ? .launchSelectedApplication : $0.action
                return ButtonBinding(button: $0.button, gesture: $0.gesture, action: allowed.contains(action) ? action : .none)
            }
            copy.mappings[profile] = mapping
        }
        return copy
    }
}
