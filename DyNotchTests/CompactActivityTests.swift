import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import DyNotch

struct CompactActivityTests {
    @Test func whatStartedFirstKeepsItsPlaceAndTheNextGoesInTheBubble() {
        // Music playing, then a timer: the music stays attached, the timer comes out beside it.
        var order = CompactActivity.arranged([.media], keeping: [])
        order = CompactActivity.arranged([.timer, .media], keeping: order)
        #expect(order == [.media, .timer])
        // The music stops: the timer moves in.
        order = CompactActivity.arranged([.timer], keeping: order)
        #expect(order == [.timer])
        // Music again: this time it's the one beside the timer.
        order = CompactActivity.arranged([.timer, .media], keeping: order)
        #expect(order == [.timer, .media])
    }

    @Test func activitiesStartingTogetherGoInTheOrderTheyreGiven() {
        #expect(CompactActivity.arranged([.timer, .media, .capsLock], keeping: []) == [.timer, .media, .capsLock])
    }

    @Test func aThirdWaitsItsTurn() {
        var order = CompactActivity.arranged([.media, .capsLock], keeping: [.media])
        order = CompactActivity.arranged([.timer, .media, .capsLock], keeping: order)
        #expect(order == [.media, .capsLock, .timer])
        // Caps Lock goes off: the timer takes the bubble.
        order = CompactActivity.arranged([.timer, .media], keeping: order)
        #expect(order == [.media, .timer])
    }

    @Test func aTimeGetsAnOvalAndTheRestACircle() {
        let notch = CGSize(width: 184, height: 32)
        let round = notch.height - NotchMetrics.bubbleInset * 2
        #expect(CompactActivity.media.bubbleSize(notch: notch) == CGSize(width: round, height: round))
        #expect(CompactActivity.capsLock.bubbleSize(notch: notch) == CGSize(width: round, height: round))
        let oval = CompactActivity.timer.bubbleSize(notch: notch)
        #expect(oval.height == round)
        #expect(oval.width > round)
    }

    @Test func anActivityOpensItsTabWhileThatShows() throws {
        let suite = "app.dynotch.DyNotchTests.bubbleTab"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        #expect(CompactActivity.timer.tab(in: settings) == .timers)
        #expect(CompactActivity.media.tab(in: settings) == .home)
        #expect(CompactActivity.capsLock.tab(in: settings) == nil)
        #expect(CompactActivity.clock.tab(in: settings) == nil)
        // A hidden tab, or a Home tab without the player, opens the usual tab instead.
        settings.setTab(.timers, visible: false)
        #expect(CompactActivity.timer.tab(in: settings) == nil)
        settings.homeLayout.remove(.media)
        #expect(CompactActivity.media.tab(in: settings) == nil)
        // Without the Timers tab, Home with the Timer widget does.
        settings.homeLayout = HomeLayout(columns: [HomeColumn(id: 0, cards: [.large(.timer)])])
        #expect(CompactActivity.timer.tab(in: settings) == .home)
    }

    @Test func aLiveActivityOpensItsTabWhileThatShows() throws {
        let suite = "app.dynotch.DyNotchTests.liveActivityTab"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        let finished = LiveActivityKind.timerFinished(TimerFinishedEvent(title: "Timer Done", detail: "5:00 timer", mode: .pomodoro))
        let song = LiveActivityKind.nowPlaying(title: "Midnight City", artist: "M83", change: .skipped(forward: true))
        let meeting = LiveActivityKind.meeting(MeetingEvent(
            title: "Design Review", start: .now, url: try #require(URL(string: "https://zoom.us/j/123")), service: "Zoom", color: .blue
        ))
        let battery = LiveActivityKind.battery(BatteryEvent(kind: .pluggedIn, percent: 64, isCharging: true, minutes: 48))
        #expect(finished.tab(in: settings) == .timers)
        #expect(song.tab(in: settings) == .home)
        #expect(meeting.tab(in: settings) == .home)
        // The standard Home tab has no Battery widget, and Caps Lock has nothing more anywhere.
        #expect(battery.tab(in: settings) == nil)
        #expect(LiveActivityKind.capsLock(true).tab(in: settings) == nil)

        settings.homeLayout = HomeLayout(columns: [HomeColumn(id: 0, cards: [.large(.battery)])])
        #expect(battery.tab(in: settings) == .home)
        #expect(song.tab(in: settings) == nil)
        #expect(meeting.tab(in: settings) == nil)
        // A hidden Home tab can't show it.
        settings.setTab(.home, visible: false)
        #expect(battery.tab(in: settings) == nil)
        #expect(finished.tab(in: settings) == .timers)
    }
}
