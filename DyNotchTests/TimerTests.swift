import Foundation
import Testing

@testable import DyNotch

struct TimerTests {
    @Test func countdownPausesAndResumes() {
        let start = Date(timeIntervalSince1970: 0)
        var countdown = Countdown(duration: 60)
        countdown.start(at: start)
        #expect(countdown.remaining(at: start.addingTimeInterval(20)) == 40)
        countdown.pause(at: start.addingTimeInterval(20))
        #expect(countdown.remaining(at: start.addingTimeInterval(500)) == 40)
        countdown.resume(at: start.addingTimeInterval(100))
        #expect(countdown.remaining(at: start.addingTimeInterval(130)) == 10)
        #expect(!countdown.isFinished(at: start.addingTimeInterval(139)))
        #expect(countdown.isFinished(at: start.addingTimeInterval(140)))
    }

    @Test func addingTimeExtendsARunningCountdown() {
        let start = Date(timeIntervalSince1970: 0)
        var countdown = Countdown(duration: 60)
        countdown.start(at: start)
        countdown.add(60, at: start)
        #expect(countdown.remaining(at: start.addingTimeInterval(30)) == 90)
        #expect(countdown.progress(at: start.addingTimeInterval(60)) == 0.5)
    }

    @Test func pomodoroCyclesThroughBreaks() {
        var phase = PomodoroPhase.focus(round: 1)
        var sequence: [PomodoroPhase] = []
        for _ in 0..<5 {
            phase = phase.next(rounds: 2)
            sequence.append(phase)
        }
        #expect(sequence == [.shortBreak(afterRound: 1), .focus(round: 2), .longBreak, .focus(round: 1), .shortBreak(afterRound: 1)])
        #expect(PomodoroPhase.longBreak.duration(work: 25, shortBreak: 5, longBreak: 15) == 900)
    }

    @Test func stopwatchAccumulatesAcrossPauses() {
        let start = Date(timeIntervalSince1970: 0)
        var stopwatch = Stopwatch()
        stopwatch.start(at: start)
        stopwatch.pause(at: start.addingTimeInterval(10))
        stopwatch.start(at: start.addingTimeInterval(100))
        #expect(stopwatch.elapsed(at: start.addingTimeInterval(105)) == 15)
    }

    @Test func formatsTime() {
        #expect(TimeFormat.clock(65) == "1:05")
        #expect(TimeFormat.clock(3723) == "1:02:03")
        #expect(TimeFormat.clock(0.2) == "0:01")
        #expect(TimeFormat.precise(62.345) == "01:02.34")
    }
}
