//
//  ContentView.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 26/10/2025.
//

import SwiftUI
import MapKit
import RZFlight

struct ContentView: View {
    @Environment(\.appState) private var state
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Map layer
            mapLayer
                .ignoresSafeArea()
            
            // Adaptive overlay layout
            GeometryReader { proxy in
                if isRegular(proxy) {
                    RegularLayoutNew(proxy: proxy)
                } else {
                    CompactLayoutNew()
                }
            }
            
            // Error banner
            if let error = state?.system.error {
                errorBanner(error)
            }
            
            // Offline banner
            if state?.system.connectivityMode == .offline && state?.settings.showOfflineBanner == true {
                offlineBanner
            }
        }
        .animation(.snappy, value: state?.navigation.showingFilters)
        .animation(.snappy, value: state?.navigation.showingChat)
    }
    
    // MARK: - Map Layer
    
    private var mapLayer: some View {
        Map(position: mapPosition) {
            if let airports = state?.airports.airports {
                ForEach(airports, id: \.icao) { airport in
                    Annotation(airport.icao, coordinate: airport.coord) {
                        AirportMarkerView(
                            airport: airport,
                            legendMode: state?.airports.legendMode ?? .airportType,
                            isSelected: airport.icao == state?.airports.selectedAirport?.icao
                        )
                        .onTapGesture {
                            state?.airports.select(airport)
                        }
                    }
                }
            }
            
            // Route polyline
            if let route = state?.airports.activeRoute {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(.blue, lineWidth: 3)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .onMapCameraChange(frequency: .onEnd) { context in
            state?.airports.onRegionChange(context.region)
        }
    }
    
    // MARK: - Computed Properties
    
    private var mapPosition: Binding<MapCameraPosition> {
        Binding(
            get: { state?.airports.mapPosition ?? .automatic },
            set: { state?.airports.mapPosition = $0 }
        )
    }
    
    // MARK: - Helper Views
    
    private func errorBanner(_ error: AppError) -> some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error.localizedDescription)
                    .font(.caption)
                Spacer()
                Button {
                    state?.system.clearError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding()
            
            Spacer()
        }
    }
    
    private var offlineBanner: some View {
        VStack {
            HStack {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
                Text("Offline Mode")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            
            Spacer()
        }
    }
    
    // MARK: - Helpers
    
    private func isRegular(_ proxy: GeometryProxy) -> Bool {
        sizeClass == .regular || proxy.size.width >= 700
    }
}

// MARK: - Airport Marker View

struct AirportMarkerView: View {
    let airport: RZFlight.Airport
    let legendMode: LegendMode
    let isSelected: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(markerColor.opacity(0.9))
                .frame(width: isSelected ? 32 : 24, height: isSelected ? 32 : 24)
            
            if isSelected {
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 32, height: 32)
            }
            
            Text(airport.icao.prefix(4))
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
    }
    
    private var markerColor: Color {
        switch legendMode {
        case .airportType:
            return airportTypeColor
        case .runwayLength:
            return runwayLengthColor
        case .procedures:
            return airport.hasInstrumentProcedures ? .blue : .gray
        case .country:
            return .blue  // Could use country-specific colors
        }
    }
    
    private var airportTypeColor: Color {
        // Simple color based on whether airport has procedures
        if airport.hasInstrumentProcedures {
            return .blue
        } else {
            return .orange
        }
    }
    
    private var runwayLengthColor: Color {
        // Use runways from airport - get max runway length
        let maxLength = airport.maxRunwayLength
        if maxLength >= 8000 { return .green }
        if maxLength >= 5000 { return .blue }
        if maxLength >= 3000 { return .orange }
        return .red
    }
}

// MARK: - RZFlight Airport Extensions

extension RZFlight.Airport {
    var hasInstrumentProcedures: Bool {
        !procedures.isEmpty
    }
    
    var maxRunwayLength: Int {
        // TODO: Access actual runway length from RZFlight
        // For now, return 0 which will show as "short runway" color
        // Need to check RZFlight API for correct property access
        0
    }
}

// MARK: - Placeholder Layouts (will be updated)

struct RegularLayoutNew: View {
    let proxy: GeometryProxy
    @Environment(\.appState) private var state
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack {
                SearchBarNew()
                
                if state?.navigation.showingFilters == true {
                    FilterPanelNew()
                }
                
                SearchResultsListNew()
                
                Spacer()
            }
            .frame(width: min(350, proxy.size.width * 0.3))
            .background(.ultraThinMaterial)
            
            Spacer()
        }
    }
}

struct CompactLayoutNew: View {
    @Environment(\.appState) private var state
    
    var body: some View {
        VStack {
            SearchBarNew()
                .padding()
            
            Spacer()
        }
    }
}

// MARK: - Placeholder Components (will be updated)

struct SearchBarNew: View {
    @Environment(\.appState) private var state
    @State private var searchText = ""
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search airports...", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit {
                    Task {
                        try? await state?.airports.search(query: searchText)
                    }
                }
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    state?.airports.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            Button {
                state?.navigation.toggleFilters()
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(state?.airports.filters.hasActiveFilters == true ? .blue : .secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct FilterPanelNew: View {
    @Environment(\.appState) private var state
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Filters")
                .font(.headline)
            
            Toggle("IFR Procedures", isOn: Binding(
                get: { state?.airports.filters.hasProcedures ?? false },
                set: { state?.airports.filters.hasProcedures = $0 ? true : nil }
            ))
            
            Toggle("Border Crossing", isOn: Binding(
                get: { state?.airports.filters.pointOfEntry ?? false },
                set: { state?.airports.filters.pointOfEntry = $0 ? true : nil }
            ))
            
            Toggle("Hard Runway", isOn: Binding(
                get: { state?.airports.filters.hasHardRunway ?? false },
                set: { state?.airports.filters.hasHardRunway = $0 ? true : nil }
            ))
            
            HStack {
                Button("Reset") {
                    state?.airports.resetFilters()
                }
                .buttonStyle(.bordered)
                
                Button("Apply") {
                    Task {
                        try? await state?.airports.applyFilters()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SearchResultsListNew: View {
    @Environment(\.appState) private var state
    
    var body: some View {
        List {
            if let results = state?.airports.searchResults, !results.isEmpty {
                ForEach(results, id: \.icao) { airport in
                    Button {
                        state?.airports.select(airport)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(airport.icao)
                                .font(.headline)
                            Text(airport.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if state?.airports.isSearching == true {
                ProgressView()
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
