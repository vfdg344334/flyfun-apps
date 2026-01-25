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
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isZoomedToNotam = false

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
                detailsSection
                noteSection
                rawTextSection
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
            HStack(alignment: .top, spacing: 12) {
                // Left side: NOTAM info
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(notam.id)
                            .font(.title2.monospaced().bold())

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

                    // Altitude constraints
                    if notam.lowerLimit != nil || notam.upperLimit != nil {
                        altitudeLabel
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Altitude Label

    private var altitudeLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.caption)
            if let lower = notam.lowerLimit, let upper = notam.upperLimit {
                Text("\(formatAltitude(lower)) - \(formatAltitude(upper))")
            } else if let lower = notam.lowerLimit {
                Text("From \(formatAltitude(lower))")
            } else if let upper = notam.upperLimit {
                Text("Up to \(formatAltitude(upper))")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Format altitude in feet to readable string (SFC, FL, or ft)
    private func formatAltitude(_ feet: Int) -> String {
        if feet == 0 {
            return "SFC"
        } else if feet >= 99999 {
            return "UNL"
        } else if feet >= 1000 && feet % 100 == 0 {
            return "FL\(feet / 100)"
        } else {
            return "\(feet) ft"
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

    /// Route coordinates for the polyline
    private var routeCoordinates: [CLLocationCoordinate2D] {
        appState?.briefing.currentBriefing?.route?.allCoordinates ?? []
    }

    @ViewBuilder
    private var mapSection: some View {
        if let coordinate = notam.coordinate {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Location")
                        .font(.headline)

                    Spacer()

                    // Zoom controls
                    HStack(spacing: 8) {
                        Button {
                            withAnimation {
                                isZoomedToNotam = true
                                mapPosition = .region(notamOnlyRegion)
                            }
                        } label: {
                            Image(systemName: "scope")
                                .font(.caption)
                                .padding(6)
                                .background(isZoomedToNotam ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Zoom to NOTAM")

                        Button {
                            withAnimation {
                                isZoomedToNotam = false
                                mapPosition = .region(routeAndNotamRegion)
                            }
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .padding(6)
                                .background(!isZoomedToNotam ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Show route and NOTAM")
                    }
                }

                Map(position: $mapPosition) {
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
                .onAppear {
                    // Start with route + NOTAM view
                    mapPosition = .region(routeAndNotamRegion)
                }
            }
        }
    }

    /// Region zoomed to just the NOTAM area
    private var notamOnlyRegion: MKCoordinateRegion {
        guard let notamCoord = notam.coordinate else {
            return MKCoordinateRegion()
        }

        // Size based on NOTAM radius, with minimum span
        let notamRadiusMeters = (notam.radiusNm ?? 5) * 1852 * 3 // 3x radius for context
        let spanDegrees = max(notamRadiusMeters / 111000, 0.05)

        return MKCoordinateRegion(
            center: notamCoord,
            span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
        )
    }

    /// Region showing both the route and NOTAM
    private var routeAndNotamRegion: MKCoordinateRegion {
        guard let notamCoord = notam.coordinate else {
            return MKCoordinateRegion()
        }

        var minLat = notamCoord.latitude
        var maxLat = notamCoord.latitude
        var minLon = notamCoord.longitude
        var maxLon = notamCoord.longitude

        // Include route if available
        for coord in routeCoordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        // Add padding (15%)
        let latPadding = (maxLat - minLat) * 0.15
        let lonPadding = (maxLon - minLon) * 0.15

        // Ensure minimum span for NOTAM visibility
        let notamRadiusMeters = (notam.radiusNm ?? 10) * 1852 * 2
        let minSpanDegrees = notamRadiusMeters / 111000

        let latSpan = max((maxLat - minLat) + latPadding * 2, minSpanDegrees)
        let lonSpan = max((maxLon - minLon) + lonPadding * 2, minSpanDegrees)

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
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

                    // Subject and Condition in one row
                    GridRow {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Subject")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(qCodeInfo.subjectMeaning) (\(qCodeInfo.subjectCode))")
                            Text(qCodeInfo.subjectCategory)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Condition")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(qCodeInfo.conditionMeaning) (\(qCodeInfo.conditionCode))")
                            Text(qCodeInfo.conditionCategory)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
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
