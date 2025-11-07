//
//  FilterPanel.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 02/11/2025.
//

import SwiftUI

struct FilterPanel: View {
    @ObservedObject var viewModel: AirportMapViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.snappy) {
                        viewModel.isFilterExpanded = false
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
            }
            
            Toggle("International only", isOn: $viewModel.showInternationalOnly)
            
            VStack(alignment: .leading) {
                Text("Minimum runway length")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Slider(value: $viewModel.minRunwayLength, in: 0...4000, step: 100)
                    Text("\(Int(viewModel.minRunwayLength)) m")
                        .monospacedDigit()
                        .frame(width: 80, alignment: .trailing)
                }
            }
            
            HStack {
                Button("Reset") {
                    viewModel.resetFilters()
                }
                Spacer()
                Button("Apply") {
                    withAnimation(.snappy) {
                        viewModel.isFilterExpanded = false
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }
}

#Preview {
    FilterPanel(viewModel: AirportMapViewModel())
        .padding()
        .background(.regularMaterial)
}

