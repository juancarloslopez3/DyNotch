import EventKit
import SwiftUI

/// The calendar and reminders in one card, switched with a small glass control when it shows
/// both. The calendar is the month at a glance; clicking it turns the card over to the events
/// coming up.
struct AgendaCard: View {
    @Environment(AppServices.self) private var services
    @AppStorage("agendaMode") private var mode = Mode.events
    var showEvents = true
    var showReminders = true
    /// With about half the column, the month makes way for this week.
    var height = HomeCardHeight.full

    enum Mode: String {
        case events, reminders
    }

    var body: some View {
        let current: Mode = !showReminders ? .events : !showEvents ? .reminders : mode

        FlipCard(canFlip: current == .events) {
            GlassCard(padding: 10, isInteractive: current == .events) {
                VStack(alignment: .leading, spacing: 8) {
                    header(current) {
                        switch current {
                        case .events: MonthTitle()
                        case .reminders: if !showEvents { title("Reminders") }
                        }
                    }
                    switch current {
                    case .events: MonthCalendar(weekOnly: height == .half)
                    case .reminders: RemindersList()
                    }
                }
            }
        } back: {
            GlassCard(padding: 10, isInteractive: true) {
                VStack(alignment: .leading, spacing: 8) {
                    header(.events) { title("Upcoming") }
                    EventsList()
                }
            }
        }
    }

    /// The switch between the calendar and reminders when the card shows both, `name`, and
    /// a button that opens the app.
    private func header(_ current: Mode, @ViewBuilder name: () -> some View) -> some View {
        HStack(spacing: 6) {
            if showEvents && showReminders {
                AgendaModePicker(mode: $mode)
            }
            name()
            Spacer(minLength: 0)
            Button {
                current == .events ? services.events.openCalendarApp() : services.events.openRemindersApp()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(current == .events ? "Open Calendar" : "Open Reminders")
        }
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// This month's name and year, kept current.
private struct MonthTitle: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.month(.wide).year())
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
    }
}

/// The month, or just this week, with dots for the days that have events.
private struct MonthCalendar: View {
    @Environment(AppServices.self) private var services
    let weekOnly: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            MiniMonthView(today: context.date, marks: services.events.dayMarks, weekOnly: weekOnly)
        }
        .help("Click for upcoming events")
    }
}

