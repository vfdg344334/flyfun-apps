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
        TabView(selection: tabBinding) {
            FlightsTab()
                .tabItem {
                    Label("Flights", systemImage: "airplane")
                }
                .tag(AppTab.flights)

            NotamListTab()
                .tabItem {
                    Label("NOTAMs", systemImage: "list.bullet.rectangle")
                }
                .tag(AppTab.notams)

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
        .sheet(item: sheetBinding) { sheet in
            sheetContent(for: sheet)
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

// MARK: - NOTAM List Tab

struct NotamListTab: View {
    @Environment(\.appState) private var appState

    var body: some View {
        NavigationStack {
            NotamListView()
                .navigationTitle("NOTAMs")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
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
                }
        }
    }

    private var filterIconName: String {
        appState?.notams.hasActiveFilters == true
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
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
