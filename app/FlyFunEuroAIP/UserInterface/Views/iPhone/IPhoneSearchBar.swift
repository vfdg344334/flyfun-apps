//
//  IPhoneSearchBar.swift
//  FlyFunEuroAIP
//
//  Top search bar for iPhone with embedded filter button.
//

import SwiftUI

struct IPhoneSearchBar: View {
    @Environment(\.appState) private var state
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @Binding var showingFilters: Bool

    private var hasActiveFilters: Bool {
        state?.airports.filters.hasActiveFilters ?? false
    }

    var body: some View {
        HStack(spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Airport, route, or location...", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onSubmit {
                        performSearch()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        state?.airports.searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Filter button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showingFilters.toggle()
                }
            } label: {
                Image(systemName: showingFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                    .font(.title2)
                    .foregroundStyle(hasActiveFilters ? .blue : .primary)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                performDebouncedSearch()
            } else {
                state?.airports.searchResults = []
            }
        }
    }

    // MARK: - Search

    private func performSearch() {
        Task {
            try? await state?.airports.search(query: searchText)
        }
    }

    private func performDebouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            try? await state?.airports.search(query: searchText)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        VStack {
            IPhoneSearchBar(showingFilters: .constant(false))
            Spacer()
        }
    }
}
