import Accelerate
import CoreAudio
import Foundation
import OSLog
import Synchronization

/// Drives the bars beside the notch from what is actually playing, like the waveform in the
/// iPhone's Dynamic Island. Listens to system audio (System Audio Recording) only while music
/// plays and bars are on screen, since macOS shows its purple recording dot all that time;
/// otherwise the bars fall back to a stand-in rhythm.
final class AudioLevelMeter {
    /// How long the tap keeps running after it's no longer needed, so the bars swapping views
    /// (compact player, skip peek) or a moment with the notch open don't restart it.
    private static let stopDelay: Duration = .seconds(1.5)

    private let tap = SystemAudioTap()
    private var isWanted = false
    private var visibleBars = 0
    private var isRunning = false
    private var isAskingPermission = false
    private var observesOutputDevice = false
    private var stopTask: Task<Void, Never>?

    /// Whether music is playing and the user wants the bars to follow it.
    func update(active: Bool) {
        isWanted = active
        refresh()
    }

    func barsAppeared() {
        visibleBars += 1
        refresh()
    }

    func barsDisappeared() {
        visibleBars = max(visibleBars - 1, 0)
        refresh()
    }

    /// Bar heights from 0 (a dot) to 1 for what can be heard right now, or `nil` while system
    /// audio isn't coming through (not allowed, turned off, nothing heard yet, or the tap stalled).
    func currentLevels() -> [Float]? {
        guard isRunning, tap.store.hasHeardAudio else { return nil }
        return tap.store.levels(at: HostTime.now)
    }

    private func refresh() {
        guard isWanted, visibleBars > 0 else { return scheduleStop() }
        stopTask?.cancel()
        stopTask = nil
        guard !isRunning else { return }
        switch SystemAudioPermission.state {
        case .granted:
            start()
        case .denied:
            break
        case .notDetermined:
            // Ask up front instead of letting the first tap ask, so the answer is known.
            guard !isAskingPermission else { return }
            isAskingPermission = true
            Task {
                _ = await SystemAudioPermission.request()
                isAskingPermission = false
                // Without the TCC SPI the state stays unknown; starting the tap then asks by itself.
                if isWanted, visibleBars > 0, !isRunning, SystemAudioPermission.state != .denied { start() }
            }
        }
    }

    private func start() {
        isRunning = true
        tap.start()
        observeOutputDevice()
    }

    private func scheduleStop() {
        guard isRunning, stopTask == nil else { return }
        stopTask = Task {
            try? await Task.sleep(for: Self.stopDelay)
            guard !Task.isCancelled else { return }
            stopTask = nil
            isRunning = false
            tap.stop()
        }
    }

    /// AirPods connecting and the like: tap again so the delay matches the new device.
    private func observeOutputDevice() {
        guard !observesOutputDevice else { return }
        observesOutputDevice = true
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            guard let self, self.isRunning else { return }
            self.tap.start()
        }
    }
}

// MARK: - Permission

/// System Audio Recording (TCC `kTCCServiceAudioCapture`). There is no public API to check or
/// ask for it (starting a tap asks by itself), so this goes through the private TCC SPI and
/// reports `.notDetermined` if that is missing.
enum SystemAudioPermission {
    private typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFunction = @convention(c) (
        CFString, CFDictionary?, @escaping @Sendable @convention(block) (Bool) -> Void
    ) -> Void

    private static let service = "kTCCServiceAudioCapture" as CFString
    private static let handle = PrivateFrameworks.load("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC")

    static var state: PermissionState {
        guard let symbol = dlsym(handle, "TCCAccessPreflight") else { return .notDetermined }
        switch unsafeBitCast(symbol, to: PreflightFunction.self)(service, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .notDetermined
        }
    }

    /// Shows the system prompt if the user hasn't answered it yet. `false` if denied or the SPI is missing.
    static func request() async -> Bool {
        guard let symbol = dlsym(handle, "TCCAccessRequest") else { return false }
        let request = unsafeBitCast(symbol, to: RequestFunction.self)
        return await withCheckedContinuation { continuation in
            request(service, nil) { granted in continuation.resume(returning: granted) }
        }
    }
}

// MARK: - Tap

