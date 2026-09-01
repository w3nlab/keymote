import Foundation
import SriVibeCore

enum L10n {
    static func text(_ key: String, _ language: AppLanguage) -> String {
        let english: [String: String] = [
            "device": "Device", "mappings": "Mappings", "permissions": "Permissions", "diagnostics": "Diagnostics",
            "supportedRemote": "Supported remote", "activeRemote": "Active remote", "noRemote": "No remote selected", "reconnect": "Reconnect selected remote",
            "application": "Application", "showInDock": "Show Keymote in the Dock", "language": "Language", "appearance": "Appearance",
            "hold": "Hold", "longPress": "Long press: %lld ms", "status": "Status",
            "editing": "Editing: %@", "automaticMappings": "Mappings are selected automatically from the frontmost app.", "currentlyActive": "Currently active: %@",
            "inputGranted": "Input Monitoring granted", "inputRequired": "Input Monitoring required", "inputDescription": "Allows Keymote to receive paired Siri Remote HID button events.",
            "accessibilityGranted": "Accessibility granted", "accessibilityRequired": "Accessibility required", "accessibilityDescription": "Allows Keymote to send configured keyboard actions to the frontmost application.",
            "requestPermissions": "Request permissions", "refresh": "Refresh", "runtimeStatus": "Runtime status", "currentProfile": "Current profile: %@", "noDiagnostics": "No diagnostic events yet.", "copyDiagnostics": "Copy diagnostics",
            "v1Scope": "Mac microphone transcription is available when enabled. Siri Remote microphone capture remains experimental and unavailable.", "tap": "Tap", "holdAction": "Hold",
            "default": "Default", "playPause": "Play / Pause", "noAction": "No action", "up": "Up arrow", "down": "Down arrow", "left": "Left arrow", "right": "Right arrow", "return": "Return", "escape": "Escape",
            "nextTab": "Next terminal tab", "previousTab": "Previous terminal tab", "switchApp": "Switch application", "exitSwitcher": "Exit application switcher", "activateChatGPT": "Activate ChatGPT",
            "system": "System", "light": "Light", "dark": "Dark", "english": "English", "chinese": "中文",
            "openSettings": "Open Settings…", "quit": "Quit Keymote", "waiting": "Waiting for a paired Siri Remote", "diagnosticMode": "Diagnostic input mode — no actions are injected", "connected": "Connected: %@", "accessibilityNeeded": "Accessibility permission is required to perform actions", "diagnosticsCopied": "Diagnostics copied to clipboard"
        ]
        let chinese: [String: String] = [
            "device": "设备", "mappings": "按键映射", "permissions": "权限", "diagnostics": "诊断",
            "supportedRemote": "支持的遥控器", "activeRemote": "当前遥控器", "noRemote": "未选择遥控器", "reconnect": "重新连接当前遥控器",
            "application": "应用", "showInDock": "在 Dock 中显示 Keymote", "language": "语言", "appearance": "外观",
            "hold": "长按", "longPress": "长按：%lld 毫秒", "status": "状态",
            "editing": "正在编辑：%@", "automaticMappings": "会根据前台应用自动选择按键映射。", "currentlyActive": "当前生效：%@",
            "inputGranted": "已授予输入监控权限", "inputRequired": "需要输入监控权限", "inputDescription": "允许 Keymote 接收已配对 Siri Remote 的 HID 按键事件。",
            "accessibilityGranted": "已授予辅助功能权限", "accessibilityRequired": "需要辅助功能权限", "accessibilityDescription": "允许 Keymote 向前台应用发送已配置的按键操作。",
            "requestPermissions": "请求权限", "refresh": "刷新", "runtimeStatus": "运行状态", "currentProfile": "当前 Profile：%@", "noDiagnostics": "暂无诊断事件。", "copyDiagnostics": "复制诊断信息",
            "v1Scope": "启用后可使用 Mac 麦克风转写；Siri Remote 麦克风采集仍为实验性功能，暂不可用。", "tap": "轻按", "holdAction": "长按",
            "default": "默认", "playPause": "播放 / 暂停", "noAction": "无操作", "up": "上方向键", "down": "下方向键", "left": "左方向键", "right": "右方向键", "return": "回车", "escape": "退出",
            "nextTab": "下一个终端标签页", "previousTab": "上一个终端标签页", "switchApp": "切换应用", "exitSwitcher": "退出应用切换", "activateChatGPT": "激活 ChatGPT",
            "system": "跟随系统", "light": "浅色", "dark": "深色", "english": "English", "chinese": "中文",
            "openSettings": "打开设置…", "quit": "退出 Keymote", "waiting": "正在等待已配对的 Siri Remote", "diagnosticMode": "诊断输入模式 — 不会发送任何操作", "connected": "已连接：%@", "accessibilityNeeded": "执行操作需要辅助功能权限", "diagnosticsCopied": "诊断信息已复制到剪贴板"
        ]
        return (language == .chinese ? chinese : english)[key] ?? english[key] ?? key
    }

    static func format(_ key: String, _ language: AppLanguage, _ arguments: CVarArg...) -> String {
        String(format: text(key, language), arguments: arguments)
    }
}
