import AudioToolbox
import CoreAudio
import Foundation

/// Volume and mute of the default output device through CoreAudio.
final class VolumeController {
    /// Called when the device, its volume or mute state change (from anywhere).
    var onChange: (() -> Void)?

    private(set) var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var listenedDevice = AudioObjectID(kAudioObjectUnknown)

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.defaultDeviceChanged() }
    }
    private lazy var valueListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.onChange?() }
    }

    func start() {
        AudioObjectAddPropertyListenerBlock(Self.systemObject, &Self.defaultOutputAddress, .main, deviceListener)
        defaultDeviceChanged()
    }

    private func defaultDeviceChanged() {
        if listenedDevice != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(listenedDevice, &Self.volumeAddress, .main, valueListener)
            AudioObjectRemovePropertyListenerBlock(listenedDevice, &Self.muteAddress, .main, valueListener)
        }
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(Self.systemObject, &Self.defaultOutputAddress, 0, nil, &size, &id)
        deviceID = id
        listenedDevice = id
        if id != kAudioObjectUnknown {
            AudioObjectAddPropertyListenerBlock(id, &Self.volumeAddress, .main, valueListener)
            AudioObjectAddPropertyListenerBlock(id, &Self.muteAddress, .main, valueListener)
        }
        onChange?()
    }

    /// Whether the current device supports software volume (HDMI often doesn't).
    var canSetVolume: Bool {
        guard deviceID != kAudioObjectUnknown, AudioObjectHasProperty(deviceID, &Self.volumeAddress) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(deviceID, &Self.volumeAddress, &settable) == noErr && settable.boolValue
    }

    var volume: Float {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &Self.volumeAddress, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    func setVolume(_ newValue: Float) {
        var value = Float32(min(max(newValue, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(deviceID, &Self.volumeAddress, 0, nil, size, &value)
    }

    var isMuted: Bool {
        guard AudioObjectHasProperty(deviceID, &Self.muteAddress) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &Self.muteAddress, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    func setMuted(_ muted: Bool) {
        guard AudioObjectHasProperty(deviceID, &Self.muteAddress) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(deviceID, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}
