//
//  ContentView.swift
//  FlyFunEuroAIP
//
//  Modern SwiftUI root view using NavigationSplitView (iOS 17+)
//  - Single view for all device sizes (iPad/Mac/iPhone)
//  - .searchable() for native search
//  - .inspector() for airport details (automatic adaptation)
//

import SwiftUI
import MapKit
import RZFlight

struct ContentView: View {
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
            // Show inspector when airport is selected
            showingInspector = (newValue != nil)
        }
        .navigationSplitViewStyle(.balanced)
        // Floating action buttons overlay
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
                Image(systemName: "paintpalette")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.purple, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
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

// MARK: - Floating Action Button

struct FloatingActionButton: View {
    let icon: String
    var isActive: Bool = false
    var activeColor: Color = .blue

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(isActive ? activeColor : activeColor.opacity(0.5), in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("iPad") {
    ContentView()
        .environment(\.horizontalSizeClass, .regular)
}

#Preview("iPhone") {
    ContentView()
        .environment(\.horizontalSizeClass, .compact)
}
