//
//  iPhoneLayoutView.swift
//  FlyFunBrief
//
//  iPhone layout with tab bar navigation.
//

import SwiftUI
import RZFlight

/// iPhone layout with compact NOTAM list and tab navigation
struct iPhoneLayoutView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        Group {
            if appState?.navigation.isViewingFlight == true {
                // Flight view mode - show NOTAM list with navigation
                FlightNotamView()
            } else {
                // Tab navigation mode
                tabNavigationView
            }
        }
        .sheet(item: sheetBinding) { sheet in
            sheetContent(for: sheet)
        }
    }

    // MARK: - Tab Navigation View

    private var tabNavigationView: some View {
        TabView(selection: tabBinding) {
            FlightsTab()
                .tabItem {
                    Label("Flights", systemImage: "airplane")
                }
                .tag(AppTab.flights)

            IgnoredTab()
                .tabItem {
                    Label("Ignored", systemImage: "xmark.circle")
                }
                .tag(AppTab.ignored)

            SettingsTab()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings)
        }
    }

    // MARK: - Bindings

    private var tabBinding: Binding<AppTab> {
        Binding(
            get: { appState?.navigation.selectedTab ?? .flights },
            set: { appState?.navigation.selectedTab = $0 }
        )
    }

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
        case .notamDetail(let notamId):
            if let notam = appState?.notams.allNotams.first(where: { $0.id == notamId }) {
                NotamDetailView(notam: notam)
            }
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

// MARK: - Flights Tab

struct FlightsTab: View {
    var body: some View {
        NavigationStack {
            FlightListView()
        }
    }
}

// MARK: - Flight NOTAM View (when viewing a flight)

struct FlightNotamView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        NavigationStack {
            NotamListView()
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            appState?.navigation.exitFlightView()
                            appState?.briefing.clearBriefing()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Flights")
                            }
                        }
                    }

                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            briefingMenu
                            Divider()
                            filterMenu
                        } label: {
                            Label("Options", systemImage: "ellipsis.circle")
                        }
                    }
                }
        }
    }

    private var navigationTitle: String {
        if let flight = appState?.flights.selectedFlight {
            return "\(flight.origin ?? "") → \(flight.destination ?? "")"
        }
        return "NOTAMs"
    }

    // MARK: - Briefing Menu

    @ViewBuilder
    private var briefingMenu: some View {
        if let flight = appState?.flights.selectedFlight {
            let briefings = flight.sortedBriefings

            Section("Briefings") {
                ForEach(briefings, id: \.id) { briefing in
                    Button {
                        appState?.briefing.loadBriefing(briefing)
                    } label: {
                        HStack {
                            if briefing.isLatest {
                                Image(systemName: "star.fill")
                            }
                            Text(briefing.formattedImportDate)
                            Text("(\(briefing.notamCount))")
                            if appState?.briefing.currentCDBriefing?.id == briefing.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Button {
                    appState?.navigation.showImportSheet()
                } label: {
                    Label("Import New Briefing", systemImage: "square.and.arrow.down")
                }
            }
        }
    }

    // MARK: - Filter Menu

    @ViewBuilder
    private var filterMenu: some View {
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

        Divider()

        Button {
            appState?.navigation.showFilterOptions()
        } label: {
            Label("More Filters...", systemImage: "slider.horizontal.3")
        }
    }
}

// MARK: - Ignored Tab

struct IgnoredTab: View {
    var body: some View {
        NavigationStack {
            IgnoreListView()
        }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("Settings")
        }
    }
}

// MARK: - Flight Picker View

struct FlightPickerView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let flights = appState?.flights.flights, !flights.isEmpty {
                    ForEach(flights, id: \.id) { flight in
                        Button {
                            appState?.flights.selectFlight(flight)
                            dismiss()
                        } label: {
                            FlightRowView(flight: flight)
                        }
                    }
                } else {
                    Text("No flights available")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        dismiss()
                        appState?.navigation.showNewFlight()
                    } label: {
                        Label("Create New Flight", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Select Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    iPhoneLayoutView()
        .environment(\.appState, AppState.preview())
}
