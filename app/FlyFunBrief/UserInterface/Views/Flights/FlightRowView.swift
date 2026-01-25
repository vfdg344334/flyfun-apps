//
//  FlightRowView.swift
//  FlyFunBrief
//
//  Row view for displaying a flight in a list.
//

import SwiftUI
import CoreData

/// Row view for a flight in the list
struct FlightRowView: View {
    let flight: CDFlight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Route header
            HStack {
                Text(flight.displayTitle)
                    .font(.headline)

                Spacer()

                if let departureTime = flight.departureTime {
                    Text(formattedDepartureTime(departureTime))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Briefing info
            HStack(spacing: 12) {
                let briefingCount = flight.sortedBriefings.count
                let notamCount = flight.latestBriefing?.notamCount ?? 0
                let unreadCount = flight.unreadNotamCount

                if briefingCount > 0 {
                    Label("\(briefingCount) briefing\(briefingCount == 1 ? "" : "s")", systemImage: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if notamCount > 0 {
                    Label("\(notamCount) NOTAMs", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if unreadCount > 0 {
                    Label("\(unreadCount) unread", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            // Route waypoints if available
            if !flight.routeArray.isEmpty {
                Text(flight.routeArray.joined(separator: " \u{2022} "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func formattedDepartureTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today' HH:mm"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "'Tomorrow' HH:mm"
        } else {
            formatter.dateFormat = "MMM d HH:mm"
        }

        return formatter.string(from: date)
    }
}

// MARK: - Preview

struct FlightRowView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.viewContext
        let flight = CDFlight.create(
            in: context,
            origin: "LFPG",
            destination: "EGLL",
            departureTime: Date().addingTimeInterval(86400),
            durationHours: 1.5
        )
        return List {
            FlightRowView(flight: flight)
        }
    }
}
