//
//  iPadLayoutView.swift
//  FlyFunBrief
//
//  iPad layout with NavigationSplitView for side-by-side NOTAM browsing.
//

import SwiftUI
import RZFlight

/// iPad layout with sidebar list and detail panel
struct iPadLayoutView: View {
    @Environment(\.appState) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar: NOTAM list
            NotamListView()
                .navigationTitle(routeTitle)
        } detail: {
            // Detail: Selected NOTAM or placeholder
            detailContent
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState?.navigation.showImportSheet()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                filterMenu
            }
        }
        .sheet(item: sheetBinding) { sheet in
            sheetContent(for: sheet)
        }
        .overlay(alignment: .bottom) {
            if appState?.navigation.showFilterPanel == true {
                FilterPanelView()
                    .frame(height: 100)
                    .background(.regularMaterial)
            }
        }
    }

    // MARK: - Route Title

    private var routeTitle: String {
        if let route = appState?.briefing.currentBriefing?.route {
            return "\(route.departure) \u{2192} \(route.destination)"
        }
        return "NOTAMs"
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let notam = appState?.notams.selectedNotam {
            NotamDetailView(notam: notam)
        } else if appState?.briefing.currentBriefing != nil {
            ContentUnavailableView {
                Label("Select a NOTAM", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Choose a NOTAM from the list to see details.")
            }
        } else {
            ContentUnavailableView {
                Label("No Briefing Loaded", systemImage: "doc.badge.plus")
            } description: {
                Text("Import a ForeFlight briefing to get started.")
            } actions: {
                Button {
                    appState?.navigation.showImportSheet()
                } label: {
                    Label("Import Briefing", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Filter Menu

    private var filterMenu: some View {
        Menu {
            Section("Filter") {
                ForEach(NotamFilter.allCases) { filter in
                    Button {
                        appState?.notams.filter = filter
                    } label: {
                        if appState?.notams.filter == filter {
                            Label(filter.rawValue, systemImage: "checkmark")
                        } else {
                            Text(filter.rawValue)
                        }
                    }
                }
            }

            Section("Group By") {
                ForEach(NotamGrouping.allCases) { grouping in
                    Button {
                        appState?.notams.grouping = grouping
                    } label: {
                        if appState?.notams.grouping == grouping {
                            Label(grouping.rawValue, systemImage: "checkmark")
                        } else {
                            Text(grouping.rawValue)
                        }
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Bindings

    private var sheetBinding: Binding<AppSheet?> {
        Binding(
            get: { appState?.navigation.presentedSheet },
            set: { appState?.navigation.presentedSheet = $0 }
        )
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: AppSheet) -> some View {
        switch sheet {
        case .importBriefing:
            ImportBriefingView()
        case .notamDetail:
            // On iPad, detail shows in split view, not sheet
            EmptyView()
        case .filterOptions:
            FilterPanelView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Preview

#Preview {
    iPadLayoutView()
        .environment(\.appState, AppState.preview())
}
