import SwiftUI

/// Rows for Settings › Weather: the chosen city with its weather now, and a field that looks
/// places up on Open-Meteo as you type. ↑ and ↓ move through the results, Return picks one
/// (the first when none is highlighted) and Esc clears the search.
struct CityPicker: View {
    @Environment(AppServices.self) private var services
    @State private var query = ""
    @State private var results: [SavedCity] = []
    @State private var phase = Phase.idle
    @State private var highlighted: Int?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private enum Phase {
        case idle, searching, done, failed
    }

    var body: some View {
        let chosen = services.settings.weatherCity
        if let chosen {
            ChosenCityRow(city: chosen)
        }
        searchField(prompt: chosen == nil ? "Search for a city" : "Search for another city")
        if phase == .failed {
            HStack {
                Label("Couldn't reach Open-Meteo. Check your internet connection.", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Try Again") { search(after: .zero) }
            }
        } else if phase == .done, results.isEmpty {
            Text("No places match “\(searchText)”. Check the spelling, or try a larger city nearby.")
                .foregroundStyle(.secondary)
        }
        ForEach(Array(results.enumerated()), id: \.element) { index, city in
            CityResultRow(
                city: city,
                term: searchTerm,
                isChosen: chosen.map { Self.isSamePlace($0, city) } ?? false,
                isHighlighted: highlighted == index,
                showsReturnHint: isFocused && highlighted == index
            ) {
                pick(city)
            }
            .onHover { inside in
                if inside {
                    highlighted = index
                } else if highlighted == index {
                    highlighted = nil
                }
            }
        }
    }

    private func searchField(prompt: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("City", text: $query, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused($isFocused)
                .onSubmit(submit)
                .onKeyPress(.downArrow) { move(by: 1) }
                .onKeyPress(.upArrow) { move(by: -1) }
                .onKeyPress(.escape) {
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }
            if phase == .searching {
                ProgressView()
                    .controlSize(.small)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Clear the search")
                .accessibilityLabel("Clear")
            }
        }
        .onChange(of: query) { search() }
        .onAppear {
            // Turning off the current location leaves nothing to show until a city is chosen.
            if services.settings.weatherCity == nil { isFocused = true }
        }
    }

    private var searchText: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    /// The part of the query matched against names: "Portland" in "Portland, Oregon".
    private var searchTerm: String {
        searchText.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// `thenPick`: Return was pressed before the results came in, so take the best match.
    private func search(after delay: Duration = .milliseconds(300), thenPick: Bool = false) {
        searchTask?.cancel()
        let text = searchText
        guard text.count >= 2 else {
            results = []
            highlighted = nil
            phase = .idle
            return
        }
        phase = .searching
        searchTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            do {
                let found = try await OpenMeteoClient.searchCities(text)
                guard !Task.isCancelled else { return }
                results = found
                highlighted = found.isEmpty ? nil : 0
                phase = .done
                if thenPick, let first = found.first { pick(first) }
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                highlighted = nil
                phase = .failed
            }
        }
    }

    private func submit() {
        switch phase {
        case .searching:
            search(after: .zero, thenPick: true)
        case .done:
            if let city = results[safe: highlighted ?? 0] { pick(city) }
        case .idle, .failed:
            break
        }
    }

    private func move(by step: Int) -> KeyPress.Result {
        guard !results.isEmpty else { return .ignored }
        let current = highlighted ?? (step > 0 ? -1 : results.count)
        highlighted = min(max(current + step, 0), results.count - 1)
        return .handled
    }

    private func pick(_ city: SavedCity) {
        services.settings.weatherCity = city
        query = ""
        isFocused = false
        Task { await services.weather.refresh() }
    }

    /// Matched by name and spot rather than `==`, so cities saved before the country code
    /// was kept still match their search result, but not a landmark in them.
    private static func isSamePlace(_ a: SavedCity, _ b: SavedCity) -> Bool {
        a.name == b.name && abs(a.latitude - b.latitude) < 0.01 && abs(a.longitude - b.longitude) < 0.01
    }
}

/// The city the weather is for, with its conditions now.
private struct ChosenCityRow: View {
    @Environment(AppServices.self) private var services
    let city: SavedCity

    var body: some View {
        let weather = services.weather
        HStack(spacing: 10) {
            CityFlag(city: city, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(city.name)
                    .font(.body.weight(.medium))
                if !city.detail.isEmpty {
                    Text(city.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if weather.status == .loading {
                ProgressView()
                    .controlSize(.small)
            } else if weather.status == .failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Couldn't load the weather. Try Refresh Now.")
            } else if let snapshot = weather.snapshot, snapshot.locationName == city.name {
                HStack(spacing: 6) {
                    // Multicolor clouds are white, lost on a light row.
                    Image(systemName: snapshot.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Text(WeatherCard.degrees(snapshot.temperature))
                        .monospacedDigit()
                }
                .font(.title3)
                .help(snapshot.conditions)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(snapshot.conditions), \(WeatherCard.degrees(snapshot.temperature))")
            }
        }
        .padding(.vertical, 2)
    }
}

/// A search result: the place's flag, its name with the typed part in bold, and where it is.
private struct CityResultRow: View {
    let city: SavedCity
    let term: String
    let isChosen: Bool
    let isHighlighted: Bool
    let showsReturnHint: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CityFlag(city: city, size: 17)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                    if !city.detail.isEmpty {
                        Text(city.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isChosen {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                } else if showsReturnHint {
                    Image(systemName: "return")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.tint.opacity(isHighlighted ? 0.14 : 0))
                .padding(.horizontal, -6)
                .padding(.vertical, -3)
        }
        .accessibilityLabel([city.name, city.detail].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var name: AttributedString {
        var name = AttributedString(city.name)
        if !term.isEmpty, let match = name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
            name[match].font = .body.weight(.semibold)
        }
        return name
    }
}

/// The country's flag, or a pin for a city saved before the country was kept.
private struct CityFlag: View {
    let city: SavedCity
    let size: CGFloat

    var body: some View {
        Group {
            if let flag = city.flag {
                Text(flag)
                    .font(.system(size: size))
            } else {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: size * 0.9))
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 26)
        .accessibilityHidden(true)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
