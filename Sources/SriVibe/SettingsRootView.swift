import SwiftUI
import SriVibeCore

struct SettingsRootView: View {
    @ObservedObject var model: AppModel
    @State private var selectedProfile: AppProfile = .default
    @State private var mappingEditor: MappingEditor = .layout
    @State private var selectedButton: RemoteButton = .center

    private enum MappingEditor: String, CaseIterable, Identifiable {
        case layout, list
        var id: Self { self }
    }

    var body: some View {
        TabView {
            deviceView.tabItem { Label(t("device"), systemImage: "dot.radiowaves.left.and.right") }
            mappingsView.tabItem { Label(t("mappings"), systemImage: "rectangle.3.group") }
            cloudView.tabItem { Label(model.language == .chinese ? "云端模型" : "Cloud models", systemImage: "cloud") }
            permissionsView.tabItem { Label(t("permissions"), systemImage: "lock.shield") }
            diagnosticsView.tabItem { Label(t("diagnostics"), systemImage: "stethoscope") }
        }
        .frame(minWidth: 680, minHeight: 460)
        .padding()
        .preferredColorScheme(model.preferredColorScheme)
    }

    private var deviceView: some View {
        Form {
            Section(t("supportedRemote")) {
                Text("Apple Siri Remote (3rd generation, A2854)")
                Picker(t("activeRemote"), selection: Binding(
                    get: { model.configuration.selectedDeviceID ?? "" },
                    set: { model.selectDevice($0.isEmpty ? nil : $0) }
                )) {
                    Text(t("noRemote")).tag("")
                    ForEach(model.devices) { device in
                        Text("\(device.name) — \(device.id)").tag(device.id)
                    }
                }
                Button(t("reconnect")) { model.reconnect() }
            }
            Section(t("application")) {
                Toggle(t("showInDock"), isOn: Binding(
                    get: { model.showsInDock },
                    set: { model.setShowsInDock($0) }
                ))
                Picker(t("language"), selection: Binding(get: { model.language }, set: { model.setLanguage($0) })) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.title(model.language)).tag($0) }
                }
                Picker(t("appearance"), selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.title(model.language)).tag($0) }
                }
                HStack {
                    Text(model.language == .chinese ? "TV 键单击应用：\(model.tvApplicationName)" : "TV button app: \(model.tvApplicationName)")
                    Spacer()
                    Button(model.language == .chinese ? "选择应用…" : "Choose app…") { model.chooseTVApplication() }
                }
            }
            Section(model.language == .chinese ? "语音转写" : "Voice transcription") {
                Picker(model.language == .chinese ? "输入模式" : "Input mode", selection: Binding(get: { model.voiceInputMode }, set: { model.setVoiceInputMode($0) })) {
                    Text(model.language == .chinese ? "关闭" : "Off").tag(VoiceInputMode.disabled)
                    Text(model.language == .chinese ? "Mac 麦克风转写" : "Mac microphone transcription").tag(VoiceInputMode.macMicrophone)
                    Text(model.language == .chinese ? "遥控器麦克风（尚未实现）" : "Siri Remote microphone (not implemented)")
                        .tag(VoiceInputMode.remoteMicrophoneExperimental)
                        .disabled(true)
                }
                if model.voiceInputMode == .macMicrophone {
                    Picker(model.language == .chinese ? "识别来源" : "Recognition source", selection: Binding(get: { model.transcriptionSource }, set: { model.setTranscriptionSource($0) })) {
                        Text(model.language == .chinese ? "macOS 本地 Speech" : "macOS local Speech").tag(TranscriptionSource.localSpeech)
                        Text(model.language == .chinese ? "云端模型" : "Cloud model").tag(TranscriptionSource.cloud)
                    }
                    Picker(model.language == .chinese ? "语音识别语言" : "Speech recognition language", selection: Binding(get: { model.speechRecognitionLanguage }, set: { model.setSpeechRecognitionLanguage($0) })) {
                        Text(model.language == .chinese ? "跟随 macOS" : "Follow macOS").tag(SpeechRecognitionLanguage.automatic)
                        Text("English (United States)").tag(SpeechRecognitionLanguage.englishUS)
                        Text("中文（简体，中国大陆）").tag(SpeechRecognitionLanguage.chineseSimplified)
                    }
                    Picker(model.language == .chinese ? "转写时机" : "Transcription timing", selection: Binding(get: { model.voiceTranscriptionTiming }, set: { model.setVoiceTranscriptionTiming($0) })) {
                        Text(model.language == .chinese ? "录音结束后" : "After recording").tag(VoiceTranscriptionTiming.afterRecording)
                        Text(model.language == .chinese ? "实时转写" : "Realtime").tag(VoiceTranscriptionTiming.realtime)
                    }
                    if model.transcriptionSource == .cloud {
                        Picker(model.language == .chinese ? "云端转写提供者" : "Cloud transcription provider", selection: Binding(get: { model.cloudTranscriptionProvider }, set: { model.setCloudTranscriptionProvider($0) })) {
                            ForEach(CloudProvider.allCases.filter(\.supportsTranscription), id: \.self) { provider in
                                Text(provider.title).tag(provider)
                            }
                        }
                    }
                    if model.transcriptionSource == .cloud && model.voiceTranscriptionTiming == .realtime {
                        Text(model.language == .chinese ? "云端模式会在停止录音后统一提交；实时转写目前仅适用于 macOS 本地 Speech。" : "Cloud audio is submitted after recording; realtime transcription currently applies only to macOS local Speech.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.voiceTranscriptionTiming == .realtime, !model.liveTranscript.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.language == .chinese ? "实时转写" : "Live transcription").font(.caption).foregroundStyle(.secondary)
                            Text(model.liveTranscript).textSelection(.enabled)
                        }
                    }
                    Text(model.language == .chinese ? "将 Siri 轻按设为“语音转写”；非默认 Profile 可设为“默认”以继承默认 Profile。" : "Set Siri tap to Voice transcription; non-default profiles can use Default to inherit the Default profile.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section(t("hold")) {
                Stepper(
                    L10n.format("longPress", model.language, model.configuration.holdThresholdMilliseconds),
                    value: Binding(
                        get: { model.configuration.holdThresholdMilliseconds },
                        set: { model.updateHoldThreshold($0) }
                    ),
                    in: 300...1_500,
                    step: 50
                )
                Stepper(
                    L10n.format("doubleTapInterval", model.language, model.configuration.doubleTapIntervalMilliseconds ?? 300),
                    value: Binding(
                        get: { model.configuration.doubleTapIntervalMilliseconds ?? 300 },
                        set: { model.updateDoubleTapInterval($0) }
                    ),
                    in: 150...800,
                    step: 25
                )
            }
            Section(t("status")) { Text(model.statusText).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }

    private var mappingsView: some View {
        HStack(alignment: .top, spacing: 0) {
            List(AppProfile.allCases, id: \.self, selection: $selectedProfile) { profile in
                Text(profile.title(model.language))
            }
            .frame(width: 150)
            .frame(maxHeight: .infinity)
            Divider()
            VStack(spacing: 0) {
                Picker("", selection: $mappingEditor) {
                    Text(model.language == .chinese ? "遥控器布局" : "Remote layout").tag(MappingEditor.layout)
                    Text(model.language == .chinese ? "表单列表" : "Form list").tag(MappingEditor.list)
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                mappingContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var mappingContent: some View {
        // Keep both editor hierarchies alive. Switching a conditional view here
        // used to tear down and recreate all of the native Picker controls,
        // which is noticeably expensive on macOS.
        ZStack(alignment: .topLeading) {
            layoutEditor
                .opacity(mappingEditor == .layout ? 1 : 0)
                .allowsHitTesting(mappingEditor == .layout)
                .accessibilityHidden(mappingEditor != .layout)
            listEditor
                .opacity(mappingEditor == .list ? 1 : 0)
                .allowsHitTesting(mappingEditor == .list)
                .accessibilityHidden(mappingEditor != .list)
        }
    }

    @ViewBuilder
    private var layoutEditor: some View {
        if RemoteLayoutRegistry.supports(model.selectedDevice?.layoutID) || model.selectedDevice == nil {
            ScrollView([.horizontal, .vertical]) {
                InteractiveRemoteLayout(model: model, profile: selectedProfile, selectedButton: $selectedButton)
            }
        } else {
            ContentUnavailableView(
                model.language == .chinese ? "该设备暂无互动布局" : "No interactive layout for this device",
                systemImage: "rectangle.dashed",
                description: Text(model.language == .chinese ? "请切换到表单列表以配置按键。" : "Use the form list to configure this device.")
            )
        }
    }

    private var listEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.format("editing", model.language, selectedProfile.title(model.language))).font(.headline)
                Text(t("automaticMappings")).foregroundStyle(.secondary)
                Text(L10n.format("currentlyActive", model.language, model.currentProfile.title(model.language))).foregroundStyle(.secondary)
                ForEach(RemoteButton.allCases, id: \.self) { button in
                    MappingRow(model: model, profile: selectedProfile, button: button)
                }
            }.padding()
        }
    }

    private var permissionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(t(model.inputMonitoringGranted ? "inputGranted" : "inputRequired"), systemImage: model.inputMonitoringGranted ? "checkmark.shield" : "exclamationmark.shield")
            Text(t("inputDescription"))
            Label(t(model.accessibilityGranted ? "accessibilityGranted" : "accessibilityRequired"), systemImage: model.accessibilityGranted ? "checkmark.shield" : "exclamationmark.shield")
            Text(t("accessibilityDescription"))
            Label(model.microphoneGranted ? (model.language == .chinese ? "已授予麦克风权限" : "Microphone permission granted") : (model.language == .chinese ? "需要麦克风权限" : "Microphone permission required"), systemImage: model.microphoneGranted ? "checkmark.shield" : "exclamationmark.shield")
            Text(model.language == .chinese ? "允许 Keymote 使用 Mac 麦克风录音。" : "Allows Keymote to record from the Mac microphone.")
            Label(model.speechRecognitionGranted ? (model.language == .chinese ? "已授予语音识别权限" : "Speech Recognition granted") : (model.language == .chinese ? "需要语音识别权限" : "Speech Recognition permission required"), systemImage: model.speechRecognitionGranted ? "checkmark.shield" : "exclamationmark.shield")
            Text(model.language == .chinese ? "允许使用 macOS 本地 Speech 转写。" : "Allows macOS local Speech transcription.")
            HStack {
                Button(t("requestPermissions")) { model.refreshPermissions(request: true) }
                Button(model.language == .chinese ? "请求语音权限" : "Request voice permissions") { model.requestVoicePermissions() }
                Button(t("refresh")) { model.refreshPermissions() }
            }
            Spacer()
        }.padding()
    }

    private var cloudView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.language == .chinese ? "云端模型配置" : "Cloud model configuration").font(.title3.weight(.semibold))
                Text(model.language == .chinese ? "凭据会以加密形式保存在 Keymote 配置中；本机 Keychain 保存解密密钥。" : "Credentials are encrypted in Keymote configuration; this Mac's Keychain keeps the decryption key.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(CloudProvider.allCases, id: \.self) { provider in
                    CloudProviderCard(model: model, provider: provider)
                }
            }.padding()
        }
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("runtimeStatus")).font(.headline)
            Text(model.statusText)
            Text(L10n.format("currentProfile", model.language, model.currentProfile.title(model.language)))
            if model.diagnostics.isEmpty {
                Text(t("noDiagnostics")).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(model.diagnostics.suffix(20).joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 220)
            }
            Button(t("copyDiagnostics")) { model.copyDiagnostics() }
            Text(t("v1Scope"))
                .foregroundStyle(.secondary)
            Spacer()
        }.padding()
    }

    private func t(_ key: String) -> String { L10n.text(key, model.language) }
}

