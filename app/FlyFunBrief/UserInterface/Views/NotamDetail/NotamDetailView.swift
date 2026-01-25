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
                if appState?.settings.showRawText == true {
                    rawTextSection
                }
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

    @ViewBuilder
    private var mapSection: some View {
        if let coordinate = notam.coordinate {
            VStack(alignment: .leading, spacing: 8) {
                Text("Location")
                    .font(.headline)

                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: (notam.radiusNm ?? 10) * 1852 * 2,
                    longitudinalMeters: (notam.radiusNm ?? 10) * 1852 * 2
                ))) {
                    Marker(notam.location, coordinate: coordinate)
                        .tint(.red)

                    if let radius = notam.radiusNm {
                        MapCircle(center: coordinate, radius: radius * 1852)
                            .foregroundStyle(.red.opacity(0.1))
                            .stroke(.red, lineWidth: 2)
                    }
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
                .font(.body)
                .textSelection(.enabled)
                .padding()
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Raw Text Section

    private var rawTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw NOTAM")
                .font(.headline)

            Text(notam.rawText)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding()
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                if let qCode = notam.qCode {
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
        NotamDetailView(notam: .preview)
    }
    .environment(\.appState, AppState.preview())
}
