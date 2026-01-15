//
//  ContentView.swift
//  FlyFunEuroAIP
//
//  Modern SwiftUI root view using NavigationSplitView (iOS 17+)
//  - Single view for all device sizes (iPad/Mac/iPhone)
//  - .searchable() for native search
//  - .inspector() for airport details (automatic adaptation)
//

import SwiftUI
import MapKit
import RZFlight

struct ContentView: View {
    @Environment(\.appState) private var state
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var searchText = ""
    @State private var showingInspector = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // SIDEBAR: Search + Filters
            SearchFilterSidebar()
        } detail: {
            // DETAIL: Map with Inspector
            MapDetailView(showingInspector: $showingInspector)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search airports...")
        .onSubmit(of: .search) {
            performSearch()
        }
        .onChange(of: searchText) { _, newValue in
            // Debounced search as user types
            if !newValue.isEmpty {
                performDebouncedSearch()
            } else {
                // Clear search results when search is cleared
                state?.airports.searchResults = []
            }
        }
        .onChange(of: state?.airports.selectedAirport) { _, newValue in
            // Show inspector when airport is selected
            showingInspector = (newValue != nil)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - Search

    private func performSearch() {
        Task {
            try? await state?.airports.search(query: searchText)
        }
    }

    @State private var searchTask: Task<Void, Never>?

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

#Preview("iPad") {
    ContentView()
        .environment(\.horizontalSizeClass, .regular)
}

#Preview("iPhone") {
    ContentView()
        .environment(\.horizontalSizeClass, .compact)
}
