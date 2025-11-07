//
//  SearchResultsList.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 02/11/2025.
//

import SwiftUI

struct SearchResultsList: View {
    let results: [Airport]
    let onSelect: (Airport) -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(results) { airport in
                    Button {
                        onSelect(airport)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(airport.icao)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 48, alignment: .leading)
                            Text(airport.name)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
    }
}

#Preview {
    SearchResultsList(
        results: [
        ],
        onSelect: { _ in }
    )
    .frame(height: 200)
    .padding()
}

