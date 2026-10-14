import Carbon
import Foundation
import KeypaceCore

/// The active keyboard input source, and what each key types under it.
final class InputSources {
    private(set) var current: InputSourceRecord?
    private var labels: [UInt16: String] = [:]
    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// The character a key types with no modifiers, uppercased; named keys get their name.
    func label(for keyCode: UInt16) -> String {
        if let named = Self.namedKeys[keyCode] { return named }
        if let cached = labels[keyCode] { return cached }
        let label = Self.translate(keyCode)?.uppercased() ?? ""
        labels[keyCode] = label
        return label
    }

    private func refresh() {
        labels = [:]
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = Self.string(source, kTISPropertyInputSourceID) else {
            current = nil
            return
        }
        current = InputSourceRecord(id: id, name: Self.string(source, kTISPropertyLocalizedName) ?? id, lastSeen: .now)
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func translate(_ keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }

    private static let namedKeys: [UInt16: String] = [
        36: "return", 48: "tab", 49: "space", 51: "delete", 53: "esc", 56: "shift", 57: "caps lock", 60: "shift",
    ]
}
