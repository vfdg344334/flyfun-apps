//
//  NotamListView.swift
//  FlyFunBrief
//
//  Displays the list of NOTAMs with grouping and filtering.
//

import SwiftUI
import RZFlight

/// Main NOTAM list view with grouping support
struct NotamListView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        Group {
            if let notams = appState?.notams, notams.allNotams.isEmpty {
                emptyState
            } else {
                notamList
            }
        }
        .searchable(text: searchBinding, prompt: "Search NOTAMs")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No NOTAMs", systemImage: "doc.text")
        } description: {
            Text("Import a briefing to see NOTAMs.")
        }
    }

    // MARK: - NOTAM List

    @ViewBuilder
    private var notamList: some View {
        let grouping = appState?.notams.grouping ?? .airport
        let filteredNotams = appState?.notams.filteredNotams ?? []

        if filteredNotams.isEmpty {
            ContentUnavailableView.search
        } else {
            List(selection: selectedNotamBinding) {
                switch grouping {
                case .none:
                    flatList(filteredNotams)
                case .airport:
                    airportGroupedList
                case .category:
                    categoryGroupedList
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Flat List

    @ViewBuilder
    private func flatList(_ notams: [Notam]) -> some View {
        ForEach(notams, id: \.id) { notam in
            NotamRowView(notam: notam)
                .tag(notam.id)
        }
    }

    // MARK: - Airport Grouped

    @ViewBuilder
    private var airportGroupedList: some View {
        let grouped = appState?.notams.notamsGroupedByAirport ?? [:]
        let sortedKeys = grouped.keys.sorted()

        ForEach(sortedKeys, id: \.self) { airport in
            Section {
                if let notams = grouped[airport] {
                    ForEach(notams, id: \.id) { notam in
                        NotamRowView(notam: notam)
                            .tag(notam.id)
                    }
                }
            } header: {
                NotamSectionHeader(title: airport, count: grouped[airport]?.count ?? 0)
            }
        }
    }

    // MARK: - Category Grouped

    @ViewBuilder
    private var categoryGroupedList: some View {
        let grouped = appState?.notams.notamsGroupedByCategory ?? [:]
        let sortedKeys = grouped.keys.sorted { $0.displayName < $1.displayName }

        ForEach(sortedKeys, id: \.self) { category in
            Section {
                if let notams = grouped[category] {
                    ForEach(notams, id: \.id) { notam in
                        NotamRowView(notam: notam)
                            .tag(notam.id)
                    }
                }
            } header: {
                NotamSectionHeader(title: category.displayName, count: grouped[category]?.count ?? 0)
            }
        }
    }

    // MARK: - Bindings

    private var searchBinding: Binding<String> {
        Binding(
            get: { appState?.notams.searchQuery ?? "" },
            set: { appState?.notams.searchQuery = $0 }
        )
    }

    private var selectedNotamBinding: Binding<String?> {
        Binding(
            get: { appState?.notams.selectedNotam?.id },
            set: { id in
                if let id, let notam = appState?.notams.allNotams.first(where: { $0.id == id }) {
                    appState?.notams.selectedNotam = notam
                    // Mark as read when selected
                    if appState?.settings.autoMarkAsRead == true {
                        appState?.notams.markAsRead(notam)
                    }
                }
            }
        )
    }
}

// MARK: - Section Header

struct NotamSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.fill.tertiary, in: Capsule())
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotamListView()
    }
    .environment(\.appState, AppState.preview())
}
