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
            // Title row: Generated title from category + tags
            HStack(spacing: 8) {
                Text(notamTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                // Location badge
                Text(notam.location)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.fill.tertiary, in: Capsule())
            }

            // NOTAM ID and Q-code
            HStack(spacing: 8) {
                Text(notam.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if let qCode = notam.qCode {
                    Text(qCode)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Time info
                if notam.isPermanent {
                    Text("PERM")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                } else if let to = notam.effectiveTo {
                    Text("until \(formatShortDate(to))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Message text (smaller)
            Text(notam.message.prefix(120) + (notam.message.count > 120 ? "..." : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Title Generation

    /// Generate a human-readable title from category and tags
    private var notamTitle: String {
        // Use primary category from categorization pipeline if available
        if let primary = notam.primaryCategory {
            let categoryTitle = formatCategory(primary)
            let tagText = formatTags(notam.customTags)
            if !tagText.isEmpty {
                return "\(categoryTitle) \(tagText)"
            }
            return categoryTitle
        }

        // Fall back to ICAO category
        if let category = notam.category {
            return category.displayName
        }

        // Last resort: use Q-code or location
        if let qCode = notam.qCode {
            return decodeQCode(qCode)
        }

        return notam.location
    }

    /// Format primary category to title case
    private func formatCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "runway": return "Runway"
        case "taxiway": return "Taxiway"
        case "apron": return "Apron"
        case "lighting": return "Lighting"
        case "navaid": return "Navaid"
        case "procedure": return "Procedure"
        case "airspace": return "Airspace"
        case "obstacle": return "Obstacle"
        case "communication": return "Comm"
        case "services": return "Services"
        case "warning": return "Warning"
        default: return category.capitalized
        }
    }

    /// Format tags into readable text
    private func formatTags(_ tags: [String]) -> String {
        // Priority tags to show
        let priorityTags = ["closed", "unserviceable", "limited", "unavailable",
                           "active", "changed", "work_in_progress"]

        // Find first priority tag
        for tag in priorityTags {
            if tags.contains(tag) {
                return formatTag(tag)
            }
        }

        // Show specific equipment tags
        let equipmentTags = ["vor", "ils", "dme", "ndb", "glideslope", "localizer",
                            "papi", "vasi", "approach", "sid", "star"]
        for tag in equipmentTags {
            if tags.contains(tag) {
                return tag.uppercased()
            }
        }

        return ""
    }

    /// Format a single tag
    private func formatTag(_ tag: String) -> String {
        switch tag {
        case "closed": return "Closed"
        case "unserviceable": return "U/S"
        case "limited": return "Limited"
        case "unavailable": return "Unavailable"
        case "active": return "Active"
        case "changed": return "Changed"
        case "work_in_progress": return "WIP"
        default: return tag.capitalized
        }
    }

    /// Decode Q-code to basic description
    private func decodeQCode(_ qCode: String) -> String {
        guard qCode.count >= 3 else { return qCode }

        let subject = String(qCode.prefix(3))
        switch subject.uppercased() {
        case "QMR": return "Runway"
        case "QMX": return "Taxiway"
        case "QMA": return "Apron"
        case "QLR", "QLL", "QLX", "QLP", "QLV": return "Lighting"
        case "QNV": return "VOR"
        case "QND": return "DME"
        case "QNI": return "ILS"
        case "QNL": return "Localizer"
        case "QNG": return "Glideslope"
        case "QNB": return "NDB"
        case "QPI": return "Approach"
        case "QPD": return "SID"
        case "QPS": return "STAR"
        case "QAR": return "Restricted Area"
        case "QAD": return "Danger Area"
        case "QAP": return "Prohibited Area"
        case "QOB", "QOE": return "Obstacle"
        case "QCA", "QCF": return "Communication"
        case "QST", "QSA", "QSP": return "ATC"
        case "QSF": return "Fuel"
        case "QWP", "QWU", "QWM", "QWE", "QWH", "QWB", "QWA", "QWF", "QWC", "QWL": return "Warning"
        default: return qCode
        }
    }

    // MARK: - Helpers

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM"
        return formatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    List {
        // Preview would need actual Notam data
        Text("NotamRowView Preview")
    }
    .environment(\.appState, AppState.preview())
}
