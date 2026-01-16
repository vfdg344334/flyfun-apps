//
//  iPhoneFloatingButtons.swift
//  FlyFunEuroAIP
//
//  Bottom-right floating action buttons for iPhone.
//  Uses shared FloatingActionButton component.
//

import SwiftUI

struct iPhoneFloatingButtons: View {
    @Environment(\.appState) private var state
    @Binding var showingChat: Bool

    var body: some View {
        VStack(spacing: 12) {
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
                    activeColor: .purple,
                    size: 50
                ) { }
                .allowsHitTesting(false)
            }

            // Chat toggle
            FloatingActionButton(
                icon: showingChat ? "xmark" : "bubble.left.and.bubble.right",
                isActive: !showingChat,
                activeColor: showingChat ? .gray : .green,
                size: 50
            ) {
                withAnimation(.spring(response: 0.3)) {
                    showingChat.toggle()
                }
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

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        VStack {
            Spacer()
            HStack {
                Spacer()
                iPhoneFloatingButtons(showingChat: .constant(false))
                    .padding()
            }
        }
    }
}
