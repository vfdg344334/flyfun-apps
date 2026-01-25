//
//  CategoryChip.swift
//  FlyFunBrief
//
//  Visual chip for displaying NOTAM categories.
//

import SwiftUI
import RZFlight

/// Compact chip showing NOTAM category
struct CategoryChip: View {
    let category: NotamCategory

    var body: some View {
        Text(category.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(categoryColor.opacity(0.2), in: Capsule())
            .foregroundStyle(categoryColor)
    }

    private var categoryColor: Color {
        switch category {
        case .runway:
            return .red
        case .navigation:
            return .purple
        case .airspace:
            return .orange
        case .obstacle:
            return .yellow
        case .lighting:
            return .blue
        case .procedure:
            return .indigo
        case .communication:
            return .teal
        case .movementArea:
            return .brown
        case .services:
            return .green
        case .warning:
            return .red
        case .other:
            return .secondary
        }
    }
}

/// Badge showing NOTAM status
struct StatusBadge: View {
    let status: NotamStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
            Text(status.displayName)
        }
        .font(.caption2.bold())
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.2), in: Capsule())
        .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch status {
        case .unread:
            return .blue
        case .read:
            return .green
        case .important:
            return .yellow
        case .ignore:
            return .secondary
        case .followUp:
            return .orange
        }
    }
}

// MARK: - Previews

#Preview("Category Chips") {
    VStack(spacing: 8) {
        ForEach(NotamCategory.allCases, id: \.rawValue) { category in
            CategoryChip(category: category)
        }
    }
    .padding()
}

#Preview("Status Badges") {
    VStack(spacing: 8) {
        ForEach(NotamStatus.allCases) { status in
            StatusBadge(status: status)
        }
    }
    .padding()
}
