import AppKit
import SriVibeCore

final class ActionExecutor {
    private var applicationSwitcherActive = false
    private var volumeTimer: Timer?
    var isApplicationSwitcherActive: Bool { applicationSwitcherActive }

    deinit { cancelApplicationSwitcher() }

    func execute(_ action: RemoteAction, for profile: AppProfile, tvApplicationBundleIdentifier: String?) -> String {
        switch action {
        case .none: return "No action assigned"
        case .useDefault: return "Default action unavailable"
        case .arrowUp: key(126); return "Up"
        case .arrowDown: key(125); return "Down"
        case .arrowLeft: key(123); return "Left"
        case .arrowRight: key(124); return "Right"
        case .confirm: key(36); return "Return"
        case .escape: key(53); return "Escape"
        case .nextTerminalTab:
            sendNextTerminalTabShortcut(for: profile)
            return "Next terminal tab"
        case .previousTerminalTab:
            sendPreviousTerminalTabShortcut(for: profile)
            return "Previous terminal tab"
        case .togglePlayPause: postMediaKey(16); return "Play/Pause"
        case .toggleMute: postMediaKey(7); return "Toggle mute"
        case .quitApplication: key(12, flags: [.maskCommand]); return "Quit current application"
        case .switchApplication: return beginApplicationSwitcher()
        case .exitApplicationSwitcher: return cancelApplicationSwitcher()
        case .adjustVolumeUp: beginVolumeAdjustment(up: true); return "Increasing system volume"
        case .adjustVolumeDown: beginVolumeAdjustment(up: false); return "Decreasing system volume"
        case .launchSelectedApplication: return activateApplication(bundleIdentifier: tvApplicationBundleIdentifier ?? "com.openai.chat")
        case .activateChatGPT: return "Legacy action unavailable"
        }
    }

    func moveApplicationSwitcherSelection(forward: Bool) -> String {
        guard applicationSwitcherActive else { return "Application switcher is not active" }
        key(48, flags: forward ? [.maskCommand] : [.maskCommand, .maskShift])
        return forward ? "Next application" : "Previous application"
    }

    func confirmApplicationSwitcher() -> String {
        guard applicationSwitcherActive else { return "Application switcher is not active" }
        releaseCommandKey()
        applicationSwitcherActive = false
        return "Selected application"
    }

    func stopVolumeAdjustment() { volumeTimer?.invalidate(); volumeTimer = nil }

    @discardableResult
    func cancelApplicationSwitcher() -> String {
        guard applicationSwitcherActive else { return "Application switcher is not active" }
        key(53, flags: [.maskCommand])
        releaseCommandKey()
        applicationSwitcherActive = false
        return "Cancelled application switch"
    }

    private func key(_ code: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func beginApplicationSwitcher() -> String {
        guard !applicationSwitcherActive else { return "Application switcher is already active" }
        postKey(55, isDown: true, flags: [.maskCommand]) // Left Command
        key(48, flags: [.maskCommand]) // Tab
        applicationSwitcherActive = true
        return "Application switcher: use left/right, centre to select, Back to cancel"
    }

    private func releaseCommandKey() {
        postKey(55, isDown: false) // Left Command
    }

    private func postKey(_ code: CGKeyCode, isDown: Bool, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private func beginVolumeAdjustment(up: Bool) {
        stopVolumeAdjustment()
        postMediaKey(up ? 0 : 1)
        volumeTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.postMediaKey(up ? 0 : 1) }
    }

    private func postMediaKey(_ keyCode: Int) {
        for state in [0xA, 0xB] {
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: .deviceIndependentFlagsMask, timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (keyCode << 16) | (state << 8), data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private func sendNextTerminalTabShortcut(for profile: AppProfile) {
        if profile == .chrome || profile == .edge {
            key(124, flags: [.maskCommand, .maskAlternate])
        } else if profile == .ghostty || profile == .otty {
            // Ghostty and Otty use Command-Shift-] for the next tab on macOS.
            key(30, flags: [.maskCommand, .maskShift])
        } else {
            key(48, flags: [.maskControl])
        }
    }

    private func sendPreviousTerminalTabShortcut(for profile: AppProfile) {
        if profile == .chrome || profile == .edge {
            key(123, flags: [.maskCommand, .maskAlternate])
        } else if profile == .ghostty || profile == .otty {
            // Ghostty and Otty use Command-Shift-[ for the previous tab on macOS.
            key(33, flags: [.maskCommand, .maskShift])
        } else {
            key(48, flags: [.maskControl, .maskShift])
        }
    }

    private func activateApplication(bundleIdentifier: String) -> String {
        let bundleID = bundleIdentifier
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return "Selected application is not installed"
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return "Opening and activating application"
    }
}