/// Hears everything the Mac plays through a private Core Audio process tap, and folds it into
/// bar levels as it arrives. Nothing is recorded: each buffer is analysed and dropped.
nonisolated final class SystemAudioTap: @unchecked Sendable {
    let store = LevelStore()

    private static let logger = Logger(subsystem: "app.dynotch", category: "AudioLevels")
    private static let unknown = AudioObjectID(kAudioObjectUnknown)

    private let controlQueue = DispatchQueue(label: "app.dynotch.audio-tap")
    private let ioQueue = DispatchQueue(label: "app.dynotch.audio-tap.io", qos: .userInteractive)

    // Only touched on `controlQueue`.
    private var tapID = unknown
    private var aggregateID = unknown
    private var procID: AudioDeviceIOProcID?

    /// Starts listening, or starts over if it already is.
    func start() {
        controlQueue.async { [self] in
            tearDown()
            do {
                try setUp()
            } catch {
                Self.logger.error("System audio tap failed: \(String(describing: error), privacy: .public)")
                tearDown()
            }
        }
    }

    func stop() {
        controlQueue.async { [self] in tearDown() }
    }

    private func setUp() throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "DyNotch Audio Bars"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID), "create the tap")

        guard let format = CoreAudioProperty.value(kAudioTapPropertyFormat, of: tapID, default: AudioStreamBasicDescription()),
              format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              format.mSampleRate > 0
        else { throw TapError(step: "read a float format from the tap", status: OSStatus(kAudioHardwareUnsupportedOperationError)) }

        // Just the tap, like Apple's sample: it clocks the device itself, whichever output is in use.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "DyNotch Audio Bars",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "create the aggregate device")

        let analyzer = SpectrumAnalyzer(sampleRate: format.mSampleRate)
        let store = store
        store.restart(latency: CoreAudioProperty.outputLatency())
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) { _, input, inputTime, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let buffer = buffers.first, let data = buffer.mData else { return }
            let samples = UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: Float.self),
                count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            )
            let time = inputTime.pointee.mFlags.contains(.hostTimeValid)
                ? HostTime.seconds(inputTime.pointee.mHostTime)
                : HostTime.now
            if analyzer.process(samples, channels: Int(buffer.mNumberChannels), at: time) {
                store.record(analyzer.levels, at: time, heardAudio: analyzer.hasHeardAudio)
            }
        }, "create the IO proc")
        // The first start asks for System Audio Recording if nobody has yet.
        try check(AudioDeviceStart(aggregateID, procID), "start the device")
    }

    private func tearDown() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != Self.unknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = Self.unknown
        }
        if tapID != Self.unknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = Self.unknown
        }
    }

    private func check(_ status: OSStatus, _ step: String) throws {
        guard status == noErr else { throw TapError(step: step, status: status) }
    }

    private struct TapError: Error, CustomStringConvertible {
        let step: String
        let status: OSStatus
        var description: String { "couldn't \(step) (OSStatus \(status))" }
    }
}

/// Bar levels handed from the audio queue to the UI, kept for a moment so they can be shown
/// when the sound they belong to actually comes out of the speakers.
nonisolated final class LevelStore: Sendable {
    private struct State {
        var history = LevelHistory()
        var latency: TimeInterval = 0
        var restartedAt: TimeInterval = 0
        var hasHeardAudio = false
    }

    /// Levels older than this mean the tap has stalled.
    private static let staleAfter: TimeInterval = 0.25
    /// How long after (re)starting the bars wait at dots for the first sound.
    private static let warmUp: TimeInterval = 1

    private let state = Mutex(State())

    /// Whether anything but silence has come through since launch. A tap without permission
    /// hears only silence (no error), so until then the bars keep their stand-in rhythm.
    var hasHeardAudio: Bool { state.withLock { $0.hasHeardAudio } }

    func restart(latency: TimeInterval) {
        state.withLock {
            $0.history = LevelHistory()
            $0.latency = latency
            $0.restartedAt = HostTime.now
        }
    }

    func record(_ levels: [Float], at time: TimeInterval, heardAudio: Bool) {
        state.withLock {
            $0.history.append(levels, at: time)
            if heardAudio { $0.hasHeardAudio = true }
        }
    }

    /// The levels of the sound being heard at host time `time`: dots while the tap warms up,
    /// `nil` if it has stalled.
    func levels(at time: TimeInterval) -> [Float]? {
        state.withLock { state in
            let heard = time - state.latency
            if let frame = state.history.frame(at: heard), heard - frame.time < Self.staleAfter {
                return frame.levels
            }
            return time - state.restartedAt < Self.warmUp ? Array(repeating: 0, count: SpectrumAnalyzer.bandCount) : nil
        }
    }
}

