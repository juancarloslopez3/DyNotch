import CoreGraphics
import Foundation
import Testing

@testable import DyNotch

struct FullScreenTests {
    /// A 14" MacBook Pro's screen, in the window list's top-left coordinates.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// The Dock's see-through window covers every screen, whatever is full screen.
    let dock = FullScreenDetection.Window(pid: 600, layer: 20, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))

    /// Safari with a YouTube video in full screen, as SkyLight reported it (trimmed).
    let safariSpace: [String: Any] = [
        "ManagedSpaceID": 36, "type": 4, "pid": 2704, "fs_wid": 674,
        "TileLayoutManager": ["TileSpaces": [["appName": "Safari", "pid": 2704, "TileType": "Primary", "TileWindowID": 674, "type": 5]]],
    ]

    @Test func aFullScreenSpaceNamesItsApp() {
        // The menu bar's window is on screen all along, and the video sits below the notch.
        let windows = [dock, .init(pid: 2704, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1512, height: 949))]
        #expect(FullScreenDetection.apps(currentSpace: safariSpace, windows: windows, screen: screen) == [.init(pid: 2704, window: 674)])
    }

    @Test func aFullScreenSpaceNamesTheWindowFillingIt() {
        // Safari browsing in full screen (window 1741), then playing a video full screen from
        // there: the video gets a Space and a window (1764) of its own.
        let browsing: [String: Any] = [
            "ManagedSpaceID": 423, "type": 4, "pid": 2704, "fs_wid": 1741,
            "TileLayoutManager": ["TileSpaces": [["appName": "Safari", "pid": 2704, "TileWindowID": 1741]]],
        ]
        let video: [String: Any] = [
            "ManagedSpaceID": 427, "type": 4, "pid": 2704, "fs_wid": 1764,
            "TileLayoutManager": ["TileSpaces": [["appName": "Safari", "pid": 2704, "TileWindowID": 1764]]],
        ]
        #expect(FullScreenDetection.apps(currentSpace: browsing, windows: [], screen: screen) == [.init(pid: 2704, window: 1741)])
        #expect(FullScreenDetection.apps(currentSpace: video, windows: [], screen: screen) == [.init(pid: 2704, window: 1764)])
        // Mid-switch the tile can lose its window for a moment.
        let switching: [String: Any] = ["type": 4, "pid": 2704, "TileLayoutManager": ["TileSpaces": [["pid": 2704]]]]
        #expect(FullScreenDetection.apps(currentSpace: switching, windows: [], screen: screen) == [.init(pid: 2704)])
    }

    @Test func appsSideBySideAreBothFullScreen() {
        let space: [String: Any] = [
            "type": 4, "pid": 2704,
            "TileLayoutManager": ["TileSpaces": [["pid": 2704], ["pid": 812]]],
        ]
        #expect(FullScreenDetection.apps(currentSpace: space, windows: [], screen: screen) == [.init(pid: 2704), .init(pid: 812)])
    }

    @Test func aFullScreenSpaceWithoutTilesFallsBackToItsApp() {
        let space: [String: Any] = ["type": 4, "pid": 2704, "fs_wid": 674]
        #expect(FullScreenDetection.apps(currentSpace: space, windows: [], screen: screen) == [.init(pid: 2704, window: 674)])
    }

    @Test func zoomedWindowsOnTheDesktopAreNotFullScreen() {
        let desktop: [String: Any] = ["ManagedSpaceID": 1, "type": 0]
        let zoomed = [dock, .init(pid: 2704, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1512, height: 863))]
        #expect(FullScreenDetection.apps(currentSpace: desktop, windows: zoomed, screen: screen) == nil)
        // With the Dock hidden, a zoomed window reaches the bottom, as a full-screen one does.
        let dockHidden = [dock, .init(pid: 2704, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1512, height: 949))]
        #expect(FullScreenDetection.apps(currentSpace: desktop, windows: dockHidden, screen: screen) == nil)
        #expect(FullScreenDetection.apps(currentSpace: nil, windows: dockHidden, screen: screen) == nil)
    }

    @Test func aWindowOverTheWholeScreenInFrontIsFullScreen() {
        let desktop: [String: Any] = ["type": 0]
        let game = FullScreenDetection.Window(pid: 900, number: 51, layer: 0, bounds: screen)
        let other = FullScreenDetection.Window(pid: 2704, layer: 0, bounds: CGRect(x: 0, y: 33, width: 800, height: 600))
        #expect(FullScreenDetection.apps(currentSpace: desktop, windows: [dock, game, other], screen: screen) == [.init(pid: 900, window: 51)])
        // Behind another window, it isn't what's on screen.
        #expect(FullScreenDetection.apps(currentSpace: desktop, windows: [dock, other, game], screen: screen) == nil)
    }

    @Test func onlyTheScreenItCoversIsFullScreen() {
        let external = CGRect(x: 1512, y: -458, width: 2560, height: 1440)
        let game = FullScreenDetection.Window(pid: 900, layer: 0, bounds: screen)
        #expect(FullScreenDetection.apps(currentSpace: nil, windows: [game], screen: external) == nil)
    }

    @Test func readsWindowsFromTheWindowList() throws {
        let info: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: 2704),
            kCGWindowNumber as String: NSNumber(value: 1741),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowBounds as String: CGRect(x: 0, y: 33, width: 1512, height: 949).dictionaryRepresentation,
        ]
        let window = try #require(FullScreenDetection.Window(info))
        #expect(window == .init(pid: 2704, number: 1741, layer: 0, bounds: CGRect(x: 0, y: 33, width: 1512, height: 949)))
    }

    @Test func notchStaysInFullScreenUnlessTurnedOn() throws {
        let suite = "app.dynotch.DyNotchTests.hideInFullScreen"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(!settings.hideInFullScreen)
        settings.hideInFullScreen = true

        #expect(AppSettings(defaults: defaults).hideInFullScreen)
    }

    @Test func playerHidesInFullScreenUnlessTurnedOff() throws {
        let suite = "app.dynotch.DyNotchTests.hidePlayerInFullScreen"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.hidePlayerInFullScreen)
        settings.hidePlayerInFullScreen = false

        #expect(!AppSettings(defaults: defaults).hidePlayerInFullScreen)
    }
}
