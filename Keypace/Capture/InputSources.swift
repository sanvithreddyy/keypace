import Carbon
import Foundation
import KeypaceCore

/// The active keyboard input source, and what each key types under it.
final class InputSources {
    private(set) var current: InputSourceRecord?
    /// Cached labels, keyed by layout (nil for the active one) and key code.
    private var labels: [String?: [UInt16: String]] = [:]
    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// The character a key types with no modifiers, uppercased; empty when it types nothing visible.
    /// - Parameter inputSourceID: the layout to label with; nil for the active layout.
    func label(for keyCode: UInt16, inputSourceID: String? = nil) -> String {
        if let cached = labels[inputSourceID]?[keyCode] { return cached }
        let layout = inputSourceID.flatMap(Self.layoutSource) ?? TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let label = layout.flatMap { Self.translate(keyCode, with: $0) }?.uppercased() ?? ""
        labels[inputSourceID, default: [:]][keyCode] = label
        return label
    }

    private func refresh() {
        labels = [:]
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let id = Self.string(source, kTISPropertyInputSourceID) else {
            current = nil
            return
        }
        let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
        let labels = layout.map { layout in
            Dictionary(uniqueKeysWithValues: KeyboardGeometry.keys.compactMap { key in
                Self.translate(key.keyCode, with: layout).map { (key.keyCode, $0.uppercased()) }
            })
        }
        current = InputSourceRecord(id: id, name: Self.string(source, kTISPropertyLocalizedName) ?? id, lastSeen: .now, labels: labels)
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    /// The installed input source with this identifier, if it carries a key layout.
    private static func layoutSource(id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return nil }
        return sources.first { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) != nil }
    }

    private static func translate(_ keyCode: UInt16, with source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: characters, count: length)
            // Tab, Return and Delete translate to control characters, which aren't labels.
            return text.unicodeScalars.allSatisfy({ $0.properties.generalCategory != .control }) ? text : nil
        }
    }
}
