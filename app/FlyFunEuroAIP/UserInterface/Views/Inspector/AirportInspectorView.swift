//
//  AirportInspectorView.swift
//  FlyFunEuroAIP
//
//  Modern SwiftUI inspector view for airport details
//  Used with .inspector() modifier - shows as trailing sidebar on iPad, sheet on iPhone
//

import SwiftUI
import RZFlight

struct AirportInspectorView: View {
    @Environment(\.appState) private var state

    var body: some View {
        if let airport = state?.airports.selectedAirport {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Tab", selection: selectedTabBinding) {
                    ForEach(NavigationDomain.BottomTab.allCases, id: \.self) { tab in
                        Label(tab.displayName, systemImage: tab.systemImage)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Tab content with swipe navigation
                TabView(selection: selectedTabBinding) {
                    AirportInfoTab(airport: airport)
                        .tag(NavigationDomain.BottomTab.airportInfo)

                    AIPTab(airport: airport)
                        .tag(NavigationDomain.BottomTab.aip)

                    RulesTab(airport: airport)
                        .tag(NavigationDomain.BottomTab.rules)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(airport.icao)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        state?.airports.clearSelection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No Airport Selected",
                systemImage: "airplane.circle",
                description: Text("Tap an airport on the map to see details")
            )
        }
    }

    private var selectedTabBinding: Binding<NavigationDomain.BottomTab> {
        Binding(
            get: { state?.navigation.selectedBottomTab ?? .airportInfo },
            set: { state?.navigation.selectBottomTab($0) }
        )
    }
}

// MARK: - Preview

#Preview("With Airport") {
    NavigationStack {
        AirportInspectorView()
    }
}

#Preview("Empty") {
    NavigationStack {
        AirportInspectorView()
    }
}
