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
        // AGA - Aerodrome Ground Aids (warm colors)
        case .agaMovement:
            return .red          // Runway, taxiway - critical
        case .agaLighting:
            return .orange       // Lights - safety related
        case .agaFacilities:
            return .brown        // Fuel, services

        // CNS - Communications, Navigation, Surveillance (cool colors)
        case .navigation:
            return .purple       // VOR, DME, NDB
        case .cnsILS:
            return .indigo       // ILS/MLS - precision approaches
        case .cnsGNSS:
            return .cyan         // GPS/GNSS
        case .cnsCommunications:
            return .teal         // Radio, CPDLC

        // ATM - Air Traffic Management (blue/green spectrum)
        case .atmAirspace:
            return .blue         // FIR, TMA, CTR
        case .atmProcedures:
            return .mint         // SID, STAR, approaches
        case .atmServices:
            return .green        // ATC services
        case .airspaceRestrictions:
            return .red          // Danger/restricted areas - critical

        // Other
        case .otherInfo:
            return .secondary    // Obstacles, misc info
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