/// The last second or so of levels (more than the longest output latency, even with small IO buffers).
nonisolated struct LevelHistory {
    static let capacity = 512

    private var times = [TimeInterval](repeating: -.infinity, count: capacity)
    private var frames = [[Float]](repeating: [], count: capacity)
    private var next = 0

    mutating func append(_ levels: [Float], at time: TimeInterval) {
        times[next] = time
        frames[next] = levels
        next = (next + 1) % Self.capacity
    }

    /// The newest levels recorded at or before `time`.
    func frame(at time: TimeInterval) -> (time: TimeInterval, levels: [Float])? {
        for offset in 1...Self.capacity {
            let index = (next - offset + Self.capacity) % Self.capacity
            if times[index] <= time { return frames[index].isEmpty ? nil : (times[index], frames[index]) }
        }
        return nil
    }
}

// MARK: - Analysis

/// Turns audio into bar heights: a short FFT folded into a few log-spaced bands, each held
/// against its own recent average so the treble moves as much as the bass, then eased with a
/// quick rise and a slower fall.
nonisolated final class SpectrumAnalyzer {
    static let size = 1024
    /// Bands from low to high as they appear left to right: the bass in the middle, so the
    /// waveform swells in the centre on the beat and flickers at the edges with the treble.
    static let barOrder = [4, 2, 0, 1, 3, 5]
    static var bandCount: Int { barOrder.count }

    private static let lowestFrequency = 50.0
    private static let highestFrequency = 12_000.0
    /// Bands quieter than this (dBFS) are silent.
    private static let silence: Float = -70
    /// dB between a dot and a full bar.
    private static let range: Float = 20
    /// dB a band can rise above its average before its bar is full.
    private static let headroom: Float = 6
    /// A band this far (dB) below the loudest one isn't lifted any further, so a bass-heavy
    /// track doesn't blow up the hiss above it.
    private static let spread: Float = 18
    /// Higher curves leave more room between an average moment and a peak.
    private static let curve: Float = 1.6
    private static let averaging: TimeInterval = 1.5
    private static let attack: TimeInterval = 0.05
    private static let release: TimeInterval = 0.18

    /// Bar heights from 0 (a dot) to 1, in bar order.
    private(set) var levels = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    /// Whether anything but silence has come through.
    private(set) var hasHeardAudio = false

    private let bands: [Range<Int>]
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: UnsafeMutablePointer<Float>
    private let ring: UnsafeMutablePointer<Float>
    private let frame: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imag: UnsafeMutablePointer<Float>
    private let power: UnsafeMutablePointer<Float>
    private var writeIndex = 0
    private var filled = 0
    private var averages = [Float?](repeating: nil, count: SpectrumAnalyzer.bandCount)
    private var smoothed = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
    private var lastTime: TimeInterval?

    init(sampleRate: Double) {
        let size = Self.size
        bands = Self.bandRanges(sampleRate: sampleRate)
        log2n = vDSP_Length(log2(Double(size)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = .allocate(capacity: size)
        ring = .allocate(capacity: size)
        frame = .allocate(capacity: size)
        real = .allocate(capacity: size / 2)
        imag = .allocate(capacity: size / 2)
        power = .allocate(capacity: size / 2)
        ring.initialize(repeating: 0, count: size)
        for index in 0..<size {
            window[index] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(index) / Double(size)))
        }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        [window, ring, frame, real, imag, power].forEach { $0.deallocate() }
    }

    /// FFT bins for each band, low to high.
    static func bandRanges(sampleRate: Double) -> [Range<Int>] {
        let binWidth = sampleRate / Double(size)
        let top = size / 2
        let ratio = pow(highestFrequency / lowestFrequency, 1 / Double(bandCount))
        var lower = min(max(Int((lowestFrequency / binWidth).rounded()), 1), top - bandCount)
        return (1...bandCount).map { index in
            let edge = Int((lowestFrequency * pow(ratio, Double(index)) / binWidth).rounded())
            let upper = min(max(edge, lower + 1), top)
            defer { lower = upper }
            return lower..<upper
        }
    }

    /// Feeds interleaved samples captured at host time `time`. Returns whether `levels` changed.
    func process(_ samples: UnsafeBufferPointer<Float>, channels: Int, at time: TimeInterval) -> Bool {
        let channels = max(channels, 1)
        let count = samples.count / channels
        guard count > 0 else { return false }
        for index in 0..<count {
            var sum: Float = 0
            for channel in 0..<channels { sum += samples[index * channels + channel] }
            ring[writeIndex] = sum / Float(channels)
            writeIndex = (writeIndex + 1) % Self.size
        }
        filled = min(filled + count, Self.size)
        guard filled == Self.size else { return false }
        let elapsed = lastTime.map { min(max(time - $0, 0.001), 0.1) } ?? 0.01
        lastTime = time

        let decibels = spectrum()
        if decibels.contains(where: { $0 > Self.silence }) { hasHeardAudio = true }

        // Each band's average follows its level over the last second or so, ignoring silence.
        let follow = Float(1 - exp(-elapsed / Self.averaging))
        for band in bands.indices where decibels[band] > Self.silence {
            averages[band] = averages[band].map { $0 + (decibels[band] - $0) * follow } ?? decibels[band]
        }
        let loudest = averages.compactMap { $0 }.max() ?? Self.silence
        for band in bands.indices {
            var target: Float = 0
            if decibels[band] > Self.silence, let average = averages[band] {
                let full = max(average, loudest - Self.spread) + Self.headroom
                target = pow(min(max((decibels[band] - full + Self.range) / Self.range, 0), 1), Self.curve)
            }
            let easing = target > smoothed[band] ? Self.attack : Self.release
            smoothed[band] += (target - smoothed[band]) * Float(1 - exp(-elapsed / easing))
        }
        for (bar, band) in Self.barOrder.enumerated() { levels[bar] = smoothed[band] }
        return true
    }

    /// Each band's power in dBFS over the last `size` samples.
    private func spectrum() -> [Float] {
        let size = Self.size
        let half = size / 2
        // Oldest sample first, windowed.
        let tail = size - writeIndex
        frame.update(from: ring + writeIndex, count: tail)
        (frame + tail).update(from: ring, count: writeIndex)
        vDSP_vmul(frame, 1, window, 1, frame, 1, vDSP_Length(size))

        var split = DSPSplitComplex(realp: real, imagp: imag)
        frame.withMemoryRebound(to: DSPComplex.self, capacity: half) { vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half)) }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
        vDSP_zvmags(&split, 1, power, 1, vDSP_Length(half))

        // A full-scale sine in the Hann window comes out of zrip at (size / 2)²: scale that to 0 dB.
        let scale = 4 / Float(size * size)
        return bands.map { band in
            var sum: Float = 0
            vDSP_sve(power + band.lowerBound, 1, &sum, vDSP_Length(band.count))
            return 10 * log10(max(sum * scale, 1e-12))
        }
    }
}

