//
//  IgnoreListView.swift
//  FlyFunBrief
//
//  View for managing the global NOTAM ignore list.
//

import SwiftUI
import OSLog

/// View for the global NOTAM ignore list
struct IgnoreListView: View {
    @Environment(\.appState) private var appState
    @State private var ignoredNotams: [CDIgnoredNotam] = []
    @State private var showExpired = false
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if filteredNotams.isEmpty {
                emptyState
            } else {
                ignoreList
            }
        }
        .navigationTitle("Ignored NOTAMs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Show Expired", isOn: $showExpired)

                    Divider()

                    Button(role: .destructive) {
                        cleanupExpired()
                    } label: {
                        Label("Remove Expired", systemImage: "trash")
                    }
                    .disabled(!hasExpiredEntries)
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .task {
            await loadIgnoredNotams()
        }
        .refreshable {
            await loadIgnoredNotams()
        }
    }

    // MARK: - Computed Properties

    private var filteredNotams: [CDIgnoredNotam] {
        if showExpired {
            return ignoredNotams
        } else {
            return ignoredNotams.filter { !$0.isExpired }
        }
    }

    private var hasExpiredEntries: Bool {
        ignoredNotams.contains { $0.isExpired }
    }

    // MARK: - Ignore List

    private var ignoreList: some View {
        List {
            ForEach(filteredNotams, id: \.id) { ignored in
                IgnoredNotamRowView(ignoredNotam: ignored)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            removeFromIgnoreList(ignored)
                        } label: {
                            Label("Remove", systemImage: "xmark.circle")
                        }
                    }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Ignored NOTAMs", systemImage: "xmark.circle")
        } description: {
            Text("NOTAMs you ignore will appear here. You can ignore NOTAMs from the NOTAM list.")
        }
    }

    // MARK: - Loading

    private func loadIgnoredNotams() async {
        isLoading = true

        do {
            if let manager = appState?.ignoreListManager {
                ignoredNotams = try manager.fetchAllIgnores()
            }
        } catch {
            Logger.app.error("Failed to load ignored NOTAMs: \(error.localizedDescription)")
        }

        isLoading = false
    }

    // MARK: - Actions

    private func removeFromIgnoreList(_ ignored: CDIgnoredNotam) {
        Task {
            do {
                try appState?.ignoreListManager.removeFromIgnoreList(ignored)
                await loadIgnoredNotams()
            } catch {
                Logger.app.error("Failed to remove from ignore list: \(error.localizedDescription)")
            }
        }
    }

    private func cleanupExpired() {
        Task {
            do {
                try appState?.ignoreListManager.cleanupExpired()
                await loadIgnoredNotams()
            } catch {
                Logger.app.error("Failed to cleanup expired: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        IgnoreListView()
    }
    .environment(\.appState, AppState.preview())
}
