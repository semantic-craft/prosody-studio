#if os(macOS)
import AVFoundation
import CoreAudio
import OSLog
import ResponsayCore

/// Applies the user's 首选麦克风 to an `AVAudioEngine` before it starts. The stored
/// `micDeviceID` is an `AVCaptureDevice.uniqueID`, which equals the CoreAudio device
/// UID — so we map UID → `AudioDeviceID` and set it on the input node's audio unit.
/// No-op when unset (system default). macOS only (CoreAudio HAL device enumeration);
/// iOS uses the system default input and never calls this.
public enum AudioInputDeviceSelector {
    private static let log = Logger(subsystem: AppBrand.loggerSubsystem, category: "audio-input")

    /// The stored preferred input UID ("" = system default). Shared key with Settings.
    static var preferredUID: String {
        UserDefaults.standard.string(forKey: "micDeviceID") ?? ""
    }

    /// Route `engine`'s input to the preferred device. Call before `installTap`/`start`.
    public static func apply(to engine: AVAudioEngine) {
        let uid = preferredUID
        guard !uid.isEmpty else { return }                 // system default → leave engine alone
        guard let deviceID = deviceID(forUID: uid) else {
            log.warning("Preferred mic UID not found among inputs; using system default")
            return
        }
        guard let unit = engine.inputNode.audioUnit else {
            log.error("Input node has no audio unit; cannot set device")
            return
        }
        var device = deviceID
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr {
            log.error("AudioUnitSetProperty(CurrentDevice) failed: \(status, privacy: .public)")
        }
    }

    // MARK: - CoreAudio lookup

    /// The `AudioDeviceID` whose UID matches `uid` and that has at least one input channel.
    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return nil }
        return devices.first { hasInput($0) && deviceUID($0) == uid }
    }

    private static func deviceUID(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        return status == noErr ? (uid as String?) : nil
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }
}
#endif
