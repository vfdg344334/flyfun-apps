//
//  IPhoneFloatingButtons.swift
//  FlyFunEuroAIP
//
//  Bottom-right floating action buttons for iPhone.
//

import SwiftUI

struct IPhoneFloatingButtons: View {
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
                IPhoneFloatingButton(icon: "paintpalette", color: .purple)
            }

            // Chat toggle
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showingChat.toggle()
                }
            } label: {
                IPhoneFloatingButton(
                    icon: showingChat ? "xmark" : "bubble.left.and.bubble.right",
                    color: showingChat ? .gray : .green
                )
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

// MARK: - Floating Button Style

struct IPhoneFloatingButton: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .background(color, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
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
                IPhoneFloatingButtons(showingChat: .constant(false))
                    .padding()
            }
        }
    }
}
