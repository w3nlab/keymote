import ApplicationServices
import IOKit.hid

enum PermissionManager {
    static func inputMonitoring(request: Bool) -> Bool {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted { return true }
        return request ? IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) : false
    }

    static func accessibility(request: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        guard request else { return false }
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}
