//
//  IPhoneFilterOverlay.swift
//  FlyFunEuroAIP
//
//  Filter panel overlay for iPhone. Appears below search bar.
//

import SwiftUI

struct IPhoneFilterOverlay: View {
    @Environment(\.appState) private var state
    @Binding var isPresented: Bool
    @State private var showAllFilters = false

    var body: some View {
        ZStack {
            // Dimmed background - tap to dismiss
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3)) {
                        isPresented = false
                    }
                }

            VStack {
                // Spacer for search bar area
                Spacer().frame(height: 70)

                // Filter panel
                VStack(spacing: 0) {
                    // Drag handle
                    Capsule()
                        .fill(.secondary.opacity(0.5))
                        .frame(width: 40, height: 4)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Quick Filters
                            quickFiltersSection

                            Divider()

                            // All Filters (expandable)
                            allFiltersSection

                            // Clear filters button
                            if state?.airports.filters.hasActiveFilters == true {
                                Button(role: .destructive) {
                                    state?.airports.filters.reset()
                                    Task {
                                        try? await state?.airports.applyFilters()
                                    }
                                } label: {
                                    Label("Clear All Filters", systemImage: "xmark.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .padding(.top, 8)
                            }
                        }
                        .padding()
                    }
                }
                .frame(maxHeight: 450)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()
            }
        }
    }

    // MARK: - Quick Filters Section

    private var quickFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Filters")
                .font(.headline)

            Toggle("Border Crossing", isOn: pointOfEntryBinding)
            Toggle("AVGAS", isOn: hasAvgasBinding)
            Toggle("Jet-A", isOn: hasJetABinding)

            HStack {
                Text("Hotel")
                Spacer()
                Picker("", selection: hotelBinding) {
                    Text("Any").tag(nil as String?)
                    Text("Nearby").tag("vicinity" as String?)
                    Text("At Airport").tag("atAirport" as String?)
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text("Restaurant")
                Spacer()
                Picker("", selection: restaurantBinding) {
                    Text("Any").tag(nil as String?)
                    Text("Nearby").tag("vicinity" as String?)
                    Text("At Airport").tag("atAirport" as String?)
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - All Filters Section

    private var allFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation { showAllFilters.toggle() }
            } label: {
                HStack {
                    Text("All Filters")
                        .font(.headline)
                    Spacer()
                    Image(systemName: showAllFilters ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showAllFilters {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("IFR Procedures", isOn: hasProceduresBinding)
                    Toggle("Hard Runway", isOn: hasHardRunwayBinding)
                    Toggle("Lighted Runway", isOn: hasLightedRunwayBinding)

                    HStack {
                        Text("Min Runway")
                        Spacer()
                        Picker("", selection: minRunwayBinding) {
                            Text("Any").tag(nil as Int?)
                            Text("2000 ft").tag(2000 as Int?)
                            Text("3000 ft").tag(3000 as Int?)
                            Text("4000 ft").tag(4000 as Int?)
                            Text("5000 ft").tag(5000 as Int?)
                        }
                        .pickerStyle(.menu)
                    }

                    Toggle("Has ILS", isOn: hasILSBinding)
                    Toggle("Has RNAV", isOn: hasRNAVBinding)

                    HStack {
                        Text("Country")
                        Spacer()
                        Picker("", selection: countryBinding) {
                            Text("Any").tag(nil as String?)
                            ForEach(availableCountries, id: \.self) { country in
                                Text(country).tag(country as String?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                .padding(.leading, 8)
            }
        }
    }

    // MARK: - Available Countries

    private var availableCountries: [String] {
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
    IPhoneFilterOverlay(isPresented: .constant(true))
}
