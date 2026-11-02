import CoreAudio
import Foundation
import Observation

/// The default microphone's mute, which the call's mute button turns on. It mutes the call in
/// whatever app has it, though that app's own button doesn't show it.
@Observable
final class CallMicrophone {
    private(set) var isMuted = false
    /// The microphone has a mute: the Mac's own does, an iPhone's used as one doesn't.
    private(set) var canMute = false

    @ObservationIgnored private var device = AudioObjectID(kAudioObjectUnknown)

    private static let system = AudioObjectID(kAudioObjectSystemObject)
    /// The microphone DyNotch muted, by UID, so it's turned back on when the call ends, or at
    /// the next launch if DyNotch quits before then.
    private static let mutedKey = "callMutedMicrophone"
    private static var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )

    @ObservationIgnored private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.deviceChanged() }
    }
    @ObservationIgnored private lazy var muteListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.readMute() }
    }

    func start() {
        AudioObjectAddPropertyListenerBlock(Self.system, &Self.defaultInputAddress, .main, deviceListener)
        deviceChanged()
    }

    func setMuted(_ muted: Bool) {
        guard canMute, write(muted, to: device) else { return }
        if muted {
            UserDefaults.standard.set(AudioDevices.uid(of: device), forKey: Self.mutedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.mutedKey)
        }
        readMute()
    }

    /// Turns back on the microphone DyNotch muted, if it's still muted: a call ended, or one
    /// muted before a quit is over.
    func releaseMute() {
        guard let uid = UserDefaults.standard.string(forKey: Self.mutedKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.mutedKey)
        if let muted = AudioDevices.device(uid: uid) { write(false, to: muted) }
        readMute()
    }

    /// A new microphone in the middle of a muted call (AirPods coming in) is muted too, so
    /// nobody hears through it what the old one kept quiet.
    private func deviceChanged() {
        if device != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(device, &Self.muteAddress, .main, muteListener)
        }
        let old = device
        device = CoreAudioProperty.value(kAudioHardwarePropertyDefaultInputDevice, of: Self.system, default: AudioObjectID(kAudioObjectUnknown)) ?? AudioObjectID(kAudioObjectUnknown)
        canMute = device != kAudioObjectUnknown && Self.isSettable(device)
        if device != kAudioObjectUnknown {
            AudioObjectAddPropertyListenerBlock(device, &Self.muteAddress, .main, muteListener)
        }
        if old != kAudioObjectUnknown, old != device, UserDefaults.standard.string(forKey: Self.mutedKey) != nil {
            write(false, to: old)
            UserDefaults.standard.removeObject(forKey: Self.mutedKey)
            setMuted(true)
        }
        readMute()
    }

    private func readMute() {
        isMuted = canMute && CoreAudioProperty.value(kAudioDevicePropertyMute, of: device, scope: kAudioObjectPropertyScopeInput, default: UInt32(0)) == 1
    }

    @discardableResult
    private func write(_ muted: Bool, to device: AudioObjectID) -> Bool {
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &Self.muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private static func isSettable(_ device: AudioObjectID) -> Bool {
        guard AudioObjectHasProperty(device, &muteAddress) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &muteAddress, &settable) == noErr && settable.boolValue
    }
}

/// A device sound can play through.
struct AudioOutput: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let symbol: String
    /// The Mac's own speakers, as the iPhone's speakerphone.
    let isSpeaker: Bool
}

/// The Mac's sound outputs, for the call's speaker button: which is in use, and switching to
/// another, as the Sound menu in Control Center does.
@Observable
final class AudioOutputs {
    private(set) var all: [AudioOutput] = []
    private(set) var current: AudioOutput?

    @ObservationIgnored private var listenedDevice = AudioObjectID(kAudioObjectUnknown)

    private static let system = AudioObjectID(kAudioObjectSystemObject)
    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    /// Headphones plugged into the Mac's jack, which turn its speakers into them.
    private static var dataSourceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDataSource,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    @ObservationIgnored private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        MainActor.assumeIsolated { self?.refresh() }
    }

    func start() {
        AudioObjectAddPropertyListenerBlock(Self.system, &Self.devicesAddress, .main, listener)
        AudioObjectAddPropertyListenerBlock(Self.system, &Self.defaultOutputAddress, .main, listener)
        refresh()
    }

    func select(_ output: AudioOutput) {
        var id = output.id
        AudioObjectSetPropertyData(Self.system, &Self.defaultOutputAddress, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &id)
    }

    private func refresh() {
        let selected = CoreAudioProperty.value(kAudioHardwarePropertyDefaultOutputDevice, of: Self.system, default: AudioObjectID(kAudioObjectUnknown))
        all = AudioDevices.all().compactMap(Self.output)
        current = all.first { $0.id == selected }
        if listenedDevice != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(listenedDevice, &Self.dataSourceAddress, .main, listener)
            listenedDevice = AudioObjectID(kAudioObjectUnknown)
        }
        if let id = current?.id, AudioObjectHasProperty(id, &Self.dataSourceAddress) {
            AudioObjectAddPropertyListenerBlock(id, &Self.dataSourceAddress, .main, listener)
            listenedDevice = id
        }
    }

    private static func output(_ device: AudioObjectID) -> AudioOutput? {
        let output = kAudioObjectPropertyScopeOutput
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: output, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &size) == noErr, size > 0,
              CoreAudioProperty.value(kAudioDevicePropertyIsHidden, of: device, default: UInt32(0)) != 1,
              let name = AudioDevices.string(kAudioObjectPropertyName, of: device)
        else { return nil }
        let transport = CoreAudioProperty.value(kAudioDevicePropertyTransportType, of: device, default: UInt32(0)) ?? 0
        let headphones = CoreAudioProperty.value(kAudioDevicePropertyDataSource, of: device, scope: output, default: UInt32(0)) == 0x6864_706E // 'hdpn'
        let isSpeaker = transport == kAudioDeviceTransportTypeBuiltIn && !headphones
        return AudioOutput(id: device, name: name, symbol: symbol(name: name, transport: transport, headphones: headphones), isSpeaker: isSpeaker)
    }

    private static func symbol(name: String, transport: UInt32, headphones: Bool) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return headphones ? "headphones" : "speaker.wave.2.fill"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if name.localizedCaseInsensitiveContains("AirPods Max") { return "airpods.max" }
            if name.localizedCaseInsensitiveContains("AirPods Pro") { return "airpods.pro" }
            if name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
            if name.localizedCaseInsensitiveContains("Beats") { return "beats.headphones" }
            return "headphones"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "tv"
        default:
            return "hifispeaker.fill"
        }
    }
}

/// Finding Core Audio devices and reading what they're called.
enum AudioDevices {
    static func all() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    static func uid(of device: AudioObjectID) -> String? {
        string(kAudioDevicePropertyDeviceUID, of: device)
    }

    static func device(uid: String) -> AudioObjectID? {
        all().first { self.uid(of: $0) == uid }
    }

    static func string(_ selector: AudioObjectPropertySelector, of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
