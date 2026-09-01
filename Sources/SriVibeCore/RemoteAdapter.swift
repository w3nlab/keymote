import Foundation

public struct HIDUsage: Hashable, Sendable {
    public let page: UInt32
    public let usage: UInt32

    public init(page: UInt32, usage: UInt32) {
        self.page = page
        self.usage = usage
    }
}

public protocol RemoteAdapter: Sendable {
    var identifier: String { get }
    var layoutID: String { get }
    var displayName: String { get }
    var vendorID: Int { get }
    var productID: Int { get }
    func button(for input: HIDUsage) -> RemoteButton?
}

/// The public HID input surface used by the USB-C Siri Remote (A2854).
/// Unknown usages are intentionally not treated as system commands until they
/// have been verified with a physical remote.
public struct AppleSiriRemoteA2854Adapter: RemoteAdapter {
    public let identifier = "apple-siri-remote-a2854"
    public let layoutID = "apple-siri-remote-a2854"
    public let displayName = "Apple Siri Remote (3rd generation)"
    public let vendorID = 0x004C
    public let productID = 0x0315

    public init() {}

    public func button(for input: HIDUsage) -> RemoteButton? {
        if input.page == 0x0C {
            switch input.usage {
            case 0x42: .up
            case 0x43: .down
            case 0x44: .left
            case 0x45: .right
            case 0x80: .center
            case 0xCD: .playPause
            case 0xE9: .volumeUp
            case 0xEA: .volumeDown
            case 0x60, 0x223: .tv
            case 0x04: .siri
            default: nil
            }
        } else if input.page == 0x01 && (input.usage == 0x86 || input.usage == 0x40) {
            .back
        } else {
            nil
        }
    }
}
