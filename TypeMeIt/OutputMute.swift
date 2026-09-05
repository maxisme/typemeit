import CoreAudio
import Foundation

/// Mutes the default output device while recording, through CoreAudio's
/// kAudioDevicePropertyMute, and puts it back afterwards.
@MainActor
enum OutputMute {
    private static var previous: (device: AudioDeviceID, wasMuted: Bool)?

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr ? id : nil
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value != 0 : nil
    }

    private static func setMuted(_ device: AudioDeviceID, _ on: Bool) {
        var address = muteAddress
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return }
        var value: UInt32 = on ? 1 : 0
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        if status != noErr { Log.audio.error("Could not set mute: \(status)") }
    }

    static func mute() {
        guard previous == nil, let device = defaultOutputDevice(), let was = isMuted(device) else { return }
        previous = (device, was)
        if !was { setMuted(device, true) }
    }

    /// Returns true when the device was muted by `mute()` and has just been
    /// unmuted.
    @discardableResult
    static func restore() -> Bool {
        guard let p = previous else { return false }
        previous = nil
        if !p.wasMuted { setMuted(p.device, false) }
        return !p.wasMuted
    }
}
