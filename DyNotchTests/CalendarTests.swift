import Foundation
import Testing

@testable import DyNotch

struct MeetingLinkDetectorTests {
    @Test(arguments: [
        ("Join: https://us02web.zoom.us/j/8123456789?pwd=abc", "Zoom"),
        ("https://meet.google.com/abc-defg-hij", "Google Meet"),
        ("Click https://teams.microsoft.com/l/meetup-join/19%3ameeting_x/0?context=y to join", "Microsoft Teams"),
        ("https://acme.webex.com/meet/jane.doe", "Webex"),
        ("FaceTime https://facetime.apple.com/join#v=1&p=AbCd", "FaceTime"),
    ])
    func detectsServices(text: String, service: String) {
        #expect(MeetingLinkDetector.find(in: [text])?.service.rawValue == service)
    }

    @Test func stripsTrailingPunctuation() {
        let result = MeetingLinkDetector.find(in: [nil, "Link: https://zoom.us/j/123456."])
        #expect(result?.url.absoluteString == "https://zoom.us/j/123456")
    }

    @Test func prefersEarlierFields() {
        let result = MeetingLinkDetector.find(in: ["https://meet.google.com/aaa-bbbb-ccc", "https://zoom.us/j/1"])
        #expect(result?.service == .meet)
    }

    @Test func ignoresOrdinaryLinks() {
        #expect(MeetingLinkDetector.find(in: ["Office", "https://example.com/zoom"]) == nil)
    }
}

struct MiniCalendarTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func monthFillsWholeWeeksFromTheFirstWeekday() {
        let monday = calendar(firstWeekday: 2)
        // October 2026 starts on a Thursday, and its clocks go back on the 25th.
        let october = MonthGrid(containing: day(2026, 10, 8, in: monday), calendar: monday)
        #expect(october.weeks.count == 5)
        #expect(october.weeks.allSatisfy { $0.count == 7 })
        #expect(october.weeks[0].map(\.number) == [28, 29, 30, 1, 2, 3, 4])
        #expect(october.weeks[0].map(\.isInMonth) == [false, false, false, true, true, true, true])
        #expect(october.weeks[4].map(\.number) == [26, 27, 28, 29, 30, 31, 1])
        #expect(october.weeks.joined().allSatisfy { monday.startOfDay(for: $0.date) == $0.date })
        #expect(october.interval == DateInterval(start: day(2026, 9, 28, in: monday), end: day(2026, 11, 2, in: monday)))
        #expect(october.week(containing: day(2026, 10, 8, in: monday), calendar: monday).map(\.number) == [5, 6, 7, 8, 9, 10, 11])
        #expect(MonthGrid.weekdaySymbols(calendar: monday) == ["M", "T", "W", "T", "F", "S", "S"])

        // From Sunday, and a month that needs six weeks.
        let sunday = calendar(firstWeekday: 1)
        #expect(MonthGrid(containing: day(2026, 10, 1, in: sunday), calendar: sunday).weeks[0].first?.number == 27)
        #expect(MonthGrid.weekdaySymbols(calendar: sunday).first == "S")
        #expect(MonthGrid(containing: day(2026, 8, 20, in: monday), calendar: monday).weeks.count == 6)
    }
}