private extension CloudProvider {
    var title: String {
        switch self {
        case .anthropic: "Claude (Anthropic API)"
        case .openAI: "OpenAI API"
        case .openRouter: "OpenRouter"
        }
    }
}

private struct CloudProviderCard: View {
    @ObservedObject var model: AppModel
    let provider: CloudProvider
    @State private var enabled = false
    @State private var apiKey = ""
    @State private var transcriptionModel = ""
    @State private var textModel = ""
    @State private var loaded = false

    var body: some View {
        GroupBox(provider.title) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(model.language == .chinese ? "启用" : "Enabled", isOn: $enabled)
                SecureField(model.language == .chinese ? "API Key（留空则保留现有密钥）" : "API Key (leave blank to keep existing key)", text: $apiKey)
                if provider.supportsTranscription {
                    TextField(model.language == .chinese ? "转写模型 ID" : "Transcription model ID", text: $transcriptionModel)
                } else {
                    Text(model.language == .chinese ? "首版仅支持文本生成；不能直接用于语音转写。" : "Text generation only in v1; not available for voice transcription.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField(model.language == .chinese ? "文本模型 ID" : "Text model ID", text: $textModel)
                HStack {
                    Button(model.language == .chinese ? "保存" : "Save") { save() }
                    Button(model.language == .chinese ? "测试连接" : "Test connection") { save(); model.testCloudProvider(provider) }
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        guard !loaded else { return }
        let config = model.cloudConfiguration(for: provider)
        enabled = config.isEnabled
        transcriptionModel = config.transcriptionModel
        textModel = config.textModel
        loaded = true
    }

    private func save() {
        model.saveCloudConfiguration(
            CloudProviderConfiguration(isEnabled: enabled, encryptedAPIKey: model.cloudConfiguration(for: provider).encryptedAPIKey, transcriptionModel: transcriptionModel, textModel: textModel),
            provider: provider,
            plainAPIKey: apiKey.isEmpty ? nil : apiKey
        )
        apiKey = ""
    }
}

private struct MappingRow: View {
    @ObservedObject var model: AppModel
    let profile: AppProfile
    let button: RemoteButton

    var body: some View {
        VStack(alignment: .leading) {
            Text(button.title(model.language)).font(.headline)
            HStack {
                actionPicker(L10n.text("tap", model.language), gesture: .tap)
                actionPicker(L10n.text("doubleTap", model.language), gesture: .doubleTap)
                actionPicker(L10n.text("holdAction", model.language), gesture: .hold)
            }
        }
    }

    private func actionPicker(_ label: String, gesture: ButtonGesture) -> some View {
        Picker(label, selection: Binding(
            get: { model.configuredAction(for: button, gesture: gesture, profile: profile) },
            set: { model.setAction($0, for: button, gesture: gesture, profile: profile) }
        )) {
            ForEach(AppConfiguration.allowedActions(for: profile), id: \.self) { action in Text(actionTitle(action)).tag(action) }
        }
        .frame(maxWidth: 260)
    }

    private func actionTitle(_ action: RemoteAction) -> String {
        guard action == .launchSelectedApplication else { return action.title(model.language) }
        return model.language == .chinese ? "启动 \(model.tvApplicationName)" : "Launch \(model.tvApplicationName)"
    }
}

private extension AppProfile {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .default: L10n.text("default", language)
        case .terminal: "Terminal"
        case .ghostty: "Ghostty"
        case .otty: "Otty"
        case .kitty: "Kitty"
        case .chrome: "Chrome"
        case .edge: "Edge"
        case .chatGPT: "ChatGPT"
        }
    }
}

extension RemoteButton {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .playPause: L10n.text("playPause", language)
        case .mute: language == .chinese ? "静音" : "Mute"
        default: rawValue.capitalized
        }
    }
}

