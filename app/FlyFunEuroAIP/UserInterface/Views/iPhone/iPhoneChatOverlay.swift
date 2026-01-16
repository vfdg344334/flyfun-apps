//
//  iPhoneChatOverlay.swift
//  FlyFunEuroAIP
//
//  Resizable bottom chat overlay for iPhone.
//  User can drag to resize, with snap points at min/mid/max heights.
//

import SwiftUI

struct iPhoneChatOverlay: View {
    @Environment(\.appState) private var state
    @Binding var height: CGFloat
    @Binding var isPresented: Bool

    @GestureState private var dragOffset: CGFloat = 0

    private let minHeight: CGFloat = 200
    private let defaultHeight: CGFloat = 350

    var body: some View {
        GeometryReader { geo in
            let maxHeight = geo.size.height * 0.85
            let currentHeight = min(maxHeight, max(minHeight, height - dragOffset))

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // Drag handle area
                    dragHandle
                        .gesture(
                            DragGesture()
                                .updating($dragOffset) { value, state, _ in
                                    state = value.translation.height
                                }
                                .onEnded { value in
                                    let predictedHeight = height - value.predictedEndTranslation.height
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        snapToHeight(predictedHeight, maxHeight: maxHeight)
                                    }
                                }
                        )

                    // Chat content
                    ChatContent(compactWelcome: true)
                        .frame(height: currentHeight - 40)
                }
                .frame(height: currentHeight)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -5)
                )
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(.secondary.opacity(0.5))
                .frame(width: 40, height: 4)

            HStack {
                // Offline indicator
                if state?.chat.isOfflineMode == true {
                    Label("Offline", systemImage: "airplane.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Text("Chat Assistant")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                // Settings button
                Button {
                    // Could show settings sheet
                } label: {
                    Image(systemName: "gear")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Snap Logic

    private func snapToHeight(_ targetHeight: CGFloat, maxHeight: CGFloat) {
        // Snap points: dismiss (< 150), min (200), mid (50%), max (85%)
        let midHeight = maxHeight * 0.5

        if targetHeight < 150 {
            // Dismiss
            isPresented = false
            height = defaultHeight // Reset for next time
        } else if targetHeight < minHeight + 50 {
            height = minHeight
        } else if targetHeight > maxHeight - 50 {
            height = maxHeight
        } else if targetHeight < midHeight - 50 {
            height = minHeight
        } else if targetHeight > midHeight + 50 {
            height = maxHeight
        } else {
            height = midHeight
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.blue.opacity(0.3)
            .ignoresSafeArea()

        iPhoneChatOverlay(
            height: .constant(350),
            isPresented: .constant(true)
        )
    }
}
