import AppKit
import EventKit
import Observation
import SwiftUI

nonisolated struct CalendarEventItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let meetingURL: URL?
    let meetingService: String?

    func isOngoing(at date: Date) -> Bool { start <= date && date < end }
}

nonisolated struct ReminderItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let due: Date?
    let hasDueTime: Bool
    let color: Color
}

nonisolated struct CalendarSummary: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let source: String
    let color: Color
}

struct MeetingEvent: Equatable {
    var title: String
    var start: Date
    var url: URL
    var service: String?
    var color: Color
}

/// Calendar events and reminders through EventKit, plus meeting "Join" announcements.
@Observable
final class EventKitService {
    @ObservationIgnored let store = EKEventStore()
    @ObservationIgnored private weak var services: AppServices?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var announcedMeetings: Set<String> = []

    private(set) var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
    /// What's going on or coming up this week, soonest first.
    private(set) var events: [CalendarEventItem] = []
    /// The days of this month's mini calendar that have events, each with the colors of up to
    /// three of their calendars. Keyed by the start of the day.
    private(set) var dayMarks: [Date: [Color]] = [:]
    private(set) var reminders: [ReminderItem] = []
    private(set) var calendars: [CalendarSummary] = []
    private(set) var reminderLists: [CalendarSummary] = []
    /// The day `dayMarks` were found for, to find them again when it changes.
    @ObservationIgnored private var markedDay: Date?

    var hasCalendarAccess: Bool { calendarStatus == .fullAccess }
    var hasRemindersAccess: Bool { remindersStatus == .fullAccess }

    /// The event going on or coming up next: a timed one today or tomorrow before an all-day
    /// one, which would otherwise always come first.
    var nextEvent: CalendarEventItem? {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: .now)) ?? .now
        return events.first { !$0.isAllDay && $0.start < end } ?? events.first
    }

    func start(services: AppServices) {
        self.services = services
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.tick()
            }
        }
    }

    func requestCalendarAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        refresh()
    }

    func requestRemindersAccess() async {
        _ = try? await store.requestFullAccessToReminders()
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
        refresh()
    }

    func refresh() {
        calendarStatus = EKEventStore.authorizationStatus(for: .event)
        remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
        refreshEvents()
        refreshDayMarks()
        refreshReminders()
    }

    /// Re-filters by time every 30s (events end, meetings approach), and finds the days with
    /// events again when the day changes.
    private func tick() {
        refreshEvents()
        if markedDay != Calendar.current.startOfDay(for: .now) { refreshDayMarks() }
        announceMeetings()
    }

    // MARK: - Events

    private func refreshEvents() {
        guard hasCalendarAccess, let settings = services?.settings else {
            events = []
            calendars = []
            return
        }
        let all = store.calendars(for: .event)
        calendars = all.map(Self.summary).sorted { ($0.source, $0.title) < ($1.source, $1.title) }
        let hidden = Set(settings.hiddenCalendarIDs)
        let visible = all.filter { !hidden.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else {
            events = []
            return
        }
        let now = Date.now
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        let predicate = store.predicateForEvents(withStart: calendar.startOfDay(for: now), end: end, calendars: visible)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.status != .canceled && !Self.isDeclined($0) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(20)
            .map(Self.item)
    }

    private func refreshDayMarks() {
        let calendar = Calendar.current
        markedDay = calendar.startOfDay(for: .now)
        var marks: [Date: [Color]] = [:]
        if hasCalendarAccess, let settings = services?.settings {
            let hidden = Set(settings.hiddenCalendarIDs)
            let visible = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
            let shown = MonthGrid(containing: .now, calendar: calendar).interval
            var calendarsByDay: [Date: Set<String>] = [:]
            if !visible.isEmpty {
                let predicate = store.predicateForEvents(withStart: shown.start, end: shown.end, calendars: visible)
                let found = store.events(matching: predicate)
                    .filter { $0.status != .canceled && !Self.isDeclined($0) }
                    .sorted { $0.startDate < $1.startDate }
                for event in found {
                    // Every day it covers; one that ends at midnight doesn't reach into that day.
                    let last = max(event.endDate.addingTimeInterval(-1), event.startDate)
                    var day = max(calendar.startOfDay(for: event.startDate), shown.start)
                    while day <= last, day < shown.end {
                        if calendarsByDay[day, default: []].count < 3,
                           calendarsByDay[day, default: []].insert(event.calendar.calendarIdentifier).inserted {
                            marks[day, default: []].append(Color(cgColor: event.calendar.cgColor))
                        }
                        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                        day = next
                    }
                }
            }
        }
        if marks != dayMarks { dayMarks = marks }
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    private static func item(_ event: EKEvent) -> CalendarEventItem {
        let meeting = MeetingLinkDetector.find(in: [event.url?.absoluteString, event.location, event.notes])
        return CalendarEventItem(
            id: (event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString)
                + "@\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? String(localized: "Untitled"),
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: Color(cgColor: event.calendar.cgColor),
            meetingURL: meeting?.url,
            meetingService: meeting?.service.rawValue
        )
    }

    private static func summary(_ calendar: EKCalendar) -> CalendarSummary {
        CalendarSummary(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            source: calendar.source?.title ?? "",
            color: Color(cgColor: calendar.cgColor)
        )
    }

    // MARK: - Meetings

    private func announceMeetings() {
        guard let services, services.settings.liveMeetings else { return }
        let now = Date.now
        for event in events where !event.isAllDay {
            guard let url = event.meetingURL else { continue }
            let untilStart = event.start.timeIntervalSince(now)
            // Once 5 minutes before, once at the start time.
            let stage: String? = switch untilStart {
            case 60...(5 * 60): "soon"
            case -60..<60: "now"
            default: nil
            }
            guard let stage, announcedMeetings.insert("\(event.id)-\(stage)").inserted else { continue }
            services.activities.post(LiveActivity(
                id: "meeting-\(event.id)",
                kind: .meeting(MeetingEvent(
                    title: event.title, start: event.start, url: url,
                    service: event.meetingService, color: event.color
                )),
                duration: 25
            ))
        }
    }

    // MARK: - Reminders

    private func refreshReminders() {
        guard hasRemindersAccess, let settings = services?.settings else {
            reminders = []
            reminderLists = []
            return
        }
        let all = store.calendars(for: .reminder)
        reminderLists = all.map(Self.summary).sorted { $0.title < $1.title }
        let hidden = Set(settings.hiddenReminderListIDs)
        let visible = all.filter { !hidden.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else {
            reminders = []
            return
        }
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: visible)
        store.fetchReminders(matching: predicate) { @Sendable [weak self] reminders in
            let items = (reminders ?? [])
                .map { reminder in
                    ReminderItem(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? String(localized: "Untitled"),
                        due: reminder.dueDateComponents?.date,
                        hasDueTime: reminder.dueDateComponents?.hour != nil,
                        color: Color(cgColor: reminder.calendar.cgColor)
                    )
                }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            Task { @MainActor in self?.reminders = Array(items.prefix(12)) }
        }
    }

    func complete(_ item: ReminderItem) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        withAnimation(.notchQuick) {
            reminders.removeAll { $0.id == item.id }
        }
        try? store.save(reminder, commit: true)
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }
}
