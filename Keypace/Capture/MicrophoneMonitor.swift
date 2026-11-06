import CoreAudio
import Foundation

/// Which processes are recording from an input device, from Core Audio's process objects.
/// Reads no audio and needs no permission.
///
/// Core Audio doesn't notify when a process starts or stops recording, but it does when an input
/// device starts or stops running. So the monitor listens to input devices and, only while one is
/// running, checks every quarter second which processes are recording.
final class MicrophoneMonitor {
    struct Change: Equatable {
        var processID: Int32
        var isRecording: Bool
    }

    static let checkInterval = 0.25

    private var onChange: (Change) -> Void = { _ in }
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var deviceListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var recording: Set<Int32> = []
    private var timer: Timer?

    var isRunning: Bool { deviceListListener != nil }

    func start(onChange: @escaping (Change) -> Void) {
        guard deviceListListener == nil else { return }
        self.onChange = onChange
        var address = Self.address(kAudioHardwarePropertyDevices)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshDevices() }
        }
        guard AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr else { return }
        deviceListListener = listener
        refreshDevices()
    }

    /// Stops watching. Processes still recording are reported as stopped.
    func stop() {
        guard let deviceListListener else { return }
        var address = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListListener)
        self.deviceListListener = nil
        for device in Array(deviceListeners.keys) { unwatch(device) }
        timer?.invalidate()
        timer = nil
        for processID in recording { onChange(Change(processID: processID, isRecording: false)) }
        recording = []
    }

    /// Watches every device with input, as devices come and go.
    private func refreshDevices() {
        let inputs = Set(Self.devices().filter(Self.hasInput))
        for device in inputs where deviceListeners[device] == nil {
            var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.update() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, .main, listener) == noErr {
                deviceListeners[device] = listener
            }
        }
        for device in deviceListeners.keys where !inputs.contains(device) { unwatch(device) }
        update()
    }

    private func unwatch(_ device: AudioObjectID) {
        guard let listener = deviceListeners.removeValue(forKey: device) else { return }
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
    }

    /// Checks now, and keeps checking while any input device runs.
    private func update() {
        let running = deviceListeners.keys.contains { (Self.value($0, kAudioDevicePropertyDeviceIsRunningSomewhere) as UInt32?) ?? 0 != 0 }
        check()
        if running, timer == nil {
            timer = .scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
        } else if !running {
            timer?.invalidate()
            timer = nil
        }
    }

    private func check() {
        let ownID = getpid()
        let now = Set(Self.processObjects().compactMap { object -> Int32? in
            guard (Self.value(object, kAudioProcessPropertyIsRunningInput) as UInt32?) ?? 0 != 0,
                  let processID: Int32 = Self.value(object, kAudioProcessPropertyPID), processID != ownID else { return nil }
            return processID
        })
        for processID in now.subtracting(recording) { onChange(Change(processID: processID, isRecording: true)) }
        for processID in recording.subtracting(now) { onChange(Change(processID: processID, isRecording: false)) }
        recording = now
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func devices() -> [AudioObjectID] {
        objects(kAudioHardwarePropertyDevices)
    }

    private static func processObjects() -> [AudioObjectID] {
        objects(kAudioHardwarePropertyProcessObjectList)
    }

    private static func objects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func hasInput(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func value<T: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        var value = T.zero
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
}
