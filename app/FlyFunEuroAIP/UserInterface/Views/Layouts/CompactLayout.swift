//
//  CompactLayout.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 02/11/2025.
//

import SwiftUI

struct CompactLayout: View {
    @ObservedObject var viewModel: AirportMapViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Spacer()
                // Search + filter button row (compact)
                SearchFieldCompact(viewModel: viewModel)
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
            
            if viewModel.isSearchExpanded || !viewModel.searchText.isEmpty {
                SearchResultsList(results: viewModel.filteredAirports) { airport in
                    viewModel.focus(on: airport)
                }
                .frame(maxHeight: 300)
                .transition(.move(edge: .top).combined(with: .opacity))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(radius: 6)
            }
            
            Spacer()
            
            // Single bottom-anchored filter panel when expanded
            if viewModel.isFilterExpanded {
                FilterPanel(viewModel: viewModel)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(radius: 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(16)
        .transition(.opacity)
    }
}

#Preview {
    CompactLayout(viewModel: AirportMapViewModel())
}

