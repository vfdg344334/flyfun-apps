//
//  iPadLayoutView.swift
//  FlyFunBrief
//
//  iPad layout with NavigationSplitView for side-by-side browsing.
//

import SwiftUI
import RZFlight

/// iPad layout with sidebar and detail panel
struct iPadLayoutView: View {
    @Environment(\.appState) private var appState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar: Flight list or NOTAM list based on context
            sidebarContent
                .navigationTitle(sidebarTitle)
        } content: {
            // Content: Context-dependent (flight detail, briefing list, etc.)
            contentColumn
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
                .disabled(appState?.flights.selectedFlight == nil)
            }

            ToolbarItem(placement: .secondaryAction) {
                filterMenu
            }
        }
        .sheet(item: sheetBinding) { sheet in
            sheetContent(for: sheet)
        }
    }

    // MARK: - Sidebar Title

    private var sidebarTitle: String {
        switch appState?.navigation.selectedTab {
        case .flights:
            return "Flights"
        case .notams:
            if let route = appState?.briefing.currentBriefing?.route {
                return "\(route.departure) \u{2192} \(route.destination)"
            }
            return "NOTAMs"
        case .ignored:
            return "Ignored"
        case .settings:
            return "Settings"
        case .none:
            return "FlyFunBrief"
        }
    }

    // MARK: - Sidebar Content

    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: Binding(
            get: { appState?.navigation.selectedTab },
            set: { if let tab = $0 { appState?.navigation.selectedTab = tab } }
        )) {
            Section {
                Label("Flights", systemImage: "airplane")
                    .tag(AppTab.flights)

                Label("NOTAMs", systemImage: "list.bullet.rectangle")
                    .tag(AppTab.notams)

                Label("Ignored", systemImage: "xmark.circle")
                    .tag(AppTab.ignored)

                Label("Settings", systemImage: "gearshape")
                    .tag(AppTab.settings)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Content Column

    @ViewBuilder
    private var contentColumn: some View {
        switch appState?.navigation.selectedTab {
        case .flights:
            FlightListView()
        case .notams:
            NotamListView()
        case .ignored:
            IgnoreListView()
        case .settings:
            SettingsView()
        case .none:
            ContentUnavailableView("Select a section", systemImage: "sidebar.left")
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let notam = appState?.notams.selectedNotam {
            NotamDetailView(notam: notam)
        } else if appState?.navigation.selectedTab == .flights {
            if let flight = appState?.flights.selectedFlight {
                FlightDetailView(flight: flight)
            } else {
                ContentUnavailableView {
                    Label("Select a Flight", systemImage: "airplane")
                } description: {
                    Text("Choose a flight from the list to see details.")
                }
            }
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
                Text("Select a flight and import a briefing to get started.")
            } actions: {
                Button {
                    appState?.navigation.selectedTab = .flights
                } label: {
                    Label("Go to Flights", systemImage: "airplane")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Filter Menu

    private var filterMenu: some View {
        Menu {
            Section("Status") {
                ForEach(StatusFilter.allCases) { status in
                    Button {
                        appState?.notams.statusFilter = status
                    } label: {
                        if appState?.notams.statusFilter == status {
                            Label(status.rawValue, systemImage: "checkmark")
                        } else {
                            Text(status.rawValue)
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

            Divider()

            Button {
                appState?.navigation.showFilterOptions()
            } label: {
                Label("More Filters...", systemImage: "slider.horizontal.3")
            }
        } label: {
            Label("Filter", systemImage: filterIconName)
        }
    }

    private var filterIconName: String {
        appState?.notams.hasActiveFilters == true
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
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
        case .newFlight:
            NavigationStack {
                FlightEditorView(mode: .create)
            }
        case .editFlight(let flightId):
            if let flight = appState?.flights.flights.first(where: { $0.id == flightId }) {
                NavigationStack {
                    FlightEditorView(mode: .edit(flight))
                }
            }
        case .flightPicker:
            FlightPickerView()
        }
    }
}

// MARK: - Preview

#Preview {
    iPadLayoutView()
        .environment(\.appState, AppState.preview())
}
