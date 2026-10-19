import Foundation
import Testing

@testable import DyNotch

struct LayoutTests {
    @Test func storedOrderDropsUnknownsAndRepeatsAndGainsNewCases() {
        let order: [NotchTab] = LayoutOrder.complete(["camera", "radio", "home", "camera"])
        #expect(order == [.camera, .home, .shelf, .timers])
        let fresh: [NotchTab] = LayoutOrder.complete(nil)
        #expect(fresh == NotchTab.allCases)
    }

    @Test func rearrangingShownItemsLeavesHiddenOnesInPlace() {
        // Shelf is hidden; Camera is dragged to the front.
        let order = LayoutOrder.rearranged([NotchTab.home, .shelf, .timers, .camera], shown: [.camera, .home, .timers])
        #expect(order == [.camera, .shelf, .home, .timers])
    }

    @Test func movingSwapsWithTheNeighbourAndStopsAtTheEnds() {
        let order: [TimerMode] = [.timer, .stopwatch, .pomodoro]
        #expect(LayoutOrder.moved(TimerMode.pomodoro, by: -1, in: order) == [.timer, .pomodoro, .stopwatch])
        #expect(LayoutOrder.moved(TimerMode.timer, by: 1, in: order) == [.stopwatch, .timer, .pomodoro])
        #expect(LayoutOrder.moved(TimerMode.timer, by: -1, in: order) == order)
        #expect(LayoutOrder.moved(TimerMode.pomodoro, by: 1, in: order) == order)
    }

    @Test func timerOrderIsSaved() throws {
        let suite = "app.dynotch.DyNotchTests.timerOrder"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.timerOrder == [.timer, .stopwatch, .pomodoro])
        settings.timerOrder = [.pomodoro, .timer, .stopwatch]
        #expect(AppSettings(defaults: defaults).timerOrder == [.pomodoro, .timer, .stopwatch])
    }

    @Test func layoutIsSavedAndTheLastTabStays() throws {
        // One fixed suite, emptied before and after, so runs don't pile up preference files.
        let suite = "app.dynotch.DyNotchTests.layout"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.tabOrder == NotchTab.allCases)
        #expect(settings.homeLayout == .standard)
        settings.tabOrder = [.timers, .home, .shelf, .camera]
        for tab in [NotchTab.home, .shelf, .camera, .timers] {
            settings.setTab(tab, visible: false)
        }
        #expect(settings.visibleTabs == [.timers])
        settings.openingTab = .camera
        settings.homeLayout.moveColumn(2, by: -1)
        settings.homeLayout.moveColumn(2, by: -1)
        settings.homeLayout.remove(.media)
        settings.homeLayout.remove(.weather)
        settings.headerBattery = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.tabOrder == [.timers, .home, .shelf, .camera])
        #expect(reloaded.visibleTabs == [.timers])
        #expect(reloaded.openingTab == .camera)
        // Camera is hidden, so the notch reopens the last tab instead.
        #expect(reloaded.effectiveOpeningTab == nil)
        #expect(reloaded.homeLayout.visibleColumns.map(\.cards) == [[.agenda], [.large(.clock)]])
        #expect(!reloaded.headerBattery)
        #expect(reloaded.headerSettingsButton)

        reloaded.setTab(.camera, visible: true)
        #expect(reloaded.visibleTabs == [.timers, .camera])
        #expect(reloaded.effectiveOpeningTab == .camera)
    }

    @Test func tabBarHidesOnlyWhileSwipingMovesBetweenTabs() throws {
        let suite = "app.dynotch.DyNotchTests.tabSwipe"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.tabSwipe == .threeFingers)
        #expect(settings.showsTabBar)
        settings.hideTabBar = true
        #expect(!settings.showsTabBar)
        settings.tabSwipe = .off
        // Without swiping the tabs would be out of reach, so the bar comes back.
        #expect(settings.showsTabBar)

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.tabSwipe == .off)
        #expect(reloaded.hideTabBar)
        reloaded.tabSwipe = .twoFingers
        #expect(!reloaded.showsTabBar)
    }

    @Test func cameraPictureSizeAndFlipAreSaved() throws {
        let suite = "app.dynotch.DyNotchTests.camera"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.cameraSize == .standard)
        #expect(settings.cameraMirrored)
        settings.cameraSize = .large
        settings.cameraMirrored = false

        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.cameraSize == .large)
        #expect(!reloaded.cameraMirrored)
    }

    @Test func musicPlayerIsSaved() throws {
        let suite = "app.dynotch.DyNotchTests.musicPlayer"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(settings.musicPlayer == .music)
        settings.musicPlayer = .deezer

        #expect(AppSettings(defaults: defaults).musicPlayer == .deezer)
    }

    @Test func largeCameraPictureIsWidescreenAcrossTheTab() {
        // The tab's margins: 16 at each side, 10 above and 14 below.
        let width = NotchMetrics.openWidth - 32
        #expect(abs((NotchMetrics.largeCameraContentHeight - 24) - width * 9 / 16) < 1)
    }
}
