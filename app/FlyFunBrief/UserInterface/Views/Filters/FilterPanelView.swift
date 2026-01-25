//
//  FilterPanelView.swift
//  FlyFunBrief
//
//  Filter panel for NOTAM filtering options.
//

import SwiftUI

/// Panel for configuring NOTAM filters
struct FilterPanelView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Status Filter
                Section("Status") {
                    Picker("Show", selection: filterBinding) {
                        ForEach(NotamFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Grouping
                Section("Group By") {
                    Picker("Group", selection: groupingBinding) {
                        ForEach(NotamGrouping.allCases) { grouping in
                            Text(grouping.rawValue).tag(grouping)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Category Filter (future enhancement)
                Section("Categories") {
                    Text("All categories shown")
                        .foregroundStyle(.secondary)
                }

                // Time Filter (future enhancement)
                Section("Time Window") {
                    Text("All NOTAMs shown")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        resetFilters()
                    }
                }
            }
        }
    }

    // MARK: - Bindings

    private var filterBinding: Binding<NotamFilter> {
        Binding(
            get: { appState?.notams.filter ?? .all },
            set: { appState?.notams.filter = $0 }
        )
    }

    private var groupingBinding: Binding<NotamGrouping> {
        Binding(
            get: { appState?.notams.grouping ?? .airport },
            set: { appState?.notams.grouping = $0 }
        )
    }

    // MARK: - Actions

    private func resetFilters() {
        appState?.notams.filter = .all
        appState?.notams.grouping = .airport
        appState?.notams.searchQuery = ""
    }
}

// MARK: - Preview

#Preview {
    FilterPanelView()
        .environment(\.appState, AppState.preview())
}
