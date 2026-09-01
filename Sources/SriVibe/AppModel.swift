import AppKit
import Combine
import os
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
    var onDockVisibilityChanged: ((Bool) -> Void)?
    var onAppearanceChanged: ((AppAppearance) -> Void)?

    private let store = ConfigurationStore()
    private let monitor = HIDRemoteMonitor()
    private let executor = ActionExecutor()
    private let nativeMediaEventSuppressor = NativeMediaEventSuppressor()
    private let logger = Logger(subsystem: "app.keymote.remote", category: "runtime")
    private let diagnosticInputMode = CommandLine.arguments.contains("--diagnose-input")
    private var gestureEngine: ButtonGestureEngine
    private var holdTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?

    init() {
        let loaded = ConfigurationStore().load()
        configuration = loaded
        gestureEngine = ButtonGestureEngine(holdThresholdMilliseconds: loaded.holdThresholdMilliseconds)
        monitor.onDevicesChanged = { [weak self] devices in Task { @MainActor in self?.setDevices(devices) } }
        monitor.onButtonEvent = { [weak self] button, isPressed in Task { @MainActor in self?.handle(button, isPressed: isPressed) } }
        monitor.onStatus = { [weak self] message in Task { @MainActor in self?.lastMessage = message } }
        monitor.onDiagnostic = { [weak self] line in Task { @MainActor in self?.recordDiagnostic(line) } }
        monitor.onDeviceDisconnected = { [weak self] in Task { @MainActor in self?.gestureEngine.cancelAll() } }
    }

    var selectedDevice: RemoteDevice? { devices.first { $0.id == configuration.selectedDeviceID } }
    var showsInDock: Bool { configuration.showsInDock ?? true }
    var language: AppLanguage { configuration.interfaceLanguage ?? .english }
    var appearance: AppAppearance { configuration.appearance ?? .system }
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
        nativeMediaEventSuppressor.start()
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
        executor.cancelApplicationSwitcher()
        executor.stopVolumeAdjustment()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    }

    func refreshPermissions(request: Bool = false) {
        inputMonitoringGranted = PermissionManager.inputMonitoring(request: request)
        accessibilityGranted = PermissionManager.accessibility(request: request)
        statusRevision += 1
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
