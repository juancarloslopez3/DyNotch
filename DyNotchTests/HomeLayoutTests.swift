import Foundation
import Testing

@testable import DyNotch

struct HomeLayoutTests {
    @Test func oldSettingsBecomeTheSameHomeTab() throws {
        let classic = HomeLayout.migrated(columnOrder: nil, media: true, weather: true, calendar: true, reminders: true)
        #expect(classic == .standard)

        let custom = HomeLayout.migrated(
            columnOrder: ["agenda", "clock", "media"], media: false, weather: true, calendar: false, reminders: true
        )
        #expect(custom.visibleColumns.map(\.cards) == [[.large(.reminders)], [.large(.clock), .small(.weather)]])

        // Through the settings, from the keys older versions stored.
        let suite = "app.dynotch.DyNotchTests.migration"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["clock", "media", "agenda"], forKey: "homeColumnOrder")
        defaults.set(false, forKey: "widgetWeather")
        // The clock could be switched off then; it stays now.
        defaults.set(false, forKey: "widgetClock")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.homeLayout.visibleColumns.map(\.cards) == [[.large(.clock)], [.large(.media)], [.agenda]])
    }

    @Test func layoutsStoredBeforeCardsLookTheSame() throws {
        // A large card with small widgets side by side under it, and small ones on their own.
        let json = """
        {"columns": [
            {"id": 0, "large": ["media"], "small": []},
            {"id": 1, "large": ["clock"], "small": ["weather", "battery"]},
            {"id": 2, "large": [], "small": ["calendar", "timer"]}
        ], "lastPlaces": {"reminders": {"column": 2, "isLarge": true, "index": 0}}}
        """
        let layout = try JSONDecoder().decode(HomeLayout.self, from: Data(json.utf8))
        #expect(layout.columns.map(\.cards) == [
            [.large(.media)],
            [.large(.clock), .small(.weather), .small(.battery)],
            [.small(.calendar), .small(.timer)],
        ])
        #expect(layout.columns[1].rows.map(\.count) == [1, 2])
    }

    @Test func twoLargeWidgetsStackInEitherOrder() {
        // The clock large, under the weather that's large too.
        var layout = HomeLayout.standard
        #expect(layout.canMakeLarge(.weather))
        layout.makeLarge(.weather)
        #expect(layout.columns[1].cards == [.large(.clock), .large(.weather)])
        layout.move(.clock, by: 1)
        #expect(layout.columns[1].cards == [.large(.weather), .large(.clock)])
        #expect(layout.columns[1].cards.map { layout.columns[1].style(of: $0, width: 168) } == [.large(.half), .large(.half)])
        #expect(layout.fixedWidth(of: layout.columns[1]) == HomeLayout.narrowColumnWidth)
        // Nothing else fits beside them.
        #expect(!layout.canAdd(.battery, large: true, to: 1))
        #expect(!layout.canAdd(.battery, large: false, to: 1))
        #expect(!layout.canMove(.clock, by: 1))
    }

    @Test func aWidgetIsInOnePlaceAndMovesWhenAddedElsewhere() {
        var layout = HomeLayout.standard
        // The weather moves under Now Playing.
        layout.add(.weather, large: true, to: 0)
        #expect(layout.columns[0].cards == [.large(.media), .large(.weather)])
        #expect(layout.columns[1].cards == [.large(.clock)])
        #expect(!layout.canAdd(.weather, large: false, to: 0))
        #expect(!layout.canAdd(.clock, large: false, to: 0))
        // The clock goes small over the agenda, which empties the middle.
        layout.add(.clock, large: false, to: 2)
        layout.move(.clock, by: -1)
        #expect(layout.columns[2].cards == [.small(.clock), .agenda])
        #expect(layout.columns[1].isEmpty)
        #expect(layout.visibleColumns.map(\.id) == [0, 2])
    }

    @Test func aColumnFitsTwoLargeOrOneWithTwoSmallOrThreeSmall() {
        var layout = HomeLayout.standard
        layout.add(.battery, large: false, to: 1)
        #expect(layout.columns[1].cards == [.large(.clock), .small(.weather), .small(.battery)])
        #expect(!layout.canAdd(.timer, large: false, to: 1))
        #expect(!layout.canAdd(.timer, large: true, to: 1))
        // No room for a second large card: the battery trades places with the clock.
        layout.makeLarge(.battery)
        #expect(layout.columns[1].cards == [.large(.battery), .small(.weather), .small(.clock)])
        // Without a large card, three small ones stack.
        layout.makeSmall([.battery])
        #expect(layout.columns[1].cards == [.small(.battery), .small(.weather), .small(.clock)])
        #expect(layout.columns[1].rows.count == 3)
        #expect(!layout.canAdd(.timer, large: false, to: 1))
        #expect(!layout.canAdd(.timer, large: true, to: 1))
        layout.remove(.weather)
        #expect(layout.canAdd(.timer, large: true, to: 1))
    }

    @Test func calendarAndRemindersShareALargeCard() {
        var layout = HomeLayout.standard
        // One made small leaves the card, on its side.
        layout.makeSmall([.calendar])
        #expect(layout.columns[2].cards == [.small(.calendar), .large(.reminders)])
        layout.makeLarge(.calendar)
        #expect(layout.columns[2].cards == [.agenda])
        layout.makeSmall([.calendar, .reminders])
        #expect(layout.columns[2].cards == [.small(.calendar), .small(.reminders)])

        // Large next to the other, it joins its card.
        layout.makeLarge(.reminders)
        layout.remove(.calendar)
        layout.add(.calendar, large: true, to: 2)
        #expect(layout.columns[2].cards == [.agenda])
        // With two small widgets beside it, the card can't go small.
        layout.add(.battery, large: false, to: 2)
        layout.add(.timer, large: false, to: 2)
        #expect(!layout.canMakeSmall([.calendar]))
        #expect(!layout.canMakeSmall([.calendar, .reminders]))
    }

    @Test func smallWidgetsOnTheirOwnShowLargeWhenThereIsRoom() {
        let alone = HomeColumn(id: 0, cards: [.small(.clock)])
        #expect(alone.style(of: .small(.clock), width: 168) == .large(.full))
        let two = HomeColumn(id: 0, cards: [.small(.clock), .small(.battery)])
        #expect(two.cards.map { two.style(of: $0, width: 168) } == [.large(.half), .large(.half)])
        let three = HomeColumn(id: 0, cards: [.small(.clock), .small(.battery), .small(.timer)])
        #expect(three.cards.allSatisfy { three.style(of: $0, width: 168) == .small(isNarrow: false) })
        #expect(!three.areBeside(0, 1))

        // Beside a large card they keep to a row, side by side when next to each other.
        let under = HomeColumn(id: 0, cards: [.large(.weather), .small(.clock), .small(.battery)])
        #expect(under.rows.map(\.count) == [1, 2])
        #expect(under.areBeside(1, 2))
        #expect(!under.areBeside(0, 1))
        #expect(under.style(of: .large(.weather), width: 230) == .large(.short))
        #expect(under.style(of: .small(.clock), width: 230) == .small(isNarrow: true))
        #expect(under.style(of: .small(.clock), width: 300) == .small(isNarrow: false))
        let around = HomeColumn(id: 0, cards: [.small(.clock), .large(.weather), .small(.battery)])
        #expect(around.rows.map(\.count) == [1, 1, 1])
        #expect(around.style(of: .large(.weather), width: 230) == .large(.half))
        #expect(around.style(of: .small(.clock), width: 230) == .small(isNarrow: false))
    }

    @Test func columnsMoveAroundEmptyOnes() {
        var layout = HomeLayout.standard
        layout.add(.clock, large: false, to: 0)
        layout.remove(.weather)
        layout.moveColumn(2, by: -1)
        #expect(layout.columns.map(\.id) == [2, 1, 0])
    }

    @Test func narrowColumnsNeedThreeShowingAndAWideOne() {
        var layout = HomeLayout.standard
        #expect(layout.columns.map { layout.fixedWidth(of: $0) } == [nil, HomeLayout.narrowColumnWidth, nil])
        #expect(layout.columns.map { layout.width(of: $0, sharing: 648) } == [230, 168, 230])
        layout.add(.battery, large: false, to: 1)
        #expect(layout.columns[1].style(of: .small(.battery), width: 168) == .small(isNarrow: true))

        var two = layout
        two.remove(.media)
        #expect(two.visibleColumns.allSatisfy { two.fixedWidth(of: $0) == nil })
        #expect(two.width(of: two.columns[1], sharing: 648) == 319)
        #expect(two.columns[1].style(of: .small(.battery), width: 319) == .small(isNarrow: false))

        // Now Playing on its own shows large, which needs the room.
        var media = HomeLayout.standard
        media.makeSmall([.media])
        #expect(media.fixedWidth(of: media.columns[0]) == nil)

        // Beside two narrow columns, a wide one has room for two detailed small widgets.
        var wide = HomeLayout.standard
        wide.remove(.calendar)
        wide.remove(.reminders)
        wide.add(.timer, large: false, to: 2)
        wide.add(.battery, large: false, to: 0)
        wide.add(.calendar, large: false, to: 0)
        #expect(wide.width(of: wide.columns[0], sharing: 648) == 292)
        #expect(wide.columns[0].style(of: .small(.calendar), width: 292) == .small(isNarrow: false))

        var allNarrow = layout
        allNarrow.remove(.media)
        allNarrow.add(.weather, large: true, to: 0)
        allNarrow.remove(.calendar)
        allNarrow.remove(.reminders)
        allNarrow.add(.timer, large: false, to: 2)
        #expect(allNarrow.visibleColumns.count == 3)
        #expect(allNarrow.visibleColumns.allSatisfy { allNarrow.fixedWidth(of: $0) == nil })
    }

    @Test func storedLayoutsAreRepaired() throws {
        let json = """
        {"columns": [
            {"id": 4, "cards": [
                {"widgets": ["clock", "weather"], "isLarge": true},
                {"widgets": ["radio"], "isLarge": false},
                {"widgets": ["battery", "timer"], "isLarge": false},
                {"widgets": ["clock"], "isLarge": false},
                {"widgets": ["reminders"], "isLarge": true},
                {"widgets": ["media"], "isLarge": true}
            ]},
            {"id": 4, "cards": [
                {"widgets": ["reminders"], "isLarge": true},
                {"widgets": ["weather"], "isLarge": false},
                {"widgets": ["calendar"], "isLarge": true},
                {"widgets": ["media"], "isLarge": false}
            ]}
        ]}
        """
        let layout = try JSONDecoder().decode(HomeLayout.self, from: Data(json.utf8))
        #expect(layout.columns.map(\.id) == [4, 0, 1])
        #expect(layout.columns[0].cards == [.large(.clock), .small(.battery)])
        #expect(layout.columns[1].cards == [.agenda, .small(.weather), .small(.media)])
        #expect(layout.columns[2].isEmpty)

        var custom = HomeLayout.standard
        custom.makeLarge(.weather)
        custom.move(.weather, by: -1)
        let decoded = try JSONDecoder().decode(HomeLayout.self, from: JSONEncoder().encode(custom))
        #expect(decoded == custom)
    }

    @Test func theClockStaysOnTheHomeTab() throws {
        var layout = HomeLayout.standard
        layout.remove(.clock)
        #expect(layout == .standard)

        // Stored without it, it comes back: large in an empty column,
        let json = """
        {"columns": [
            {"id": 0, "cards": [{"widgets": ["media"], "isLarge": true}]},
            {"id": 1, "cards": []},
            {"id": 2, "cards": [{"widgets": ["calendar", "reminders"], "isLarge": true}]}
        ]}
        """
        let stored = try JSONDecoder().decode(HomeLayout.self, from: Data(json.utf8))
        #expect(stored.columns[1].cards == [.large(.clock)])
        // or small in the first column with room,
        let full = HomeLayout(columns: [
            HomeColumn(id: 0, cards: [.large(.media)]),
            HomeColumn(id: 1, cards: [.large(.weather), .small(.battery)]),
            HomeColumn(id: 2, cards: [.agenda]),
        ])
        #expect(full.columns[0].cards == [.large(.media), .small(.clock)])
        // or else in place of the last card.
        let packed = HomeLayout(columns: [
            HomeColumn(id: 0, cards: [.large(.media), .large(.weather)]),
            HomeColumn(id: 1, cards: [.large(.calendar), .large(.battery)]),
            HomeColumn(id: 2, cards: [.large(.reminders), .large(.timer)]),
        ])
        #expect(packed.columns[2].cards == [.large(.reminders), .large(.clock)])
        #expect(!packed.contains(.timer))
    }

    @Test func draggedCardsLandWhereverTheyFit() {
        let layout = HomeLayout.standard
        // Up its column: the weather over the clock.
        #expect(layout.dropping([.weather], large: false, in: 1, at: 0)?.columns[1].cards == [.small(.weather), .large(.clock)])
        // Into another column, at its size.
        let across = layout.dropping([.weather], large: false, in: 0, at: 1)
        #expect(across?.columns[0].cards == [.large(.media), .small(.weather)])
        #expect(across?.columns[1].cards == [.large(.clock)])
        // Large where only a small card fits, it goes small, and its own column empties.
        let shrunk = layout.dropping([.media], large: true, in: 1, at: 2)
        #expect(shrunk?.columns[1].cards == [.large(.clock), .small(.weather), .small(.media)])
        #expect(shrunk?.columns[0].isEmpty == true)
        // Calendar and Reminders move together, into an empty column too.
        var emptied = layout
        emptied.remove(.media)
        let agenda = emptied.dropping([.calendar, .reminders], large: true, in: 0, at: 0)
        #expect(agenda?.columns[0].cards == [.agenda])
        #expect(agenda?.columns[2].isEmpty == true)
        // Large next to Reminders, Calendar shares its card again.
        var split = layout
        split.makeSmall([.calendar])
        #expect(split.dropping([.calendar], large: true, in: 2, at: 1)?.columns[2].cards == [.agenda])
        // A widget from the tray, small beside the weather.
        let added = layout.dropping([.battery], large: false, in: 1, at: 2)
        #expect(added?.columns[1].cards == [.large(.clock), .small(.weather), .small(.battery)])
        #expect(added?.columns[1].rows.map(\.count) == [1, 2])
        // A full column takes nothing more, at either size.
        #expect(added?.dropping([.timer], large: false, in: 1, at: 0) == nil)
        // Dropped where it was, nothing changes.
        #expect(layout.dropping([.clock], large: true, in: 1, at: 0) == layout)
    }
}