extension RemoteAction {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .none: L10n.text("noAction", language)
        case .useDefault: language == .chinese ? "默认" : "Default"
        case .toggleVoiceTranscription: language == .chinese ? "语音转写" : "Voice transcription"
        case .arrowUp: L10n.text("up", language)
        case .arrowDown: L10n.text("down", language)
        case .arrowLeft: L10n.text("left", language)
        case .arrowRight: L10n.text("right", language)
        case .confirm: L10n.text("return", language)
        case .escape: L10n.text("escape", language)
        case .delete: L10n.text("delete", language)
        case .nextTerminalTab: L10n.text("nextTab", language)
        case .previousTerminalTab: L10n.text("previousTab", language)
        case .togglePlayPause: language == .chinese ? "播放 / 暂停" : "Play / Pause"
        case .toggleMute: language == .chinese ? "切换静音" : "Toggle mute"
        case .quitApplication: language == .chinese ? "退出当前应用" : "Quit current application"
        case .adjustVolumeUp: language == .chinese ? "调高系统音量" : "Increase system volume"
        case .adjustVolumeDown: language == .chinese ? "调低系统音量" : "Decrease system volume"
        case .switchApplication: L10n.text("switchApp", language)
        case .exitApplicationSwitcher: L10n.text("exitSwitcher", language)
        case .launchSelectedApplication: language == .chinese ? "选择并启动应用…" : "Choose and launch application…"
        case .activateChatGPT: L10n.text("noAction", language)
        }
    }
}

private extension AppLanguage {
    func title(_ language: AppLanguage) -> String { L10n.text(self == .english ? "english" : "chinese", language) }
}

private extension AppAppearance {
    func title(_ language: AppLanguage) -> String { L10n.text(rawValue, language) }
}
