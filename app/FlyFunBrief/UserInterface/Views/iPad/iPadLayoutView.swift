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

    /// Whether we're showing the filter/flight info sidebar vs the main navigation
    private var showingNotamContext: Bool {
        appState?.navigation.selectedTab == .notams && appState?.briefing.currentBriefing != nil
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar: Navigation or Filter Panel based on context
            if showingNotamContext {
                notamContextSidebar
            } else {
                navigationSidebar
            }
        } content: {
            // Content: NOTAM list, flight list, etc.
            contentColumn
        } detail: {
            // Detail: Selected NOTAM or flight details
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
        }
        .sheet(item: sheetBinding) { sheet in
            sheetContent(for: sheet)
        }
    }

    // MARK: - Navigation Sidebar (Tab Selection)

    @ViewBuilder
    private var navigationSidebar: some View {
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
        .navigationTitle("FlyFunBrief")
    }

    // MARK: - NOTAM Context Sidebar (Flight Info + Filters)

    @ViewBuilder
    private var notamContextSidebar: some View {
        List {
            // Back button section
            Section {
                Button {
                    // Go back to navigation mode by clearing briefing or switching tab
                    appState?.navigation.selectedTab = .flights
                } label: {
                    Label("Back to Flights", systemImage: "chevron.left")
                }
            }

            // Flight info section
            if let route = appState?.briefing.currentBriefing?.route {
                Section("Flight") {
                    flightInfoRow(route: route)
                }
            }

            // Filter sections
            Section("Status Filter") {
                statusFilterPicker
            }

            Section("Categories") {
                categoryToggles
            }

            Section("Route Corridor") {
                routeFilterControls
            }

            Section("Time Filter") {
                timeFilterControls
            }

            Section("Visibility") {
                visibilityToggles
            }

            Section("Grouping") {
                groupingPicker
            }

            // Reset filters
            if appState?.notams.hasActiveFilters == true {
                Section {
                    Button(role: .destructive) {
                        appState?.notams.resetFilters()
                    } label: {
                        Label("Reset All Filters", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(sidebarTitle)
    }

    // MARK: - Flight Info Row

    @ViewBuilder
    private func flightInfoRow(route: Route) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Route
            HStack {
                Text(route.departure)
                    .font(.headline.monospaced())
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(route.destination)
                    .font(.headline.monospaced())
            }

            // Departure time
            if let depTime = route.departureTime {
                Label(formatDateTime(depTime), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Waypoints
            if !route.waypoints.isEmpty {
                Text(route.waypoints.joined(separator: " "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            // NOTAM count
            let notamCount = appState?.notams.filteredNotams.count ?? 0
            let totalCount = appState?.notams.allNotams.count ?? 0
            if notamCount != totalCount {
                Text("\(notamCount) of \(totalCount) NOTAMs shown")
                    .font(.caption)
                    .foregroundStyle(.blue)
            } else {
                Text("\(totalCount) NOTAMs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Filter Controls

    private var statusFilterPicker: some View {
        Picker("Status", selection: statusFilterBinding) {
            ForEach(StatusFilter.allCases) { status in
                Text(status.rawValue).tag(status)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var categoryToggles: some View {
        Toggle("Runway", isOn: categoryBinding(\.showRunway))
        Toggle("Navigation", isOn: categoryBinding(\.showNavigation))
        Toggle("Airspace", isOn: categoryBinding(\.showAirspace))
        Toggle("Obstacles", isOn: categoryBinding(\.showObstacle))
        Toggle("Procedures", isOn: categoryBinding(\.showProcedure))
        Toggle("Lighting", isOn: categoryBinding(\.showLighting))
        Toggle("Services", isOn: categoryBinding(\.showServices))
        Toggle("Other", isOn: categoryBinding(\.showOther))
    }

    @ViewBuilder
    private var routeFilterControls: some View {
        Toggle("Filter by Route", isOn: routeEnabledBinding)

        if appState?.notams.routeFilter.isEnabled == true {
            Picker("Corridor Width", selection: corridorWidthBinding) {
                Text("10 nm").tag(10.0)
                Text("25 nm").tag(25.0)
                Text("50 nm").tag(50.0)
                Text("100 nm").tag(100.0)
            }
        }
    }

    @ViewBuilder
    private var timeFilterControls: some View {
        Toggle("Active at Flight Time", isOn: timeFilterEnabledBinding)

        if appState?.notams.timeFilter.isEnabled == true,
           let route = appState?.briefing.currentBriefing?.route,
           let depTime = route.departureTime {
            Text("Departure: \(formatDateTime(depTime))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var visibilityToggles: some View {
        Toggle("Show Read", isOn: showReadBinding)
        Toggle("Show Ignored", isOn: showIgnoredBinding)
    }

    private var groupingPicker: some View {
        Picker("Group By", selection: groupingBinding) {
            ForEach(NotamGrouping.allCases) { grouping in
                Text(grouping.rawValue).tag(grouping)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Sidebar Title

    private var sidebarTitle: String {
        if let route = appState?.briefing.currentBriefing?.route {
            return "\(route.departure) → \(route.destination)"
        }
        return "NOTAMs"
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

    // MARK: - Bindings

    private var sheetBinding: Binding<AppSheet?> {
        Binding(
            get: { appState?.navigation.presentedSheet },
            set: { appState?.navigation.presentedSheet = $0 }
        )
    }

    private var statusFilterBinding: Binding<StatusFilter> {
        Binding(
            get: { appState?.notams.statusFilter ?? .all },
            set: { appState?.notams.statusFilter = $0 }
        )
    }

    private func categoryBinding(_ keyPath: WritableKeyPath<CategoryFilter, Bool>) -> Binding<Bool> {
        Binding(
            get: { appState?.notams.categoryFilter[keyPath: keyPath] ?? true },
            set: { appState?.notams.categoryFilter[keyPath: keyPath] = $0 }
        )
    }

    private var routeEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState?.notams.routeFilter.isEnabled ?? false },
            set: { appState?.notams.routeFilter.isEnabled = $0 }
        )
    }

    private var corridorWidthBinding: Binding<Double> {
        Binding(
            get: { appState?.notams.routeFilter.corridorWidthNm ?? 25 },
            set: { appState?.notams.routeFilter.corridorWidthNm = $0 }
        )
    }

    private var timeFilterEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState?.notams.timeFilter.isEnabled ?? false },
            set: { appState?.notams.timeFilter.isEnabled = $0 }
        )
    }

    private var showReadBinding: Binding<Bool> {
        Binding(
            get: { appState?.notams.visibilityFilter.showRead ?? true },
            set: { appState?.notams.visibilityFilter.showRead = $0 }
        )
    }

    private var showIgnoredBinding: Binding<Bool> {
        Binding(
            get: { appState?.notams.visibilityFilter.showIgnored ?? false },
            set: { appState?.notams.visibilityFilter.showIgnored = $0 }
        )
    }

    private var groupingBinding: Binding<NotamGrouping> {
        Binding(
            get: { appState?.notams.grouping ?? .airport },
            set: { appState?.notams.grouping = $0 }
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

    // MARK: - Helpers

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM HH:mm 'UTC'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    iPadLayoutView()
        .environment(\.appState, AppState.preview())
}
