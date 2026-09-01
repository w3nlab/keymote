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
        if mappingEditor == .layout {
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
        } else {
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
    }

    private var permissionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(t(model.inputMonitoringGranted ? "inputGranted" : "inputRequired"), systemImage: model.inputMonitoringGranted ? "checkmark.shield" : "exclamationmark.shield")
            Text(t("inputDescription"))
            Label(t(model.accessibilityGranted ? "accessibilityGranted" : "accessibilityRequired"), systemImage: model.accessibilityGranted ? "checkmark.shield" : "exclamationmark.shield")
            Text(t("accessibilityDescription"))
            HStack {
                Button(t("requestPermissions")) { model.refreshPermissions(request: true) }
                Button(t("refresh")) { model.refreshPermissions() }
            }
            Spacer()
        }.padding()
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

private struct MappingRow: View {
    @ObservedObject var model: AppModel
    let profile: AppProfile
    let button: RemoteButton

    var body: some View {
        VStack(alignment: .leading) {
            Text(button.title(model.language)).font(.headline)
            HStack {
                actionPicker(L10n.text("tap", model.language), gesture: .tap)
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
        case .arrowUp: L10n.text("up", language)
        case .arrowDown: L10n.text("down", language)
        case .arrowLeft: L10n.text("left", language)
        case .arrowRight: L10n.text("right", language)
        case .confirm: L10n.text("return", language)
        case .escape: L10n.text("escape", language)
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
