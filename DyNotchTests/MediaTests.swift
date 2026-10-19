import Foundation
import Testing

@testable import DyNotch

struct NowPlayingTests {
    @Test func mergesDiffsIntoFullPayload() {
        var state = NowPlayingStreamState()
        let loadedFull = state.apply(line: #"{"type":"data","diff":false,"payload":{"title":"Song","artist":"Band","playing":true,"durationMicros":200000000,"elapsedTimeMicros":10000000,"timestampEpochMicros":1000000000000}}"#)
        #expect(loadedFull)
        #expect(state.info?.title == "Song")
        #expect(state.info?.duration == 200)

        let appliedDiff = state.apply(line: #"{"type":"data","diff":true,"payload":{"playing":false,"artist":null}}"#)
        #expect(appliedDiff)
        #expect(state.info?.isPlaying == false)
        #expect(state.info?.artist == "")
        #expect(state.info?.title == "Song")
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        var state = NowPlayingStreamState()
        let appliedEmpty = state.apply(line: #"{"type":"data","diff":false,"payload":{}}"#)
        #expect(appliedEmpty)
        #expect(state.info == nil)
        let rejected = state.apply(line: "not json")
        #expect(!rejected)
    }

    @Test func privateBrowsingPlaysWithoutTitle() throws {
        // Recorded from a Safari private window; the bare app-and-state payload comes first.
        var state = NowPlayingStreamState()
        _ = state.apply(line: #"{"type":"data","diff":false,"payload":{"playing":true,"processIdentifier":2715,"parentApplicationBundleIdentifier":"com.apple.Safari","bundleIdentifier":"com.apple.WebKit.GPU"}}"#)
        #expect(state.info == nil)
        _ = state.apply(line: #"{"type":"data","diff":false,"payload":{"playbackRate":1,"timestampEpochMicros":1792342959330484,"album":"","elapsedTimeMicros":0,"playing":true,"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","processIdentifier":2715,"title":"","uniqueIdentifier":141657,"artist":"","contentItemIdentifier":"141657","durationMicros":13318101000}}"#)
        let info = try #require(state.info)
        #expect(info.title.isEmpty)
        #expect(info.isPlaying)
        #expect(info.bundleIdentifier == "com.apple.Safari")
    }

    @Test func browsersReportTheirParentApp() throws {
        let info = try #require(NowPlayingInfo(payload: [
            "title": "Video", "bundleIdentifier": "com.apple.WebKit.GPU", "parentApplicationBundleIdentifier": "com.apple.Safari",
        ], artworkData: nil))
        #expect(info.bundleIdentifier == "com.apple.Safari")
    }

    @Test func positionAdvancesOnlyWhilePlaying() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var info = try #require(NowPlayingInfo(payload: [
            "title": "Song", "playing": true, "durationMicros": 60_000_000, "elapsedTimeMicros": 10_000_000,
            "timestampEpochMicros": 1_000_000_000, "playbackRate": 1,
        ], artworkData: nil))
        #expect(info.position(at: start.addingTimeInterval(5)) == 15)
        #expect(info.position(at: start.addingTimeInterval(500)) == 60)
        info.isPlaying = false
        #expect(info.position(at: start.addingTimeInterval(5)) == 10)
    }

    @Test func resumingRunsOnFromThePausedPosition() throws {
        var state = NowPlayingStreamState()
        let paused = Date(timeIntervalSince1970: 1000)
        _ = state.apply(line: #"{"type":"data","diff":false,"payload":{"title":"Song","playing":false,"durationMicros":200000000,"elapsedTimeMicros":10000000,"timestampEpochMicros":1000000000}}"#, at: paused)
        // Resumed five minutes later without a fresh timestamp.
        let resumed = paused.addingTimeInterval(300)
        _ = state.apply(line: #"{"type":"data","diff":true,"payload":{"playing":true}}"#, at: resumed)
        let info = try #require(state.info)
        #expect(info.position(at: resumed.addingTimeInterval(5)) == 15)
    }

    @Test func pausingHoldsThePositionReached() throws {
        var state = NowPlayingStreamState()
        let started = Date(timeIntervalSince1970: 1000)
        _ = state.apply(line: #"{"type":"data","diff":false,"payload":{"title":"Song","playing":true,"playbackRate":1,"durationMicros":200000000,"elapsedTimeMicros":10000000,"timestampEpochMicros":1000000000}}"#, at: started)
        // Paused a minute in; the new position follows the flag a moment later.
        let paused = started.addingTimeInterval(60)
        _ = state.apply(line: #"{"type":"data","diff":true,"payload":{"playing":false}}"#, at: paused)
        #expect(try #require(state.info).position(at: paused.addingTimeInterval(1)) == 70)
        _ = state.apply(line: #"{"type":"data","diff":true,"payload":{"playbackRate":0,"elapsedTimeMicros":70000000,"timestampEpochMicros":1060000000}}"#, at: paused)
        #expect(try #require(state.info).position(at: paused.addingTimeInterval(1)) == 70)
    }
}

struct TrackChangeTests {
    private let start = Date(timeIntervalSince1970: 1000)

    private func track(
        _ title: String, elapsed: TimeInterval = 0, duration: TimeInterval? = 200, at date: Date
    ) throws -> NowPlayingInfo {
        var payload: [String: Any] = [
            "title": title, "playing": true, "playbackRate": 1,
            "elapsedTimeMicros": elapsed * 1_000_000, "timestampEpochMicros": date.timeIntervalSince1970 * 1_000_000,
        ]
        if let duration { payload["durationMicros"] = duration * 1_000_000 }
        return try #require(NowPlayingInfo(payload: payload, artworkData: nil))
    }

    @Test func songThatPlaysOutContinues() throws {
        var detector = TrackChangeDetector()
        _ = detector.update(try track("A", elapsed: 150, at: start), at: start)
        #expect(detector.update(try track("A", elapsed: 150, at: start), at: start.addingTimeInterval(20)) == nil)
        let next = start.addingTimeInterval(49)
        #expect(detector.update(try track("B", at: next), at: next) == .continued)
    }

    @Test func movingOnMidSongIsASkip() throws {
        var detector = TrackChangeDetector()
        _ = detector.update(try track("A", elapsed: 30, at: start), at: start)
        let next = start.addingTimeInterval(10)
        #expect(detector.update(try track("B", at: next), at: next) == .skipped(forward: true))
    }

    @Test func skipCommandSetsTheDirection() throws {
        var detector = TrackChangeDetector()
        _ = detector.update(try track("A", elapsed: 198, at: start), at: start)
        detector.noteSkip(forward: false, at: start.addingTimeInterval(1))
        let next = start.addingTimeInterval(1.5)
        #expect(detector.update(try track("B", at: next), at: next) == .skipped(forward: false))

        // An old command doesn't claim a later change.
        detector.noteSkip(forward: false, at: next)
        let later = next.addingTimeInterval(199)
        #expect(detector.update(try track("C", at: later), at: later) == .continued)
    }

    @Test func elapsedResetJustBeforeTheSwitchStillContinues() throws {
        var detector = TrackChangeDetector()
        _ = detector.update(try track("A", elapsed: 190, at: start), at: start)
        let reset = start.addingTimeInterval(9)
        _ = detector.update(try track("A", elapsed: 0, at: reset), at: reset)
        let next = reset.addingTimeInterval(0.2)
        #expect(detector.update(try track("B", at: next), at: next) == .continued)
    }

    @Test func briefGapBetweenTracksIsIgnored() throws {
        var detector = TrackChangeDetector()
        _ = detector.update(try track("A", elapsed: 195, at: start), at: start)
        #expect(detector.update(nil, at: start.addingTimeInterval(5)) == nil)
        let next = start.addingTimeInterval(6)
        #expect(detector.update(try track("B", at: next), at: next) == .continued)

        _ = detector.update(nil, at: next.addingTimeInterval(1))
        let much = next.addingTimeInterval(60)
        #expect(detector.update(try track("C", at: much), at: much) == .skipped(forward: true))
    }

    @Test func skipSoonAfterResumingIsASkip() throws {
        var state = NowPlayingStreamState()
        var detector = TrackChangeDetector()
        // Paused 30 s into the song, resumed five minutes later, skipped in the player 10 s after that.
        _ = state.apply(line: #"{"type":"data","diff":false,"payload":{"title":"A","playing":false,"durationMicros":200000000,"elapsedTimeMicros":30000000,"timestampEpochMicros":1000000000}}"#, at: start)
        _ = detector.update(state.info, at: start)
        let resumed = start.addingTimeInterval(300)
        _ = state.apply(line: #"{"type":"data","diff":true,"payload":{"playing":true}}"#, at: resumed)
        #expect(detector.update(state.info, at: resumed) == nil)
        let next = resumed.addingTimeInterval(10)
        _ = state.apply(line: #"{"type":"data","diff":false,"payload":{"title":"B","playing":true,"durationMicros":200000000,"elapsedTimeMicros":0,"timestampEpochMicros":1310000000}}"#, at: next)
        #expect(detector.update(state.info, at: next) == .skipped(forward: true))
    }

    @Test func unknownLengthStaysQuiet() throws {
        var detector = TrackChangeDetector()
        _ = detector.update(try track("Radio A", duration: nil, at: start), at: start)
        let next = start.addingTimeInterval(5)
        #expect(detector.update(try track("Radio B", duration: nil, at: next), at: next) == .continued)
    }
}

struct AudioLevelTests {
    /// Feeds `seconds` of a sine (or silence) in 512-frame buffers, like the tap delivers them,
    /// starting at sample `start`. Returns the sample it ended at.
    @discardableResult
    private func feed(
        _ analyzer: SpectrumAnalyzer, frequency: Double?, seconds: Double, from start: Int = 0, sampleRate: Double = 48_000
    ) -> Int {
        let chunk = 512
        var buffer = [Float](repeating: 0, count: chunk)
        var sample = start
        for _ in 0..<Int(seconds * sampleRate) / chunk {
            for index in 0..<chunk {
                buffer[index] = frequency.map { Float(0.5 * sin(2 * .pi * $0 * Double(sample + index) / sampleRate)) } ?? 0
            }
            sample += chunk
            buffer.withUnsafeBufferPointer {
                _ = analyzer.process($0, channels: 1, at: Double(sample) / sampleRate)
            }
        }
        return sample
    }

    private func bar(ofBand band: Int) -> Int { SpectrumAnalyzer.barOrder.firstIndex(of: band)! }

    @Test func bandsCoverTheSpectrumWithoutGaps() {
        for rate in [44_100.0, 48_000, 96_000] {
            let bands = SpectrumAnalyzer.bandRanges(sampleRate: rate)
            #expect(bands.count == SpectrumAnalyzer.bandCount)
            #expect(bands.allSatisfy { !$0.isEmpty && $0.lowerBound >= 1 && $0.upperBound <= SpectrumAnalyzer.size / 2 })
            #expect(zip(bands, bands.dropFirst()).allSatisfy { $0.upperBound == $1.lowerBound })
        }
    }

    @Test func toneLightsOnlyItsBar() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        // 3 kHz falls in the second-highest band.
        feed(analyzer, frequency: 3_000, seconds: 0.5)
        #expect(analyzer.hasHeardAudio)
        let lit = bar(ofBand: 4)
        #expect(analyzer.levels[lit] > 0.3)
        for (index, level) in analyzer.levels.enumerated() where index != lit {
            #expect(level < 0.05)
        }
    }

    @Test func bassSitsInTheMiddle() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        feed(analyzer, frequency: 80, seconds: 0.5)
        let middle = SpectrumAnalyzer.bandCount / 2 - 1
        #expect(bar(ofBand: 0) == middle)
        #expect(analyzer.levels[middle] > 0.3)
    }

    @Test func silenceIsDotsAndNeverCountsAsHeard() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        feed(analyzer, frequency: nil, seconds: 0.3)
        #expect(!analyzer.hasHeardAudio)
        #expect(analyzer.levels.allSatisfy { $0 == 0 })
    }

    @Test func barsFallBackToDotsWhenTheMusicStops() {
        let analyzer = SpectrumAnalyzer(sampleRate: 48_000)
        let end = feed(analyzer, frequency: 3_000, seconds: 0.5)
        feed(analyzer, frequency: nil, seconds: 1, from: end)
        #expect(analyzer.levels.allSatisfy { $0 < 0.01 })
    }

    @Test func historyShowsWhatIsBeingHeard() {
        var history = LevelHistory()
        #expect(history.frame(at: 10) == nil)
        history.append([0.1], at: 1.0)
        history.append([0.2], at: 1.1)
        history.append([0.3], at: 1.2)
        #expect(history.frame(at: 0.9) == nil)
        #expect(history.frame(at: 1.15)?.levels == [0.2])
        #expect(history.frame(at: 5)?.time == 1.2)
    }
}

struct VideoCoverTests {
    @Test func findsYouTubeVideoIDs() {
        let pages = [
            "https://www.youtube.com/watch?v=x-s9y5FONxY": "x-s9y5FONxY",
            "https://www.youtube.com/watch?v=ss9ieMG8kFU&list=RDss9ieMG8kFU&start_radio=1": "ss9ieMG8kFU",
            "https://m.youtube.com/watch?feature=share&v=x-s9y5FONxY": "x-s9y5FONxY",
            "https://music.youtube.com/watch?v=x-s9y5FONxY&si=abc": "x-s9y5FONxY",
            "https://youtu.be/x-s9y5FONxY?t=42": "x-s9y5FONxY",
            "https://www.youtube.com/shorts/x-s9y5FONxY": "x-s9y5FONxY",
            "https://www.youtube.com/live/x-s9y5FONxY": "x-s9y5FONxY",
            "https://www.youtube-nocookie.com/embed/x-s9y5FONxY": "x-s9y5FONxY",
        ]
        for (page, id) in pages {
            #expect(VideoCover.youTubeID(in: URL(string: page)!) == id, "\(page)")
        }
        for page in ["https://www.youtube.com/", "https://www.youtube.com/@TechSantos", "https://www.youtube.com/watch?v=short",
                     "https://notyoutube.com/watch?v=x-s9y5FONxY", "https://vimeo.com/76979871"] {
            #expect(VideoCover.youTubeID(in: URL(string: page)!) == nil, "\(page)")
        }
        #expect(VideoCover.thumbnailURL(forPage: URL(string: "https://youtu.be/x-s9y5FONxY")!)?.absoluteString
            == "https://i.ytimg.com/vi/x-s9y5FONxY/mqdefault.jpg")
    }

    // Recorded from Safari over Accessibility: a normal window, and a private one, which adds to
    // the page title in its window's.
    private let normal = BrowserPages.Page(
        windowTitle: "(92) iPhone Duo en Mano - Contesto tus Dudas! - YouTube",
        title: "(92) iPhone Duo en Mano - Contesto tus Dudas! - YouTube",
        url: URL(string: "https://www.youtube.com/watch?v=x-s9y5FONxY")!
    )
    private let privateWindow = BrowserPages.Page(
        windowTitle: "Musica para trabajar activo y alegre - YouTube, navegación privada",
        title: "Musica para trabajar activo y alegre - YouTube",
        url: URL(string: "https://www.youtube.com/watch?v=ss9ieMG8kFU&list=RDss9ieMG8kFU&start_radio=1")!
    )

    @Test func titledVideoIsTheWindowShowingIt() {
        #expect(BrowserPages.page(playing: "iPhone Duo en Mano - Contesto tus Dudas!", among: [privateWindow, normal]) == normal)
        // Playing in a tab behind another: no window shows it.
        #expect(BrowserPages.page(playing: "Another video", among: [privateWindow, normal]) == nil)
    }

    @Test func untitledVideoIsTheOnePrivateWindowShowingOne() {
        #expect(BrowserPages.page(playing: "", among: [normal, privateWindow]) == privateWindow)
        // Two private windows on videos: no telling which plays.
        var other = privateWindow
        other.url = URL(string: "https://www.youtube.com/watch?v=x-s9y5FONxY")!
        #expect(BrowserPages.page(playing: "", among: [privateWindow, other]) == nil)
        // A private window on another site doesn't count.
        other.url = URL(string: "https://www.apple.com/")!
        #expect(BrowserPages.page(playing: "", among: [privateWindow, other]) == privateWindow)
        #expect(BrowserPages.page(playing: "", among: [normal]) == nil)
    }
}
