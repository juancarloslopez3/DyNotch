import SwiftUI

/// The Home tab: up to three columns of cards, each widget large or small and in any order, as
/// set in Settings › Layout. By default the clock sits in the middle, right under the cut-out,
/// with the weather beneath it, and Now Playing and the agenda flank it.
struct HomeTabView: View {
    @Environment(AppServices.self) private var services

    /// The room the columns share: the open notch less its padding at the sides.
    static let width = NotchMetrics.openWidth - 32

    var body: some View {
        let layout = services.settings.homeLayout
        let columns = layout.visibleColumns

        HStack(spacing: HomeLayout.columnSpacing) {
            ForEach(columns) { column in
                HomeColumnStack(column: column, width: layout.width(of: column, sharing: Self.width)) { card, style in
                    HomeCardView(card: card, style: style)
                }
                .frame(width: layout.fixedWidth(of: column))
            }
            if columns.isEmpty {
                Text("Add Home widgets in Settings › Layout")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.notchQuick, value: layout)
    }
}

/// One Home column: its cards top to bottom, each drawn the way the column has room for. Next
/// to a large card, small ones beside each other share a row. The notch and the preview in
/// Settings › Layout both lay out with this.
struct HomeColumnStack<Card: View>: View {
    let column: HomeColumn
    /// The column's width: small widgets side by side in a narrow one get only their essentials.
    let width: CGFloat
    @ViewBuilder var card: (HomeCard, HomeCardStyle) -> Card

    var body: some View {
        VStack(spacing: 8) {
            ForEach(column.rows, id: \.first?.id) { row in
                // A row of small cards beside a large one keeps to its height; the rest share the column.
                if column.largeCount > 0, row.allSatisfy({ !$0.isLarge }) {
                    HStack(spacing: 8) {
                        ForEach(row) { item in
                            card(item, column.style(of: item, width: width))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(row) { item in
                        card(item, column.style(of: item, width: width))
                    }
                }
            }
        }
    }
}

/// A Home card: a large one, as tall as its column allows, or a small one on a single row.
private struct HomeCardView: View {
    let card: HomeCard
    let style: HomeCardStyle

    var body: some View {
        switch style {
        case .large(let height): LargeWidget(widgets: card.widgets, height: height)
        case .small(let isNarrow): SmallWidget(widget: card.id, isNarrow: isNarrow)
        }
    }
}

private struct LargeWidget: View {
    let widgets: [HomeWidget]
    let height: HomeCardHeight

    var body: some View {
        switch widgets.first {
        case .media?: NowPlayingCard(height: height)
        case .clock?: ClockCard(height: height)
        case .weather?: WeatherCard(height: height)
        case .battery?: BatteryCard(height: height)
        case .timer?: TimerCard(height: height)
        default: AgendaCard(showEvents: widgets.contains(.calendar), showReminders: widgets.contains(.reminders), height: height)
        }
    }
}

private struct SmallWidget: View {
    let widget: HomeWidget
    let isNarrow: Bool

    var body: some View {
        switch widget {
        case .media: NowPlayingSmallCard(isNarrow: isNarrow)
        case .clock: ClockSmallCard(isNarrow: isNarrow)
        case .weather: WeatherSmallCard(isNarrow: isNarrow)
        case .calendar: CalendarSmallCard(isNarrow: isNarrow)
        case .reminders: RemindersSmallCard(isNarrow: isNarrow)
        case .battery: BatterySmallCard(isNarrow: isNarrow)
        case .timer: TimerSmallCard(isNarrow: isNarrow)
        }
    }
}

/// The glass card every small widget sits in: a single row, the same height whatever it
/// shows, so the cards around it don't jump.
struct SmallWidgetCard<Content: View>: View {
    var tint: Color? = nil
    /// Responds to the pointer, for a card that turns over when clicked.
    var isInteractive = false
    @ViewBuilder var content: Content

    var body: some View {
        GlassCard(padding: 10, tint: tint, isInteractive: isInteractive) {
            content
                .frame(maxWidth: .infinity, minHeight: 26, maxHeight: .infinity)
        }
    }
}

/// "Nothing Playing" and the like, dimmed; only the symbol when it's narrow.
struct SmallEmptyState: View {
    let symbol: String
    let text: LocalizedStringKey
    let isNarrow: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            if !isNarrow {
                Text(text)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(isNarrow ? text : "")
    }
}
