//
//  SearchFilterSidebar.swift
//  FlyFunEuroAIP
//
//  iPad sidebar with search and filters.
//  Uses shared FilterBindings for filter controls.
//

import SwiftUI
import RZFlight

struct SearchFilterSidebar: View {
    @Environment(\.appState) private var state
    @State private var showAllFilters = false
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?

    private var filters: FilterBindings { FilterBindings(state: state) }

    var body: some View {
        List {
            // Search Section
            Section {
                SearchTextField(
                    text: $searchText,
                    onClear: { state?.airports.searchResults = [] }
                )
                .padding(.vertical, 4)
            } header: {
                Text("Search")
            } footer: {
                Text("Enter ICAO code, city name, or route (e.g., EGLL-LFPG)")
                    .font(.caption2)
            }

            // Search Results
            if let results = state?.airports.searchResults, !results.isEmpty {
                Section("Results (\(results.count))") {
                    ForEach(results, id: \.icao) { airport in
                        AirportSearchRow(airport: airport) {
                            state?.airports.select(airport)
                        }
                    }
                }
            }

            // Quick Filters Section
            Section("Quick Filters") {
                Toggle("Border Crossing", isOn: filters.pointOfEntry)
                Toggle("AVGAS", isOn: filters.hasAvgas)
                Toggle("Jet-A", isOn: filters.hasJetA)

                Picker("Hotel", selection: filters.hotel) {
                    Text("Any").tag(nil as String?)
                    Text("Nearby").tag("vicinity" as String?)
                    Text("At Airport").tag("atAirport" as String?)
                }

                Picker("Restaurant", selection: filters.restaurant) {
                    Text("Any").tag(nil as String?)
                    Text("Nearby").tag("vicinity" as String?)
                    Text("At Airport").tag("atAirport" as String?)
                }
            }

            // All Filters Section (expandable)
            Section("All Filters", isExpanded: $showAllFilters) {
                Toggle("IFR Procedures", isOn: filters.hasProcedures)
                Toggle("Hard Runway", isOn: filters.hasHardRunway)
                Toggle("Lighted Runway", isOn: filters.hasLightedRunway)

                Picker("Min Runway", selection: filters.minRunwayLengthFt) {
                    Text("Any").tag(nil as Int?)
                    Text("2000 ft").tag(2000 as Int?)
                    Text("3000 ft").tag(3000 as Int?)
                    Text("4000 ft").tag(4000 as Int?)
                    Text("5000 ft").tag(5000 as Int?)
                    Text("6000 ft").tag(6000 as Int?)
                    Text("8000 ft").tag(8000 as Int?)
                }

                Toggle("Has ILS", isOn: filters.hasILS)
                Toggle("Has RNAV", isOn: filters.hasRNAV)
                Toggle("Precision Approach", isOn: filters.hasPrecisionApproach)

                Picker("Max Landing Fee", selection: filters.maxLandingFee) {
                    Text("Any").tag(nil as Double?)
                    Text("€20").tag(20.0 as Double?)
                    Text("€50").tag(50.0 as Double?)
                    Text("€100").tag(100.0 as Double?)
                    Text("€200").tag(200.0 as Double?)
                }

                Toggle("Exclude Large Airports", isOn: filters.excludeLargeAirports)

                Picker("Country", selection: filters.country) {
                    Text("Any").tag(nil as String?)
                    ForEach(availableCountries, id: \.self) { country in
                        Text(country).tag(country as String?)
                    }
                }
            }

            // Clear Filters
            if filters.hasActiveFilters {
                Section {
                    Button(role: .destructive) {
                        filters.clearAll()
                    } label: {
                        Label("Clear All Filters", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Explore")
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                performDebouncedSearch()
            } else {
                state?.airports.searchResults = []
            }
        }
    }

    // MARK: - Search

    private func performDebouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            try? await state?.airports.search(query: searchText)
        }
    }
}

// MARK: - Shared Search TextField

/// Reusable search text field with clear button
struct SearchTextField: View {
    @Binding var text: String
    var placeholder: String = "Airport, route, or location..."
    var onSubmit: (() -> Void)?
    var onClear: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SearchFilterSidebar()
    }
}
