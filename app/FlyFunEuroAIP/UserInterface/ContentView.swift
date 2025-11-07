//
//  ContentView.swift
//  flyguneuroaip
//
//  Created by Brice Rosenzweig on 26/10/2025.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var viewModel = AirportMapViewModel()
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Map layer
            mapLayer
                .ignoresSafeArea()
            
            // Adaptive overlay layout
            GeometryReader { proxy in
                if isRegular(proxy) {
                    RegularLayout(viewModel: viewModel, proxy: proxy)
                } else {
                    CompactLayout(viewModel: viewModel)
                }
            }
        }
        .animation(.snappy, value: viewModel.isSearchExpanded)
        .animation(.snappy, value: viewModel.isFilterExpanded)
    }
    
    // MARK: - Map Layer
    private var mapLayer: some View {
        Map(position: $viewModel.mapPosition) {
            ForEach(viewModel.filteredAirports) { airport in
                Annotation(airport.icao, coordinate: airport.coordinate) {
                    ZStack {
                        Circle().fill(.blue.opacity(0.9)).frame(width: 24, height: 24)
                        Text(airport.icao)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .padding(4)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
    }
    
    // MARK: - Helpers
    private func isRegular(_ proxy: GeometryProxy) -> Bool {
        sizeClass == .regular || proxy.size.width >= 700
    }
}

#Preview {
    ContentView()
}
