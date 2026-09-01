import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let model: AppModel
    private let showWindow: () -> Void
    private let reconnect: () -> Void
    private var observation: AnyCancellable?

    init(model: AppModel, showWindow: @escaping () -> Void, reconnect: @escaping () -> Void) {
        self.model = model
        self.showWindow = showWindow
        self.reconnect = reconnect
        super.init()
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        observation = model.$statusRevision.sink { [weak self] _ in self?.render() }
        render()
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() }
        else { showWindow() }
    }

    private func render() {
        item.button?.image = NSImage(systemSymbolName: model.statusSymbol, accessibilityDescription: "Keymote")
        item.button?.toolTip = "Keymote — \(model.statusText)"
    }

    private func showMenu() {
        let menu = NSMenu()
        let state = NSMenuItem(title: model.statusText, action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("openSettings", model.language), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: L10n.text("reconnect", model.language), action: #selector(reconnectRemote), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("quit", model.language), action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettings() { showWindow() }
    @objc private func reconnectRemote() { reconnect() }
    @objc private func quit() { NSApp.terminate(nil) }
}
