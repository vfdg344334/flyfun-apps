//
//  NotamDetailView.swift
//  FlyFunBrief
//
//  Full NOTAM detail view with map, raw text, and status controls.
//

import SwiftUI
import MapKit
import RZFlight

/// Detailed NOTAM view with map and status controls
struct NotamDetailView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    let notam: Notam

    @State private var isRawTextExpanded = false

    private var annotation: NotamAnnotation? {
        appState?.notams.annotation(for: notam)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusButtons
                if appState?.settings.showNotamMap == true, notam.coordinate != nil {
                    mapSection
                }
                messageSection
                rawTextSection
                detailsSection
                noteSection
            }
            .padding()
        }
        .navigationTitle(notam.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        copyToClipboard()
                    } label: {
                        Label("Copy NOTAM", systemImage: "doc.on.doc")
                    }

                    Button {
                        appState?.notams.toggleImportant(notam)
                    } label: {
                        if annotation?.status == .important {
                            Label("Remove from Important", systemImage: "star.slash")
                        } else {
                            Label("Mark as Important", systemImage: "star")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            // Mark as read when viewing
            if appState?.settings.autoMarkAsRead == true {
                appState?.notams.markAsRead(notam)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(notam.id)
                    .font(.title2.monospaced().bold())

                Spacer()

                if let category = notam.category {
                    CategoryChip(category: category)
                }
            }

            HStack {
                Label(notam.location, systemImage: "mappin")
                if let fir = notam.fir {
                    Text("FIR: \(fir)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            if let from = notam.effectiveFrom {
                Label(formatDate(from), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if notam.isPermanent {
                Label("PERMANENT", systemImage: "infinity")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Status Buttons

    private var statusButtons: some View {
        HStack(spacing: 12) {
            statusButton(.read, icon: "checkmark.circle", label: "Read", color: .green)
            statusButton(.important, icon: "star.fill", label: "Important", color: .yellow)
            statusButton(.ignore, icon: "xmark.circle", label: "Ignore", color: .secondary)
            statusButton(.followUp, icon: "flag.fill", label: "Follow Up", color: .orange)
        }
    }

    private func statusButton(_ status: NotamStatus, icon: String, label: String, color: Color) -> some View {
        let isSelected = annotation?.status == status

        return Button {
            appState?.notams.setStatus(status, for: notam)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? color.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? color : .secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? color : .secondary)
    }

    // MARK: - Map Section

    /// Calculate the map region to show both the NOTAM and the flight route
    private var mapRegion: MKCoordinateRegion {
        guard let notamCoord = notam.coordinate else {
            return MKCoordinateRegion()
        }

        // Start with the NOTAM coordinate
        var minLat = notamCoord.latitude
        var maxLat = notamCoord.latitude
        var minLon = notamCoord.longitude
        var maxLon = notamCoord.longitude

        // Expand to include route if available
        if let route = appState?.briefing.currentBriefing?.route {
            for coord in route.allCoordinates {
                minLat = min(minLat, coord.latitude)
                maxLat = max(maxLat, coord.latitude)
                minLon = min(minLon, coord.longitude)
                maxLon = max(maxLon, coord.longitude)
            }
        }

        // Add padding (10%)
        let latPadding = (maxLat - minLat) * 0.15
        let lonPadding = (maxLon - minLon) * 0.15

        // Ensure minimum span for NOTAM radius
        let notamRadiusMeters = (notam.radiusNm ?? 10) * 1852 * 2
        let minSpanDegrees = notamRadiusMeters / 111000 // ~111km per degree

        let latSpan = max((maxLat - minLat) + latPadding * 2, minSpanDegrees)
        let lonSpan = max((maxLon - minLon) + lonPadding * 2, minSpanDegrees)

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }

    /// Route coordinates for the polyline
    private var routeCoordinates: [CLLocationCoordinate2D] {
        appState?.briefing.currentBriefing?.route?.allCoordinates ?? []
    }

    @ViewBuilder
    private var mapSection: some View {
        if let coordinate = notam.coordinate {
            VStack(alignment: .leading, spacing: 8) {
                Text("Location")
                    .font(.headline)

                Map(initialPosition: .region(mapRegion)) {
                    // Flight route polyline (if available)
                    if !routeCoordinates.isEmpty {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(.blue, lineWidth: 3)

                        // Departure marker
                        if let dep = routeCoordinates.first,
                           let depName = appState?.briefing.currentBriefing?.route?.departure {
                            Annotation(depName, coordinate: dep) {
                                Image(systemName: "airplane.departure")
                                    .foregroundStyle(.blue)
                                    .padding(4)
                                    .background(.white, in: Circle())
                            }
                        }

                        // Destination marker
                        if let dest = routeCoordinates.last,
                           let destName = appState?.briefing.currentBriefing?.route?.destination,
                           routeCoordinates.count > 1 {
                            Annotation(destName, coordinate: dest) {
                                Image(systemName: "airplane.arrival")
                                    .foregroundStyle(.blue)
                                    .padding(4)
                                    .background(.white, in: Circle())
                            }
                        }
                    }

                    // NOTAM affected area circle
                    if let radius = notam.radiusNm {
                        MapCircle(center: coordinate, radius: radius * 1852)
                            .foregroundStyle(.red.opacity(0.15))
                            .stroke(.red, lineWidth: 2)
                    }

                    // NOTAM location marker
                    Marker(notam.location, coordinate: coordinate)
                        .tint(.red)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Message Section

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .font(.headline)

            Text(notam.message)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding()
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Raw Text Section

    private var rawTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    isRawTextExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Raw NOTAM")
                        .font(.headline)
                    Spacer()
                    Image(systemName: isRawTextExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isRawTextExpanded {
                Text(notam.rawText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding()
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                if let qCodeInfo = notam.qCodeInfo {
                    GridRow {
                        Text("Q-Code")
                            .foregroundStyle(.secondary)
                        Text(qCodeInfo.qCode)
                            .monospaced()
                    }

                    GridRow {
                        Text("Subject")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(qCodeInfo.subjectMeaning) (\(qCodeInfo.subjectCode))")
                            Text(qCodeInfo.subjectCategory)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    GridRow {
                        Text("Condition")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(qCodeInfo.conditionMeaning) (\(qCodeInfo.conditionCode))")
                            Text(qCodeInfo.conditionCategory)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    GridRow {
                        Text("Summary")
                            .foregroundStyle(.secondary)
                        Text(qCodeInfo.displayText)
                            .fontWeight(.medium)
                    }
                } else if let qCode = notam.qCode {
                    GridRow {
                        Text("Q-Code")
                            .foregroundStyle(.secondary)
                        Text(qCode)
                            .monospaced()
                    }
                }

                if let trafficType = notam.trafficType {
                    GridRow {
                        Text("Traffic")
                            .foregroundStyle(.secondary)
                        Text(trafficType == "I" ? "IFR" : trafficType == "V" ? "VFR" : "IFR/VFR")
                    }
                }

                if let scope = notam.scope {
                    GridRow {
                        Text("Scope")
                            .foregroundStyle(.secondary)
                        Text(scope)
                    }
                }

                if let lower = notam.lowerLimit, let upper = notam.upperLimit {
                    GridRow {
                        Text("Altitude")
                            .foregroundStyle(.secondary)
                        Text("\(lower) - \(upper) ft")
                    }
                }

                if let radius = notam.radiusNm {
                    GridRow {
                        Text("Radius")
                            .foregroundStyle(.secondary)
                        Text("\(Int(radius)) NM")
                    }
                }
            }
            .font(.subheadline)
        }
    }

    // MARK: - Note Section

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)

            TextField("Add a note...", text: noteBinding, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { annotation?.textNote ?? "" },
            set: { appState?.notams.setNote($0.isEmpty ? nil : $0, for: notam) }
        )
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy HH:mm 'UTC'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = notam.rawText
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        // Preview placeholder - would use actual Notam in real preview
        Text("NotamDetailView Preview")
    }
    .environment(\.appState, AppState.preview())
}
