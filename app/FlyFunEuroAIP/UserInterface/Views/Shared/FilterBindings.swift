//
//  FilterBindings.swift
//  FlyFunEuroAIP
//
//  Shared filter bindings with auto-apply debouncing.
//  Eliminates duplication between iPad sidebar and iPhone overlay.
//

import SwiftUI

/// Provides SwiftUI bindings for all filter properties with automatic debounced apply.
///
/// Usage:
/// ```swift
/// @Environment(\.appState) private var state
/// private var filters: FilterBindings { FilterBindings(state: state) }
///
/// var body: some View {
///     Toggle("Border Crossing", isOn: filters.pointOfEntry)
/// }
/// ```
@MainActor
struct FilterBindings {
    private let state: AppState?

    init(state: AppState?) {
        self.state = state
    }

    // MARK: - Quick Filters

    var pointOfEntry: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.pointOfEntry ?? false },
            set: { [state] newValue in
                state?.airports.filters.pointOfEntry = newValue ? true : nil
                applyFiltersDebounced(state: state)
            }
        )
    }

    var hasAvgas: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasAvgas ?? false },
            set: { [state] newValue in
                state?.airports.filters.hasAvgas = newValue ? true : nil
                applyFiltersDebounced(state: state)
            }
        )
    }

    var hasJetA: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasJetA ?? false },
            set: { [state] newValue in
                state?.airports.filters.hasJetA = newValue ? true : nil
                applyFiltersDebounced(state: state)
            }
        )
    }

    var hotel: Binding<String?> {
        Binding(
            get: { state?.airports.filters.hotel },
            set: { [state] newValue in
                state?.airports.filters.hotel = newValue
                applyFiltersDebounced(state: state)
            }
        )
    }

    var restaurant: Binding<String?> {
        Binding(
            get: { state?.airports.filters.restaurant },
            set: { [state] newValue in
                state?.airports.filters.restaurant = newValue
                applyFiltersDebounced(state: state)
            }
        )
    }

    // MARK: - Runway Filters

    var hasProcedures: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasProcedures ?? false },
            set: { [state] newValue in
                state?.airports.filters.hasProcedures = newValue ? true : nil
                applyFiltersDebounced(state: state)
            }
        )
    }

    var hasHardRunway: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasHardRunway ?? false },
            set: { [state] newValue in
                state?.airports.filters.hasHardRunway = newValue ? true : nil
                applyFiltersDebounced(state: state)
            }
        )
    }

    var hasLightedRunway: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasLightedRunway ?? false },
            set: { [state] newValue in
                state?.airports.filters.hasLightedRunway = newValue ? true : nil
                applyFiltersDebounced(state: state)
            }
        )
    }

    var minRunwayLengthFt: Binding<Int?> {
        Binding(
            get: { state?.airports.filters.minRunwayLengthFt },
            set: { [state] newValue in
                state?.airports.filters.minRunwayLengthFt = newValue
                applyFiltersDebounced(state: state)
            }
        )
    }

    // MARK: - Approach Filters

    var hasILS: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasILS ?? false },
            set: { [state] newValue in
                state?.airports.filters.hasILS = newValue ? true : nil
                applyFiltersDebounced(state: state)
            }
        )
    }

    var hasRNAV: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasRNAV ?? false },
            set: { [state] newValue in
                state?.airports.filters.hasRNAV = newValue ? true : nil
                applyFiltersDebounced(state: state)
            }
        )
    }

    var hasPrecisionApproach: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.hasPrecisionApproach ?? false },
            set: { [state] newValue in
                state?.airports.filters.hasPrecisionApproach = newValue ? true : nil
                applyFiltersDebounced(state: state)
            }
        )
    }

    // MARK: - Other Filters

    var maxLandingFee: Binding<Double?> {
        Binding(
            get: { state?.airports.filters.maxLandingFee },
            set: { [state] newValue in
                state?.airports.filters.maxLandingFee = newValue
                applyFiltersDebounced(state: state)
            }
        )
    }

    var excludeLargeAirports: Binding<Bool> {
        Binding(
            get: { state?.airports.filters.excludeLargeAirports ?? false },
            set: { [state] newValue in
                state?.airports.filters.excludeLargeAirports = newValue ? true : nil
                applyFiltersDebounced(state: state)
            }
        )
    }

    var country: Binding<String?> {
        Binding(
            get: { state?.airports.filters.country },
            set: { [state] newValue in
                state?.airports.filters.country = newValue
                applyFiltersDebounced(state: state)
            }
        )
    }

    // MARK: - State Accessors

    var hasActiveFilters: Bool {
        state?.airports.filters.hasActiveFilters ?? false
    }

    func clearAll() {
        state?.airports.filters.reset()
        Task {
            try? await state?.airports.applyFilters()
        }
    }
}

// MARK: - Debounced Apply

/// Shared debounced filter application
private var filterApplyTask: Task<Void, Never>?

@MainActor
private func applyFiltersDebounced(state: AppState?) {
    filterApplyTask?.cancel()
    filterApplyTask = Task {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        try? await state?.airports.applyFilters()
    }
}

// MARK: - Available Countries

/// Common European countries for country filter picker
let availableCountries: [String] = [
    "AT", "BE", "CH", "CZ", "DE", "DK", "ES", "FI", "FR", "GB",
    "GR", "HR", "HU", "IE", "IT", "NL", "NO", "PL", "PT", "SE", "SI", "SK"
]
