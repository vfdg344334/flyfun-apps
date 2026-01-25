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
            BriefingTab()
                .tabItem {
                    Label("Briefing", systemImage: "doc.text")
                }
                .tag(AppTab.briefing)

            NotamListTab()
                .tabItem {
                    Label("NOTAMs", systemImage: "list.bullet.rectangle")
                }
                .tag(AppTab.notams)

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
            get: { appState?.navigation.selectedTab ?? .briefing },
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
        }
    }
}

// MARK: - Briefing Tab

struct BriefingTab: View {
    @Environment(\.appState) private var appState

    var body: some View {
        NavigationStack {
            Group {
                if let briefing = appState?.briefing.currentBriefing {
                    BriefingSummaryView(briefing: briefing)
                } else if appState?.briefing.isLoading == true {
                    ImportProgressView()
                } else {
                    EmptyBriefingView()
                }
            }
            .navigationTitle("Briefing")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appState?.navigation.showImportSheet()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
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
                        } label: {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
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

// MARK: - Preview

#Preview {
    iPhoneLayoutView()
        .environment(\.appState, AppState.preview())
}
