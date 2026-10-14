import AppKit
import CoreGraphics

/// Facts about a key-down event that the rest of the app may keep. Never includes the character.
struct ObservedKey {
    var keyCode: UInt16
    /// Seconds since boot, the same clock as `ProcessInfo.systemUptime`.
    var time: Double
    var text: String
    var commandOrControl: Bool
    var isRepeat: Bool
    /// Where the event came from; used to tell real keystrokes from posted ones.
    var sourceStateID: Int64
    var sourceProcessID: Int64
}

/// Passive, listen-only keyboard tap. Needs Input Monitoring.
final class KeyboardMonitor {
    private var tap: CFMachPort?
    private var onKey: (ObservedKey) -> Void = { _ in }

    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt and adds the app to the Input Monitoring list.
    static func requestPermission() { CGRequestListenEventAccess() }

    var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// Returns false when the tap can't be created, which means permission is missing.
    func start(onKey: @escaping (ObservedKey) -> Void) -> Bool {
        guard tap == nil else { return true }
        self.onKey = onKey
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(info!).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            guard let nsEvent = NSEvent(cgEvent: event) else { return }
            let flags = event.flags
            onKey(ObservedKey(
                keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                time: nsEvent.timestamp,
                text: nsEvent.characters ?? "",
                commandOrControl: flags.contains(.maskCommand) || flags.contains(.maskControl),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                sourceStateID: event.getIntegerValueField(.eventSourceStateID),
                sourceProcessID: event.getIntegerValueField(.eventSourceUnixProcessID)
            ))
        default:
            break
        }
    }
}
