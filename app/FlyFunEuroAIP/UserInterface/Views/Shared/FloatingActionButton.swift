//
//  FloatingActionButton.swift
//  FlyFunEuroAIP
//
//  Shared floating action button style used by both iPad and iPhone layouts.
//

import SwiftUI

/// Circular floating action button with icon and active state.
/// Used for sidebar toggles, chat toggles, and legend pickers.
struct FloatingActionButton: View {
    let icon: String
    var isActive: Bool = false
    var activeColor: Color = .blue
    var size: CGFloat = 44

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(isActive ? activeColor : activeColor.opacity(0.5), in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 16) {
        FloatingActionButton(icon: "magnifyingglass", isActive: true, activeColor: .blue) { }
        FloatingActionButton(icon: "bubble.left.and.bubble.right", isActive: false, activeColor: .green) { }
        FloatingActionButton(icon: "paintpalette", isActive: true, activeColor: .purple) { }
    }
    .padding()
}
