//
//  NotamRowView.swift
//  FlyFunBrief
//
//  Compact NOTAM row for list display.
//

import SwiftUI
import RZFlight
import CoreLocation

/// Row view for NOTAM list with configurable display style
struct NotamRowView: View {
    @Environment(\.appState) private var appState
    let enrichedNotam: EnrichedNotam

    /// Convenience accessor for underlying NOTAM
    private var notam: Notam { enrichedNotam.notam }

    /// Current row style from app state
    private var rowStyle: NotamRowStyle {
        appState?.notams.rowStyle ?? .standard
    }

    var body: some View {
        HStack(spacing: 12) {
            statusIndicator
            content
            Spacer()
            badges
        }
        .padding(.vertical, rowStyle == .full ? 8 : 4)
        .opacity(enrichedNotam.isGloballyIgnored ? 0.5 : 1.0)
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
        switch enrichedNotam.status {
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

    // MARK: - Badges

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            if enrichedNotam.isGloballyIgnored {
                Image(systemName: "eye.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title row with inline ID for compact mode
            if rowStyle == .compact {
                compactTitleRow
            } else {
                // Title row: full width
                Text(notamTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Detail row (ID, location, distance, altitude, inactive) - hidden in compact mode
            if rowStyle.showDetailRow {
                HStack(spacing: 8) {
                    Text(notam.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Text(notam.location)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)

                    Spacer()

                    // Distance from route (highlighted if < 50nm)
                    if let distanceText = routeDistanceText {
                        Text(distanceText)
                            .font(.caption2)
                            .foregroundColor(isDistanceRelevant ? .blue : .gray)
                    }

                    // Altitude range (highlighted if includes cruise altitude ±2000ft)
                    if let altitudeText = altitudeRangeText {
                        Text(altitudeText)
                            .font(.caption2)
                            .foregroundColor(isAltitudeRelevant ? .blue : .gray)
                    }

                    // Inactive indicator (if flight time is set and NOTAM is inactive)
                    if isInactiveForFlight {
                        Text("Inactive")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Message text - line limit varies by style
            if rowStyle.messageLineLimit > 0 {
                let charLimit = rowStyle == .full ? 500 : 120
                Text(notam.message.prefix(charLimit) + (notam.message.count > charLimit ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(rowStyle.messageLineLimit)
            }
        }
    }

    // MARK: - Compact Title Row

    /// Compact mode: title + ID on same line
    private var compactTitleRow: some View {
        HStack(spacing: 8) {
            Text(notamTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Text(notam.id)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)

            // Inactive indicator
            if isInactiveForFlight {
                Text("Inactive")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Title Generation

    /// Generate a human-readable title from Q-code info or category
    private var notamTitle: String {
        // Best: use parsed Q-code display text from server
        if let qCodeInfo = notam.qCodeInfo {
            // displayText is like "Runway: Closed" - perfect for title
            return qCodeInfo.displayText
        }

        // Fallback: use primary category from categorization pipeline
        if let primary = notam.primaryCategory {
            let categoryTitle = formatCategory(primary)
            let tagText = formatTags(notam.customTags)
            if !tagText.isEmpty {
                return "\(categoryTitle): \(tagText)"
            }
            return categoryTitle
        }

        // Fall back to ICAO category
        if let category = notam.category {
            return category.displayName
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

    // MARK: - Route Distance

    /// Route coordinates built from CDFlight using KnownAirports
    private var flightRouteCoordinates: [CLLocationCoordinate2D] {
        guard let flight = appState?.flights.selectedFlight,
              let knownAirports = appState?.knownAirports else {
            return []
        }

        var coords: [CLLocationCoordinate2D] = []

        // Origin
        if let origin = flight.origin,
           let airport = knownAirports.airport(icao: origin, ensureRunway: false) {
            coords.append(airport.coordinate)
        }

        // Intermediate waypoints
        for icao in flight.routeArray {
            if let airport = knownAirports.airport(icao: icao, ensureRunway: false) {
                coords.append(airport.coordinate)
            }
        }

        // Destination
        if let destination = flight.destination,
           let airport = knownAirports.airport(icao: destination, ensureRunway: false) {
            coords.append(airport.coordinate)
        }

        return coords
    }

    /// Distance from route centerline (perpendicular distance)
    private var routeDistanceText: String? {
        let routeCoords = flightRouteCoordinates
        guard routeCoords.count >= 2,
              let coordinate = notam.coordinate else {
            return nil
        }

        // Calculate minimum perpendicular distance to route segments
        let distance = RouteGeometry.minimumDistanceToRoute(from: coordinate, routePoints: routeCoords)

        if distance < 1 {
            return "<1nm"
        } else {
            return String(format: "%.0fnm", distance)
        }
    }

    /// Raw distance from route in nautical miles (nil if no route or NOTAM has no coordinates)
    private var routeDistance: Double? {
        let routeCoords = flightRouteCoordinates
        guard routeCoords.count >= 2,
              let coordinate = notam.coordinate else {
            return nil
        }
        return RouteGeometry.minimumDistanceToRoute(from: coordinate, routePoints: routeCoords)
    }

    /// Whether the NOTAM is close enough to the route to be highlighted (< 50nm)
    private var isDistanceRelevant: Bool {
        guard let distance = routeDistance else { return false }
        return distance < 50
    }

    // MARK: - Altitude Range

    /// Formatted altitude range (e.g., "SFC-FL100", "1000-5000ft")
    private var altitudeRangeText: String? {
        let lower = notam.lowerLimit
        let upper = notam.upperLimit

        // If neither is set, return nil
        guard lower != nil || upper != nil else {
            return nil
        }

        let lowerText = formatAltitude(lower, isLower: true)
        let upperText = formatAltitude(upper, isLower: false)

        return "\(lowerText)-\(upperText)"
    }

    /// Format altitude value
    private func formatAltitude(_ feet: Int?, isLower: Bool) -> String {
        guard let feet = feet else {
            return isLower ? "SFC" : "UNL"
        }

        if feet == 0 {
            return "SFC"
        } else if feet >= 18000 {
            // Flight level
            return "FL\(feet / 100)"
        } else if feet >= 1000 {
            // Thousands of feet
            return "\(feet / 1000)k"
        } else {
            return "\(feet)ft"
        }
    }

    /// Whether the NOTAM altitude range is relevant to the flight's cruise altitude
    /// Returns true if cruise altitude ±2000ft overlaps with NOTAM altitude range
    /// Returns false for SFC-UNL (000/999) as this always includes all altitudes
    private var isAltitudeRelevant: Bool {
        guard let flight = appState?.flights.selectedFlight,
              flight.cruiseAltitude > 0 else {
            return false
        }

        let cruiseAlt = Int(flight.cruiseAltitude)
        let lower = notam.lowerLimit ?? 0
        let upper = notam.upperLimit

        // Don't highlight if it's surface to unlimited (000/999 or nil upper)
        // These always include all altitudes so highlighting isn't useful
        if lower == 0 && (upper == nil || upper! >= 99900) {
            return false
        }

        // Check if cruise altitude ±2000ft overlaps with NOTAM range
        let cruiseLower = cruiseAlt - 2000
        let cruiseUpper = cruiseAlt + 2000
        let notamUpper = upper ?? 99999 // Treat nil as unlimited

        // Ranges overlap if: cruiseLower <= notamUpper AND cruiseUpper >= notamLower
        return cruiseLower <= notamUpper && cruiseUpper >= lower
    }

    // MARK: - Inactive Check

    /// Whether the NOTAM is inactive during the flight window (+/- 2 hours)
    private var isInactiveForFlight: Bool {
        guard let route = appState?.notams.currentRoute,
              let departureTime = route.departureTime else {
            return false
        }

        // Flight window: departure - 2h to arrival + 2h (or departure + 2h if no arrival)
        let bufferSeconds: TimeInterval = 2 * 60 * 60
        let windowStart = departureTime.addingTimeInterval(-bufferSeconds)
        let windowEnd = (route.arrivalTime ?? departureTime).addingTimeInterval(bufferSeconds)

        // Check if NOTAM is active during this window
        return !enrichedNotam.isActive(during: windowStart, to: windowEnd)
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
        // Preview would need actual EnrichedNotam data
        Text("NotamRowView Preview")
    }
    .environment(\.appState, AppState.preview())
}
