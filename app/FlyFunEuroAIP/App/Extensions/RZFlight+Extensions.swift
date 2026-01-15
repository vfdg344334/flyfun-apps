//
//  RZFlight+Extensions.swift
//  FlyFunEuroAIP
//
//  Consolidated extensions for RZFlight types used throughout the app.
//  These are app-specific conveniences, not core functionality.
//

import Foundation
import RZFlight
import CoreLocation

// MARK: - Airport Extensions

extension RZFlight.Airport {
    /// Returns true if the airport has any IFR procedures
    var hasInstrumentProcedures: Bool {
        !procedures.isEmpty
    }

    /// Returns the length of the longest runway in feet
    var maxRunwayLength: Int {
        runways.map(\.length_ft).max() ?? 0
    }

    /// Returns true if the airport has any precision approaches (ILS, GLS, etc.)
    var hasPrecisionApproach: Bool {
        procedures.contains { $0.precisionCategory == .precision }
    }

    /// Returns true if the airport has any RNAV approaches
    var hasRNAVApproach: Bool {
        procedures.contains { $0.precisionCategory == .rnav }
    }
}

// MARK: - Airport Type Extensions

extension RZFlight.Airport.AirportType {
    /// Human-readable display name for airport type
    var displayName: String {
        switch self {
        case .large_airport: return "Large"
        case .medium_airport: return "Medium"
        case .small_airport: return "Small"
        case .seaplane_base: return "Seaplane"
        case .balloonport: return "Balloon"
        case .closed: return "Closed"
        case .none: return "Other"
        }
    }
}

// MARK: - Procedure Type Extensions

extension RZFlight.Procedure.ProcedureType {
    /// Human-readable display name for procedure type
    var displayName: String {
        switch self {
        case .approach: return "Approaches"
        case .departure: return "Departures (SID)"
        case .arrival: return "Arrivals (STAR)"
        }
    }
}

// MARK: - Runway Extensions

extension RZFlight.Runway {
    /// Combined runway identifier (e.g., "09/27")
    var ident: String {
        "\(le.ident)/\(he.ident)"
    }
}

// MARK: - AIP Entry Section Extensions

extension RZFlight.AIPEntry.Section {
    /// Human-readable display name for AIP section
    var displayName: String {
        switch self {
        case .admin: return "Administrative"
        case .operational: return "Operational"
        case .handling: return "Handling"
        case .passenger: return "Passenger Services"
        }
    }
}
