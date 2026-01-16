//
//  iPadLayoutView.swift
//  FlyFunEuroAIP
//
//  iPad layout using NavigationSplitView with sidebar.
//  Sidebar contains search/filters or chat views.
//

import SwiftUI
import MapKit

struct iPadLayoutView: View {
    @Environment(\.appState) private var state
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var showingInspector = false
    @State private var showingChat = false
    @State private var showingChatSettings = false
    @State private var showingOfflineMaps = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // SIDEBAR: Search/Filters, Chat, Settings, or Offline Maps
            if showingChat {
                if showingOfflineMaps {
                    OfflineMapsView(onBack: {
                        withAnimation { showingOfflineMaps = false }
                    })
                } else if showingChatSettings {
                    ChatSettingsView(
                        onShowChat: {
                            withAnimation { showingChatSettings = false }
                        },
                        onShowOfflineMaps: {
                            withAnimation { showingOfflineMaps = true }
                        }
                    )
                } else {
                    ChatView(onShowSettings: {
                        withAnimation { showingChatSettings = true }
                    })
                }
            } else {
                SearchFilterSidebar()
            }
        } detail: {
            // DETAIL: Map with Inspector
            MapDetailView(showingInspector: $showingInspector)
        }
        .onChange(of: state?.airports.selectedAirport) { _, newValue in
            showingInspector = (newValue != nil)
        }
        .navigationSplitViewStyle(.balanced)
        .overlay(alignment: .topTrailing) {
            floatingActionButtons
                .padding(.top, 60)
                .padding(.trailing, 16)
        }
    }

    // MARK: - Floating Action Buttons

    private var floatingActionButtons: some View {
        VStack(spacing: 12) {
            // Toggle sidebar (search/filters)
            FloatingActionButton(
                icon: "magnifyingglass",
                isActive: columnVisibility != .detailOnly && !showingChat,
                activeColor: .blue
            ) {
                withAnimation {
                    if columnVisibility == .detailOnly {
                        columnVisibility = .doubleColumn
                        showingChat = false
                    } else if !showingChat {
                        columnVisibility = .detailOnly
                    } else {
                        showingChat = false
                    }
                }
            }

            // Toggle chat
            FloatingActionButton(
                icon: "bubble.left.and.bubble.right",
                isActive: columnVisibility != .detailOnly && showingChat,
                activeColor: .green
            ) {
                withAnimation {
                    if columnVisibility == .detailOnly {
                        columnVisibility = .doubleColumn
                        showingChat = true
                    } else if showingChat {
                        columnVisibility = .detailOnly
                    } else {
                        showingChat = true
                    }
                }
            }

            // Legend picker
            Menu {
                Picker("Legend", selection: legendModeBinding) {
                    ForEach(LegendMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
            } label: {
                FloatingActionButton(
                    icon: "paintpalette",
                    isActive: true,
                    activeColor: .purple
                ) { }
                .allowsHitTesting(false)
            }
        }
    }

    private var legendModeBinding: Binding<LegendMode> {
        Binding(
            get: { state?.airports.legendMode ?? .airportType },
            set: { state?.airports.legendMode = $0 }
        )
    }
}

// MARK: - Preview

#Preview("iPad Layout") {
    iPadLayoutView()
        .environment(\.horizontalSizeClass, .regular)
}