private struct AgendaModePicker: View {
    @Binding var mode: AgendaCard.Mode
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            segment(.events, "calendar")
            segment(.reminders, "checklist")
        }
        .padding(2)
        .background(.white.opacity(0.06), in: .capsule)
    }

    private func segment(_ value: AgendaCard.Mode, _ symbol: String) -> some View {
        Button {
            withAnimation(.notchQuick) { mode = value }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 20)
                .foregroundStyle(mode == value ? .white : .white.opacity(0.5))
                .background {
                    if mode == value {
                        Capsule().fill(.clear)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .matchedGeometryEffect(id: "agenda", in: namespace)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

private struct EventsList: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let kit = services.events
        if !kit.hasCalendarAccess {
            AccessPrompt(text: "Show your upcoming events", denied: kit.calendarStatus == .denied) {
                Task { await kit.requestCalendarAccess() }
            } openSettings: {
                services.permissions.openSettings(.calendars)
            }
        } else if kit.events.isEmpty {
            EmptyAgenda(symbol: "calendar", text: "No upcoming events")
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(kit.events) { EventRow(event: $0) }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct EventRow: View {
    let event: CalendarEventItem

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 8) {
                Capsule()
                    .fill(event.color)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(Self.timeText(event, now: context.date))
                        .font(.system(size: 10.5))
                        .foregroundStyle(event.isOngoing(at: context.date) ? event.color : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                JoinButton(event: event)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func timeText(_ event: CalendarEventItem, now: Date) -> String {
        let day = dayName(event, now: now)
        if event.isAllDay { return day.map { String(localized: "\($0) · All day") } ?? String(localized: "All day") }
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        if event.isOngoing(at: now) {
            return String(localized: "Now · until \(event.end.formatted(time))")
        }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 60 && day == nil {
            return String(localized: "In \(max(minutes, 1)) min · \(event.start.formatted(time))")
        }
        let hours = "\(event.start.formatted(time)) – \(event.end.formatted(time))"
        return day.map { "\($0) \(hours)" } ?? hours
    }

    /// "Tomorrow" or "Fri" for an event that starts on a later day; nil for one today.
    static func dayName(_ event: CalendarEventItem, now: Date) -> String? {
        let calendar = Calendar.current
        guard event.start > now, !calendar.isDate(event.start, inSameDayAs: now) else { return nil }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(event.start, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow")
        }
        // It starts the line: "Vie", not "vie", in Spanish.
        var weekday = Date.FormatStyle.dateTime.weekday(.abbreviated)
        weekday.capitalizationContext = .beginningOfSentence
        return event.start.formatted(weekday)
    }
}

private struct RemindersList: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let kit = services.events
        if !kit.hasRemindersAccess {
            AccessPrompt(text: "Show today's reminders", denied: kit.remindersStatus == .denied) {
                Task { await kit.requestRemindersAccess() }
            } openSettings: {
                services.permissions.openSettings(.reminders)
            }
        } else if kit.reminders.isEmpty {
            EmptyAgenda(symbol: "checkmark.circle", text: "All done for today")
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(kit.reminders) { reminder in
                        ReminderRow(reminder: reminder) { kit.complete(reminder) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

/// A small glass button that opens an event's online meeting, if it has one.
private struct JoinButton: View {
    let event: CalendarEventItem

    var body: some View {
        if let url = event.meetingURL {
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help(event.meetingService.map { String(localized: "Join \($0)") } ?? String(localized: "Join meeting"))
        }
    }
}

private struct ReminderRow: View {
    let reminder: ReminderItem
    /// Smaller type, to fit a small widget.
    var isCompact = false
    let complete: () -> Void
    @State private var isChecked = false

    var body: some View {
        HStack(spacing: isCompact ? 6 : 8) {
            Button {
                isChecked = true
                Haptics.perform(.levelChange)
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    complete()
                }
            } label: {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: isCompact ? 13 : 14))
                    .foregroundStyle(reminder.color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: isCompact ? 0 : 1) {
                Text(reminder.title)
                    .font(.system(size: isCompact ? 11.5 : 12, weight: .medium))
                    .strikethrough(isChecked)
                    .lineLimit(1)
                if let due = reminder.due {
                    Text(Self.dueText(due, hasTime: reminder.hasDueTime))
                        .font(.system(size: isCompact ? 10 : 10.5))
                        .foregroundStyle(Self.isOverdue(due, hasTime: reminder.hasDueTime) ? .red : .secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    static func isOverdue(_ due: Date, hasTime: Bool) -> Bool {
        hasTime ? due < .now : due < Calendar.current.startOfDay(for: .now)
    }

    static func dueText(_ due: Date, hasTime: Bool) -> String {
        if Calendar.current.isDateInToday(due) {
            return hasTime ? due.formatted(date: .omitted, time: .shortened) : String(localized: "Today")
        }
        return due.formatted(.relative(presentation: .named))
    }
}

private struct AccessPrompt: View {
    let text: LocalizedStringKey
    let denied: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(denied ? "Open Settings" : "Allow Access", action: denied ? openSettings : request)
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Asks for access from a small widget; only the button when it's narrow.
private struct SmallAccessPrompt: View {
    let symbol: String
    let text: String
    let denied: Bool
    let isNarrow: Bool
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        if isNarrow {
            button
        } else {
            // The name goes first when the button leaves no room for it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    symbolImage
                    Text(text)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    button
                }
                HStack(spacing: 6) {
                    symbolImage
                    Spacer(minLength: 4)
                    button
                }
            }
        }
    }

    private var symbolImage: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var button: some View {
        Button(denied ? (isNarrow ? "Settings" : "Open Settings") : "Allow", action: denied ? openSettings : request)
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("\(text) needs access")
    }
}

private struct EmptyAgenda: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.4))
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Small widgets

/// This week, or today alone when it's narrow. Clicking turns it over to the event going on or
/// coming up next.
struct CalendarSmallCard: View {
    let isNarrow: Bool

    var body: some View {
        FlipCard {
            SmallWidgetCard(isInteractive: true) {
                TimelineView(.everyMinute) { context in
                    if isNarrow {
                        TodayBadge(today: context.date)
                    } else {
                        WeekStripView(today: context.date)
                    }
                }
                .help("Click for the next event")
            }
        } back: {
            SmallWidgetCard(isInteractive: true) {
                NextEventRow(isNarrow: isNarrow)
            }
        }
    }
}

/// The event going on or coming up next (timed ones today and tomorrow before all-day ones),
/// with a Join button for an online meeting when there's room.
private struct NextEventRow: View {
    @Environment(AppServices.self) private var services
    let isNarrow: Bool

    var body: some View {
        let kit = services.events
        if !kit.hasCalendarAccess {
            SmallAccessPrompt(symbol: "calendar", text: HomeWidget.calendar.title, denied: kit.calendarStatus == .denied, isNarrow: isNarrow) {
                Task { await kit.requestCalendarAccess() }
            } openSettings: {
                services.permissions.openSettings(.calendars)
            }
        } else if let event = kit.nextEvent {
            TimelineView(.everyMinute) { context in
                HStack(spacing: 8) {
                    Capsule()
                        .fill(event.color)
                        .frame(width: 3, height: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(isNarrow ? Self.shortTime(event, now: context.date) : event.title)
                            .font(.system(size: 11.5, weight: .semibold))
                        Text(isNarrow ? event.title : EventRow.timeText(event, now: context.date))
                            .font(.system(size: 10))
                            .foregroundStyle(!isNarrow && event.isOngoing(at: context.date) ? event.color : .secondary)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !isNarrow {
                        JoinButton(event: event)
                    }
                }
                .help("\(event.title) · \(EventRow.timeText(event, now: context.date))")
            }
        } else {
            SmallEmptyState(symbol: "calendar", text: "No upcoming events", isNarrow: isNarrow)
        }
    }

    /// "Now", "In 5 min", "3:30 PM", "All day", "Tomorrow" or "Fri": what fits over the title
    /// in a narrow widget.
    static func shortTime(_ event: CalendarEventItem, now: Date) -> String {
        if let day = EventRow.dayName(event, now: now) { return day }
        if event.isAllDay { return String(localized: "All day") }
        if event.isOngoing(at: now) { return String(localized: "Now") }
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        return minutes < 60 ? String(localized: "In \(max(minutes, 1)) min") : event.start.formatted(date: .omitted, time: .shortened)
    }
}

/// The first reminder due, to tick off, and how many more there are; just the count when
/// it's narrow.
struct RemindersSmallCard: View {
    @Environment(AppServices.self) private var services
    let isNarrow: Bool

    var body: some View {
        let kit = services.events
        SmallWidgetCard {
            if !kit.hasRemindersAccess {
                SmallAccessPrompt(symbol: "checklist", text: HomeWidget.reminders.title, denied: kit.remindersStatus == .denied, isNarrow: isNarrow) {
                    Task { await kit.requestRemindersAccess() }
                } openSettings: {
                    services.permissions.openSettings(.reminders)
                }
            } else if let first = kit.reminders.first {
                let count = kit.reminders.count
                if isNarrow {
                    HStack(spacing: 5) {
                        Image(systemName: "checklist")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(first.color)
                        Text("\(count)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(value: Double(count)))
                    }
                    .help(count == 1 ? "1 reminder due" : "\(count) reminders due")
                } else {
                    HStack(spacing: 6) {
                        ReminderRow(reminder: first, isCompact: true) { kit.complete(first) }
                            .id(first.id)
                        if count > 1 {
                            Text("+\(count - 1)")
                                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .help("\(count - 1) more due")
                        }
                    }
                }
            } else {
                SmallEmptyState(symbol: "checkmark.circle", text: "All done for today", isNarrow: isNarrow)
            }
        }
    }
}

/// "Standup in 5 min [Join]" live activity.
struct MeetingActivityView: View {
    let meeting: MeetingEvent
    let notch: CGSize

    var body: some View {
        VStack(spacing: 0) {
            WingsLayout(notch: notch) {
                Image(systemName: "video.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(meeting.color)
            } trailing: {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text(Self.relative(meeting.start, now: context.date))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(meeting.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(meeting.service ?? String(localized: "Online meeting"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Join") {
                    NSWorkspace.shared.open(meeting.url)
                    AppServices.shared.activities.dismiss()
                }
                .buttonStyle(.tintedGlass(.green))
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)
        }
    }

    static func relative(_ start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        return minutes > 0 ? String(localized: "in \(minutes) min") : String(localized: "now")
    }
}
