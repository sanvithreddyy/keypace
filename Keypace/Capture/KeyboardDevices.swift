import Foundation
import IOKit.hid
import KeypaceCore

/// Watches HID keyboards so each keystroke can be tied to the physical keyboard it came from.
/// HID values arrive just before the matching key event, so the last keyboard with a key-down
/// is the source of the next keystroke.
final class KeyboardDevices {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var started = false

    /// The keyboard behind the most recent key-down.
    private(set) var lastUsed: KeyboardRecord?

    func start() {
        guard !started else { return }
        started = true
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        IOHIDManagerSetInputValueMatching(manager, [kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            let devices = Unmanaged<KeyboardDevices>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated { devices.handle(value) }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    /// Identifiers of keyboards connected right now.
    var connectedIDs: Set<String> {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return Set(devices.map { Self.record(for: $0).id })
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usage = IOHIDElementGetUsage(element)
        // Usages 4–231 are keys; 1 means pressed.
        guard (4...231).contains(usage), IOHIDValueGetIntegerValue(value) == 1 else { return }
        lastUsed = Self.record(for: IOHIDElementGetDevice(element))
    }

    private static func record(for device: IOHIDDevice) -> KeyboardRecord {
        func property<T>(_ key: String) -> T? { IOHIDDeviceGetProperty(device, key as CFString) as? T }
        let vendor: Int = property(kIOHIDVendorIDKey) ?? 0
        let product: Int = property(kIOHIDProductIDKey) ?? 0
        let transport: String = property(kIOHIDTransportKey) ?? ""
        let builtIn = (property(kIOHIDBuiltInKey) as Bool?) ?? ["SPI", "FIFO"].contains(transport)
        let name: String = property(kIOHIDProductKey) ?? (builtIn ? "Built-in Keyboard" : "Keyboard")
        // Vendor and product identify the model and the serial number separates two of the same model.
        // Some keyboards, including Apple's built-in one, report neither ID; their name stands in.
        let serial = (property(kIOHIDSerialNumberKey) as String?).flatMap { $0.isEmpty ? nil : $0 }
        let model = vendor == 0 && product == 0 ? name : "\(vendor):\(product)"
        let id = [model, serial].compactMap { $0 }.joined(separator: ":")
        return KeyboardRecord(id: id, name: name, isBuiltIn: builtIn, lastSeen: .now)
    }
}
