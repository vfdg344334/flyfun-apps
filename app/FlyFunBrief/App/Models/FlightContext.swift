//
//  FlightContext.swift
//  FlyFunBrief
//
//  Flight and route context for NOTAM priority evaluation.
//

import Foundation
import CoreLocation

/// Context about the current flight used for NOTAM priority evaluation.
///
/// This captures all flight-related information needed to evaluate NOTAM relevance
/// and priority without requiring access to Core Data or AppState.
struct FlightContext {
    // MARK: - Route Geometry

    /// Route coordinates from origin through waypoints to destination.
    /// Built from CDFlight using KnownAirports coordinate lookup.
    let routeCoordinates: [CLLocationCoordinate2D]

    // MARK: - Airports

    /// Departure airport ICAO code
    let departureICAO: String?

    /// Destination airport ICAO code
    let destinationICAO: String?

    /// Alternate airport ICAO codes
    let alternateICAOs: [String]

    // MARK: - Altitude

    /// Cruise altitude in feet (from CDFlight)
    let cruiseAltitude: Int?

    // MARK: - Time

    /// Planned departure time
    let departureTime: Date?

    /// Estimated arrival time
    let arrivalTime: Date?

    // MARK: - Computed Properties

    /// Whether we have enough route info to calculate distances
    var hasValidRoute: Bool {
        routeCoordinates.count >= 2
    }

    /// Flight window start (departure - 2 hours buffer)
    var flightWindowStart: Date? {
        departureTime?.addingTimeInterval(-2 * 60 * 60)
    }

    /// Flight window end (arrival + 2 hours buffer, or departure + 2 hours if no arrival)
    var flightWindowEnd: Date? {
        guard let departure = departureTime else { return nil }
        let end = arrivalTime ?? departure
        return end.addingTimeInterval(2 * 60 * 60)
    }

    /// Cruise altitude range for relevance check (±2000 ft)
    var cruiseAltitudeRange: ClosedRange<Int>? {
        guard let cruise = cruiseAltitude, cruise > 0 else { return nil }
        return (cruise - 2000)...(cruise + 2000)
    }

    // MARK: - Initialization

    init(
        routeCoordinates: [CLLocationCoordinate2D] = [],
        departureICAO: String? = nil,
        destinationICAO: String? = nil,
        alternateICAOs: [String] = [],
        cruiseAltitude: Int? = nil,
        departureTime: Date? = nil,
        arrivalTime: Date? = nil
    ) {
        self.routeCoordinates = routeCoordinates
        self.departureICAO = departureICAO
        self.destinationICAO = destinationICAO
        self.alternateICAOs = alternateICAOs
        self.cruiseAltitude = cruiseAltitude
        self.departureTime = departureTime
        self.arrivalTime = arrivalTime
    }

    /// Empty context when no flight is selected
    static let empty = FlightContext()
}
