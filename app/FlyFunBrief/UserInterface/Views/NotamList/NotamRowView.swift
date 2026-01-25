//
//  NotamRowView.swift
//  FlyFunBrief
//
//  Compact NOTAM row for list display.
//

import SwiftUI
import RZFlight

/// Compact row view for NOTAM list
struct NotamRowView: View {
    @Environment(\.appState) private var appState
    let notam: Notam

    private var annotation: NotamAnnotation? {
        appState?.notams.annotation(for: notam)
    }

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator
            content
            Spacer()
            categoryChip
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                appState?.notams.markAsRead(notam)
            } label: {
                Label("Read", systemImage: "checkmark")
            }
            .tint(.green)

            Button {
                appState?.notams.toggleImportant(notam)
            } label: {
                Label("Important", systemImage: "star")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .leading) {
            Button {
                appState?.notams.markAsIgnored(notam)
            } label: {
                Label("Ignore", systemImage: "xmark")
            }
            .tint(.secondary)
        }
    }

    // MARK: - Status Indicator

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }

    private var statusColor: Color {
        switch annotation?.status ?? .unread {
        case .unread:
            return .blue
        case .read:
            return .gray
        case .important:
            return .yellow
        case .ignore:
            return .secondary.opacity(0.5)
        case .followUp:
            return .orange
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(notam.id)
                    .font(.caption.monospaced().bold())
                    .foregroundStyle(.secondary)

                Text(notam.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(notam.message.prefix(100) + (notam.message.count > 100 ? "..." : ""))
                .font(.subheadline)
                .lineLimit(2)

            if let from = notam.effectiveFrom, let to = notam.effectiveTo {
                Text(formatDateRange(from: from, to: to))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if notam.isPermanent {
                Text("PERMANENT")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Category Chip

    @ViewBuilder
    private var categoryChip: some View {
        if let category = notam.category {
            CategoryChip(category: category)
        }
    }

    // MARK: - Helpers

    private func formatDateRange(from: Date, to: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM HH:mm"
        return "\(formatter.string(from: from)) - \(formatter.string(from: to))"
    }
}

// MARK: - Preview

#Preview {
    List {
        NotamRowView(notam: .preview)
    }
    .environment(\.appState, AppState.preview())
}

// MARK: - Preview Helper

extension Notam {
    static var preview: Notam {
        // Create a minimal preview NOTAM
        // In real app, this would use actual Notam initializer
        fatalError("Implement Notam.preview using actual Notam initializer")
    }
}