// MARK: - Core Audio helpers

nonisolated enum HostTime {
    static var now: TimeInterval { seconds(AudioGetCurrentHostTime()) }

    static func seconds(_ hostTime: UInt64) -> TimeInterval {
        TimeInterval(AudioConvertHostTimeToNanos(hostTime)) / 1_000_000_000
    }
}

nonisolated enum CoreAudioProperty {
    /// Reads a fixed-size (plain C) property.
    static func value<T: BitwiseCopyable>(
        _ selector: AudioObjectPropertySelector,
        of object: AudioObjectID,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        default value: T
    ) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var value = value
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) }
        return status == noErr ? value : nil
    }

    /// How long sound takes from the system mix to the default output (much longer for
    /// Bluetooth headphones), so the bars can wait for the sound they show.
    static func outputLatency() -> TimeInterval {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let device = value(kAudioHardwarePropertyDefaultOutputDevice, of: system, default: AudioObjectID(0)),
              device != 0,
              let rate = value(kAudioDevicePropertyNominalSampleRate, of: device, default: Float64(0)),
              rate > 0
        else { return 0 }
        let output = kAudioObjectPropertyScopeOutput
        var frames = (value(kAudioDevicePropertyLatency, of: device, scope: output, default: UInt32(0)) ?? 0)
            + (value(kAudioDevicePropertySafetyOffset, of: device, scope: output, default: UInt32(0)) ?? 0)
            + (value(kAudioDevicePropertyBufferFrameSize, of: device, default: UInt32(0)) ?? 0)
        if let stream = value(kAudioDevicePropertyStreams, of: device, scope: output, default: AudioStreamID(0)), stream != 0 {
            frames += value(kAudioStreamPropertyLatency, of: stream, default: UInt32(0)) ?? 0
        }
        return min(Double(frames) / rate, 0.5)
    }
}
