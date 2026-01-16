//
//  IPhoneLayoutView.swift
//  FlyFunEuroAIP
//
//  iPhone-specific layout with map always visible as background.
//  Uses overlays for search, filters, and chat instead of NavigationSplitView.
//

import SwiftUI

struct IPhoneLayoutView: View {
    @Environment(\.appState) private var state
    @State private var showingFilters = false
    @State private var showingChat = false
    @State private var chatSheetHeight: CGFloat = 350
    @State private var showingInspector = false

    var body: some View {
        ZStack {
            // Layer 1: Map (always visible, full screen)
            AirportMapView()
                .ignoresSafeArea()

            // Layer 2: Top search bar (when not in chat mode)
            if !showingChat {
                VStack {
                    IPhoneSearchBar(showingFilters: $showingFilters)
                    Spacer()
                }
            }

            // Layer 3: Filter overlay (when expanded)
            if showingFilters {
                IPhoneFilterOverlay(isPresented: $showingFilters)
            }

            // Layer 4: Bottom-right floating buttons
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    IPhoneFloatingButtons(showingChat: $showingChat)
                        .padding(.bottom, showingChat ? chatSheetHeight + 16 : 16)
                }
            }
            .padding(.trailing, 16)

            // Layer 5: Chat overlay (resizable from bottom)
            if showingChat {
                IPhoneChatOverlay(
                    height: $chatSheetHeight,
                    isPresented: $showingChat
                )
            }
        }
        // Inspector shows as sheet when airport selected
        .inspector(isPresented: $showingInspector) {
            AirportInspectorView()
        }
        .onChange(of: state?.airports.selectedAirport) { _, newValue in
            showingInspector = (newValue != nil)
        }
    }
}

// MARK: - Preview

#Preview("iPhone Layout") {
    IPhoneLayoutView()
        .environment(\.horizontalSizeClass, .compact)
}
