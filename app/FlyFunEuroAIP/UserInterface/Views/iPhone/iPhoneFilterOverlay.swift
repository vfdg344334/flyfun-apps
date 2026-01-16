//
//  iPhoneFilterOverlay.swift
//  FlyFunEuroAIP
//
//  Filter panel overlay for iPhone. Appears below search bar.
//  Uses shared FilterBindings for filter controls.
//

import SwiftUI

struct iPhoneFilterOverlay: View {
    @Environment(\.appState) private var state
    @Binding var isPresented: Bool
    @State private var showAllFilters = false

    private var filters: FilterBindings { FilterBindings(state: state) }

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
                            if filters.hasActiveFilters {
                                Button(role: .destructive) {
                                    filters.clearAll()
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

            Toggle("Border Crossing", isOn: filters.pointOfEntry)
            Toggle("AVGAS", isOn: filters.hasAvgas)
            Toggle("Jet-A", isOn: filters.hasJetA)

            HStack {
                Text("Hotel")
                Spacer()
                Picker("", selection: filters.hotel) {
                    Text("Any").tag(nil as String?)
                    Text("Nearby").tag("vicinity" as String?)
                    Text("At Airport").tag("atAirport" as String?)
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text("Restaurant")
                Spacer()
                Picker("", selection: filters.restaurant) {
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
                    Toggle("IFR Procedures", isOn: filters.hasProcedures)
                    Toggle("Hard Runway", isOn: filters.hasHardRunway)
                    Toggle("Lighted Runway", isOn: filters.hasLightedRunway)

                    HStack {
                        Text("Min Runway")
                        Spacer()
                        Picker("", selection: filters.minRunwayLengthFt) {
                            Text("Any").tag(nil as Int?)
                            Text("2000 ft").tag(2000 as Int?)
                            Text("3000 ft").tag(3000 as Int?)
                            Text("4000 ft").tag(4000 as Int?)
                            Text("5000 ft").tag(5000 as Int?)
                        }
                        .pickerStyle(.menu)
                    }

                    Toggle("Has ILS", isOn: filters.hasILS)
                    Toggle("Has RNAV", isOn: filters.hasRNAV)

                    HStack {
                        Text("Country")
                        Spacer()
                        Picker("", selection: filters.country) {
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
}

// MARK: - Preview

#Preview {
    iPhoneFilterOverlay(isPresented: .constant(true))
}
