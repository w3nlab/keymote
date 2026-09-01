import AppKit
import SwiftUI
import SriVibeCore

@main
struct KeymoteApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusController: StatusBarController?
    private var windowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockVisibility(model.showsInDock)
        model.onDockVisibilityChanged = { [weak self] visible in self?.applyDockVisibility(visible) }
        applyAppearance(model.appearance)
        model.onAppearanceChanged = { [weak self] appearance in self?.applyAppearance(appearance) }
        windowController = SettingsWindowController(model: model)
        statusController = StatusBarController(
            model: model,
            showWindow: { [weak self] in self?.showMainWindow() },
            reconnect: { [weak self] in self?.model.reconnect() }
        )
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) { model.stop() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    private func showMainWindow() {
        windowController?.showCentered()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyDockVisibility(_ visible: Bool) {
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    private func applyAppearance(_ appearance: AppAppearance) {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
