//
//  SearchFieldCompact.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 02/11/2025.
//

import SwiftUI

struct SearchFieldCompact: View {
    @ObservedObject var viewModel: AirportMapViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .onTapGesture {
                    withAnimation(.snappy) {
                        viewModel.isSearchExpanded = true
                    }
                }
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.thickMaterial, in: Capsule())
    }
}

#Preview {
    SearchFieldCompact(viewModel: AirportMapViewModel())
        .padding()
}

