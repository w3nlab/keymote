import Foundation
import IOKit.hid
import SriVibeCore

struct RemoteDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let vendorID: Int
    let productID: Int
    let layoutID: String
}

/// A2854 exposes several Bluetooth HID interfaces for one physical remote. This
/// monitor discovers the relevant primary usage pages, opens each interface, and
/// collapses their duplicate button reports to a single logical transition.
final class HIDRemoteMonitor {
    var onDevicesChanged: (([RemoteDevice]) -> Void)?
    var onButtonEvent: ((RemoteButton, Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onDeviceDisconnected: (() -> Void)?

    private let adapter: any RemoteAdapter = AppleSiriRemoteA2854Adapter()
    private var manager: IOHIDManager?
    private var selectedID: String?
    private var interfaces: [String: IOHIDDevice] = [:]
    private var pressedElements: [String: RemoteButton] = [:]
    private var buttonPressCounts: [RemoteButton: Int] = [:]
    private var diagnosedUnknownUsages: Set<HIDUsage> = []

    func start(selectedID: String?) {
        stop()
        self.selectedID = selectedID
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let pages: [Int] = [0x0C, 0x0D, 0xFF00, 0x01]
        let matches = pages.map { page in
            [kIOHIDVendorIDKey as String: adapter.vendorID, kIOHIDPrimaryUsagePageKey as String: page] as [String: Any]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatched, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, Unmanaged.passUnretained(self).toOpaque())

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            onStatus?("Could not listen for Siri Remote HID devices (\(result))")
            return
        }
        self.manager = manager
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        onStatus?("Searching for paired Apple Siri Remote (A2854)")
    }

    func stop() {
        for device in interfaces.values {
            IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        interfaces.removeAll()
        pressedElements.removeAll()
        buttonPressCounts.removeAll()
        diagnosedUnknownUsages.removeAll()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    func selectDevice(_ id: String?) {
        selectedID = id
        pressedElements.removeAll()
        buttonPressCounts.removeAll()
        onStatus?(id == nil ? "Select a Siri Remote" : "Selected Siri Remote")
    }

    func reconnect() { start(selectedID: selectedID) }

    private func matched(_ device: IOHIDDevice) {
        guard productID(for: device) == adapter.productID else { return }
        let key = interfaceKey(for: device)
        guard interfaces[key] == nil else { return }

        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            onDiagnostic?("Could not exclusively open HID interface \(usageLabel(for: device)): \(result)")
            onStatus?("Input Monitoring is required to access the Siri Remote")
            return
        }
        IOHIDDeviceRegisterInputValueCallback(device, Self.inputValue, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        interfaces[key] = device
        onDiagnostic?("Opened A2854 HID interface \(usageLabel(for: device))")
        refreshDevices()
    }

    private func removed(_ device: IOHIDDevice) {
        let remoteID = descriptor(for: device).id
        let key = interfaceKey(for: device)
        guard interfaces.removeValue(forKey: key) != nil else { return }
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        pressedElements.removeAll()
        buttonPressCounts.removeAll()
        refreshDevices()
        if selectedID == remoteID && !interfaces.values.contains(where: { descriptor(for: $0).id == remoteID }) {
            onDeviceDisconnected?()
            onStatus?("Siri Remote disconnected")
        }
    }

    private func refreshDevices() {
        let grouped = Dictionary(grouping: interfaces.values.map(descriptor(for:)), by: \.id)
        onDevicesChanged?(grouped.values.compactMap(\.first).sorted { $0.name < $1.name })
    }

    private func descriptor(for device: IOHIDDevice) -> RemoteDevice {
        let serial = stringProperty(device, key: kIOHIDSerialNumberKey)
            ?? stringProperty(device, key: kIOHIDLocationIDKey)
            ?? "unknown"
        let product = stringProperty(device, key: kIOHIDProductKey) ?? adapter.displayName
        return RemoteDevice(id: "\(adapter.identifier)-\(serial)", name: product, vendorID: adapter.vendorID, productID: adapter.productID, layoutID: adapter.layoutID)
    }

    private func productID(for device: IOHIDDevice) -> Int? {
        numberProperty(device, key: kIOHIDProductIDKey)
    }

    private func interfaceKey(for device: IOHIDDevice) -> String {
        let location = stringProperty(device, key: kIOHIDLocationIDKey) ?? "unknown"
        return "\(descriptor(for: device).id)-\(location)-\(usageLabel(for: device))"
    }

    private func usageLabel(for device: IOHIDDevice) -> String {
        let page = numberProperty(device, key: kIOHIDPrimaryUsagePageKey) ?? -1
        let usage = numberProperty(device, key: kIOHIDPrimaryUsageKey) ?? -1
        return String(format: "0x%X/0x%X", page, usage)
    }

    private func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        return String(describing: value)
    }

    private func numberProperty(_ device: IOHIDDevice, key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let selectedID, descriptor(for: device).id == selectedID else { return }
        let input = HIDUsage(page: IOHIDElementGetUsagePage(element), usage: IOHIDElementGetUsage(element))
        guard let button = adapter.button(for: input) else {
            if diagnosedUnknownUsages.insert(input).inserted {
                onDiagnostic?("Ignored HID usage page=0x\(String(input.page, radix: 16)) usage=0x\(String(input.usage, radix: 16))")
            }
            return
        }

        let key = "\(Unmanaged.passUnretained(element).toOpaque())"
        let isPressed = IOHIDValueGetIntegerValue(value) != 0
        if isPressed {
            guard pressedElements[key] == nil else { return }
            pressedElements[key] = button
            buttonPressCounts[button, default: 0] += 1
            guard buttonPressCounts[button] == 1 else { return }
        } else {
            guard let originalButton = pressedElements.removeValue(forKey: key) else { return }
            let nextCount = max(0, (buttonPressCounts[originalButton] ?? 1) - 1)
            buttonPressCounts[originalButton] = nextCount
            guard nextCount == 0 else { return }
        }
        onButtonEvent?(button, isPressed)
    }

    private static let deviceMatched: IOHIDDeviceCallback = { context, _, _, device in
        Unmanaged<HIDRemoteMonitor>.fromOpaque(context!).takeUnretainedValue().matched(device)
    }
    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        Unmanaged<HIDRemoteMonitor>.fromOpaque(context!).takeUnretainedValue().removed(device)
    }
    private static let inputValue: IOHIDValueCallback = { context, _, _, value in
        Unmanaged<HIDRemoteMonitor>.fromOpaque(context!).takeUnretainedValue().receive(value)
    }
}
