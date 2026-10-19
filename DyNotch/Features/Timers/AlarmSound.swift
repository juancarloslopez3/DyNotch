import AppKit

/// A ringtone a finished timer can ring with: the iPhone's own, which macOS keeps for the
/// calls it rings for. Named by its file, e.g. "Radar" or "Radial-EncoreInfinitum".
nonisolated struct AlarmTone: Identifiable, Hashable, Sendable {
    let id: String

    /// The iPhone's timer sound.
    static let standard = AlarmTone(id: "Radar")

    private static let directory = URL(filePath: "/System/Library/PrivateFrameworks/ToneLibrary.framework/Resources/Ringtones")

    /// What the iPhone calls it: the newer tones' files end in "-EncoreInfinitum".
    var name: String { id.replacing("-EncoreInfinitum", with: "") }

    var url: URL { Self.directory.appending(path: id + ".m4r") }

    /// Every tone on this Mac, by name. Where a newer tone has an older one's name
    /// ("Reflection"), the newer one stays, as on the iPhone.
    static let all: [AlarmTone] = {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let ids = files.filter { $0.pathExtension == "m4r" }.map { $0.deletingPathExtension().lastPathComponent }
        let tones = ids.filter { $0.hasSuffix("-EncoreInfinitum") || !ids.contains($0 + "-EncoreInfinitum") }
            .map(AlarmTone.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return tones.isEmpty ? [standard] : tones
    }()
}

/// Plays a tone over and over while a timer's alarm rings, or once to try it in Settings.
final class AlarmPlayer {
    private var sound: NSSound?

    func play(_ tone: AlarmTone, repeating: Bool) {
        stop()
        // A copy of the named sound, so looping it doesn't loop every other "Glass".
        let sound = NSSound(contentsOf: tone.url, byReference: true) ?? NSSound(named: "Glass")?.copy() as? NSSound
        sound?.loops = repeating
        sound?.play()
        self.sound = sound
    }

    func stop() {
        sound?.stop()
        sound = nil
    }
}
