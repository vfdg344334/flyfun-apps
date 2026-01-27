//
//  FlightEditorView.swift
//  FlyFunBrief
//
//  Form for creating or editing a flight.
//

import SwiftUI

/// Editor mode for flight form
enum FlightEditorMode {
    case create
    case edit(CDFlight)

    var title: String {
        switch self {
        case .create: return "New Flight"
        case .edit: return "Edit Flight"
        }
    }

    var actionLabel: String {
        switch self {
        case .create: return "Create"
        case .edit: return "Save"
        }
    }
}

/// Form view for creating or editing a flight
struct FlightEditorView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    let mode: FlightEditorMode

    @State private var origin: String = ""
    @State private var destination: String = ""
    @State private var departureDate: Date = Date()
    @State private var hasDepartureTime: Bool = false
    @State private var durationHours: Double = 0
    @State private var routeString: String = ""
    @State private var hasCruiseAltitude: Bool = false
    @State private var cruiseAltitude: Int = 5000

    @State private var isSaving = false

    var body: some View {
        Form {
            // Route section
            Section("Route") {
                HStack {
                    TextField("Origin", text: $origin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    TextField("Destination", text: $destination)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(maxWidth: .infinity)
                }

                TextField("Route waypoints (optional)", text: $routeString)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }

            // Time section
            Section("Schedule") {
                Toggle("Set departure time", isOn: $hasDepartureTime)

                if hasDepartureTime {
                    DatePicker("Departure", selection: $departureDate)
                }

                HStack {
                    Text("Duration")
                    Spacer()
                    Stepper(
                        durationHours > 0 ? formattedDuration(durationHours) : "Not set",
                        value: $durationHours,
                        in: 0...24,
                        step: 0.5
                    )
                }
            }

            // Altitude section
            Section("Cruise Altitude") {
                Toggle("Set cruise altitude", isOn: $hasCruiseAltitude)

                if hasCruiseAltitude {
                    HStack {
                        Text("Altitude")
                        Spacer()
                        TextField("ft", value: $cruiseAltitude, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("ft")
                            .foregroundStyle(.secondary)
                    }

                    // Quick altitude buttons
                    HStack(spacing: 8) {
                        ForEach([3000, 5000, 7000, 10000], id: \.self) { alt in
                            Button("\(alt / 1000)k") {
                                cruiseAltitude = alt
                            }
                            .buttonStyle(.bordered)
                            .tint(cruiseAltitude == alt ? .blue : .gray)
                        }
                    }
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(mode.actionLabel) {
                    save()
                }
                .disabled(!isValid || isSaving)
            }
        }
        .onAppear {
            loadExistingData()
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !origin.trimmingCharacters(in: .whitespaces).isEmpty &&
        !destination.trimmingCharacters(in: .whitespaces).isEmpty &&
        origin.count >= 3 && origin.count <= 4 &&
        destination.count >= 3 && destination.count <= 4
    }

    // MARK: - Load Existing

    private func loadExistingData() {
        if case .edit(let flight) = mode {
            origin = flight.origin ?? ""
            destination = flight.destination ?? ""
            if let time = flight.departureTime {
                departureDate = time
                hasDepartureTime = true
            }
            durationHours = flight.durationHours
            routeString = flight.routeICAOs ?? ""
            if flight.cruiseAltitude > 0 {
                cruiseAltitude = Int(flight.cruiseAltitude)
                hasCruiseAltitude = true
            }
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true

        Task {
            switch mode {
            case .create:
                await appState?.flights.createFlight(
                    origin: origin.uppercased(),
                    destination: destination.uppercased(),
                    departureTime: hasDepartureTime ? departureDate : nil,
                    durationHours: durationHours > 0 ? durationHours : nil,
                    routeICAOs: routeString.isEmpty ? nil : routeString.uppercased(),
                    cruiseAltitude: hasCruiseAltitude ? Int32(cruiseAltitude) : nil
                )

            case .edit(let flight):
                await appState?.flights.updateFlight(
                    flight,
                    origin: origin.uppercased(),
                    destination: destination.uppercased(),
                    departureTime: hasDepartureTime ? departureDate : nil,
                    durationHours: durationHours > 0 ? durationHours : nil,
                    routeICAOs: routeString.isEmpty ? nil : routeString.uppercased(),
                    cruiseAltitude: hasCruiseAltitude ? Int32(cruiseAltitude) : nil
                )
            }

            dismiss()
        }
    }

    // MARK: - Formatting

    private func formattedDuration(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 && m > 0 {
            return "\(h)h \(m)m"
        } else if h > 0 {
            return "\(h)h"
        } else if m > 0 {
            return "\(m)m"
        } else {
            return "Not set"
        }
    }
}

// MARK: - Preview

#Preview("Create") {
    NavigationStack {
        FlightEditorView(mode: .create)
    }
    .environment(\.appState, AppState.preview())
}
