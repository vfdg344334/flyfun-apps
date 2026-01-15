//
//  SearchFilterSidebar.swift
//  FlyFunEuroAIP
//
//  Modern SwiftUI sidebar with search and filters
//  Uses .searchable() modifier and Section(isExpanded:) for iOS 17+
//

import SwiftUI
import RZFlight

struct SearchFilterSidebar: View {
    @Environment(\.appState) private var state
    @State private var showAllFilters = false
    @State private var searchText = ""

    var body: some View {
        List {
            // Search Section - always visible at top
            Section {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Airport, route, or location...", text: $searchText)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .onSubmit {
                            performSearch()
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            state?.airports.searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Search")
            } footer: {
                Text("Enter ICAO code, city name, or route (e.g., EGLL-LFPG)")
                    .font(.caption2)
            }

            // Search Results (when searching) - show right after search
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
                Toggle("Border Crossing", isOn: pointOfEntryBinding)
                Toggle("AVGAS", isOn: hasAvgasBinding)
                Toggle("Jet-A", isOn: hasJetABinding)

                Picker("Hotel", selection: hotelBinding) {
                    Text("Any").tag(nil as String?)
                    Text("Nearby").tag("vicinity" as String?)
                    Text("At Airport").tag("atAirport" as String?)
                }

                Picker("Restaurant", selection: restaurantBinding) {
                    Text("Any").tag(nil as String?)
                    Text("Nearby").tag("vicinity" as String?)
                    Text("At Airport").tag("atAirport" as String?)
                }
            }

            // All Filters Section (expandable)
            Section("All Filters", isExpanded: $showAllFilters) {
                // Features
                Toggle("IFR Procedures", isOn: hasProceduresBinding)
                Toggle("Hard Runway", isOn: hasHardRunwayBinding)
                Toggle("Lighted Runway", isOn: hasLightedRunwayBinding)

                // Runway
                Picker("Min Runway", selection: minRunwayBinding) {
                    Text("Any").tag(nil as Int?)
                    Text("2000 ft").tag(2000 as Int?)
                    Text("3000 ft").tag(3000 as Int?)
                    Text("4000 ft").tag(4000 as Int?)
                    Text("5000 ft").tag(5000 as Int?)
                    Text("6000 ft").tag(6000 as Int?)
                    Text("8000 ft").tag(8000 as Int?)
                }

                // Approaches
                Toggle("Has ILS", isOn: hasILSBinding)
                Toggle("Has RNAV", isOn: hasRNAVBinding)
                Toggle("Precision Approach", isOn: hasPrecisionBinding)

                // Fees
                Picker("Max Landing Fee", selection: maxLandingFeeBinding) {
                    Text("Any").tag(nil as Double?)
                    Text("€20").tag(20.0 as Double?)
                    Text("€50").tag(50.0 as Double?)
                    Text("€100").tag(100.0 as Double?)
                    Text("€200").tag(200.0 as Double?)
                }

                // Size
                Toggle("Exclude Large Airports", isOn: excludeLargeBinding)

                // Country
                Picker("Country", selection: countryBinding) {
                    Text("Any").tag(nil as String?)
                    ForEach(availableCountries, id: \.self) { country in
                        Text(country).tag(country as String?)
                    }
                }
            }

            // Filter Actions
            if state?.airports.filters.hasActiveFilters == true {
                Section {
                    Button(role: .destructive) {
                        state?.airports.filters.reset()
                        Task {
                            try? await state?.airports.applyFilters()
                        }
                    } label: {
                        Label("Clear All Filters", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Explore")
        .onChange(of: searchText) { _, newValue in
            // Debounced search as user types
            if !newValue.isEmpty {
                performDebouncedSearch()
            } else {
                state?.airports.searchResults = []
            }
        }
    }

    // MARK: - Search

    @State private var searchTask: Task<Void, Never>?

    private func performSearch() {
        Task {
            try? await state?.airports.search(query: searchText)
        }
    }

    private func performDebouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            try? await state?.airports.search(query: searchText)
        }
    }

    // MARK: - Available Countries

    private var availableCountries: [String] {
        // Common European countries - could be made dynamic from data
        ["AT", "BE", "CH", "CZ", "DE", "DK", "ES", "FI", "FR", "GB", "GR", "HR", "HU", "IE", "IT", "NL", "NO", "PL", "PT", "SE", "SI", "SK"]
    }

    // MARK: - Filter Bindings

    private var pointOfEntryBinding: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.pointOfEntry ?? false },
            set: { newValue in
                state?.airports.filters.pointOfEntry = newValue ? true : nil
                applyFiltersDebounced()
            }
        )
    }

    private var hasAvgasBinding: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasAvgas ?? false },
            set: { newValue in
                state?.airports.filters.hasAvgas = newValue ? true : nil
                applyFiltersDebounced()
            }
        )
    }

    private var hasJetABinding: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasJetA ?? false },
            set: { newValue in
                state?.airports.filters.hasJetA = newValue ? true : nil
                applyFiltersDebounced()
            }
        )
    }

    private var hotelBinding: Binding<String?> {
        Binding(
            get: { state?.airports.filters.hotel },
            set: { newValue in
                state?.airports.filters.hotel = newValue
                applyFiltersDebounced()
            }
        )
    }

    private var restaurantBinding: Binding<String?> {
        Binding(
            get: { state?.airports.filters.restaurant },
            set: { newValue in
                state?.airports.filters.restaurant = newValue
                applyFiltersDebounced()
            }
        )
    }

    private var hasProceduresBinding: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasProcedures ?? false },
            set: { newValue in
                state?.airports.filters.hasProcedures = newValue ? true : nil
                applyFiltersDebounced()
            }
        )
    }

    private var hasHardRunwayBinding: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasHardRunway ?? false },
            set: { newValue in
                state?.airports.filters.hasHardRunway = newValue ? true : nil
                applyFiltersDebounced()
            }
        )
    }

    private var hasLightedRunwayBinding: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasLightedRunway ?? false },
            set: { newValue in
                state?.airports.filters.hasLightedRunway = newValue ? true : nil
                applyFiltersDebounced()
            }
        )
    }

    private var minRunwayBinding: Binding<Int?> {
        Binding(
            get: { state?.airports.filters.minRunwayLengthFt },
            set: { newValue in
                state?.airports.filters.minRunwayLengthFt = newValue
                applyFiltersDebounced()
            }
        )
    }

    private var hasILSBinding: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasILS ?? false },
            set: { newValue in
                state?.airports.filters.hasILS = newValue ? true : nil
                applyFiltersDebounced()
            }
        )
    }

    private var hasRNAVBinding: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasRNAV ?? false },
            set: { newValue in
                state?.airports.filters.hasRNAV = newValue ? true : nil
                applyFiltersDebounced()
            }
        )
    }

    private var hasPrecisionBinding: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasPrecisionApproach ?? false },
            set: { newValue in
                state?.airports.filters.hasPrecisionApproach = newValue ? true : nil
                applyFiltersDebounced()
            }
        )
    }

    private var maxLandingFeeBinding: Binding<Double?> {
        Binding(
            get: { state?.airports.filters.maxLandingFee },
            set: { newValue in
                state?.airports.filters.maxLandingFee = newValue
                applyFiltersDebounced()
            }
        )
    }

    private var excludeLargeBinding: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.excludeLargeAirports ?? false },
            set: { newValue in
                state?.airports.filters.excludeLargeAirports = newValue ? true : nil
                applyFiltersDebounced()
            }
        )
    }

    private var countryBinding: Binding<String?> {
        Binding(
            get: { state?.airports.filters.country },
            set: { newValue in
                state?.airports.filters.country = newValue
                applyFiltersDebounced()
            }
        )
    }

    // MARK: - Apply Filters

    private func applyFiltersDebounced() {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            try? await state?.airports.applyFilters()
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SearchFilterSidebar()
    }
}
