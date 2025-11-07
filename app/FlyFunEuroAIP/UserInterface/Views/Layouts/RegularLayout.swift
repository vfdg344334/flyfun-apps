//
//  RegularLayout.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 02/11/2025.
//

import SwiftUI

struct RegularLayout: View {
    @ObservedObject var viewModel: AirportMapViewModel
    let proxy: GeometryProxy
    
    var body: some View {
        HStack(spacing: 12) {
            // Left: search + results side panel
            sidePanel
                .frame(width: max(320, proxy.size.width * 0.28))
                .transition(.move(edge: .leading).combined(with: .opacity))
            
            Spacer(minLength: 0)
            
            // Right: filter button + expandable panel
            VStack(alignment: .trailing, spacing: 12) {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.snappy) {
                            viewModel.isFilterExpanded.toggle()
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle.fill")
                            .labelStyle(.iconOnly)
                            .imageScale(.large)
                            .foregroundStyle(.tint)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Filter")
                }
                
                if viewModel.isFilterExpanded {
                    FilterPanel(viewModel: viewModel)
                        .frame(width: 360)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(radius: 8)
                }
            }
            .frame(maxWidth: 380)
        }
        .padding(16)
    }
    
    // MARK: - Side Panel
    private var sidePanel: some View {
        VStack(spacing: 12) {
            SearchBar(viewModel: viewModel)
            if viewModel.isSearchExpanded || !viewModel.searchText.isEmpty {
                SearchResultsList(results: viewModel.filteredAirports) { airport in
                    viewModel.focus(on: airport)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .frame(maxHeight: 360)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 8)
    }
}

#Preview {
    GeometryReader { proxy in
        RegularLayout(viewModel: AirportMapViewModel.sample(), proxy: proxy)
    }
}

