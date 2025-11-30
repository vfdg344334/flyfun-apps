//
//  APIAirportModels.swift
//  FlyFunEuroAIP
//
//  Minimal API response models for nested JSON structures.
//  
//  For main airport data, we decode directly to RZFlight.Airport.
//  These models are only needed for wrapper responses (route search, locate, etc.)
//

import Foundation

// MARK: - Airport Summary (for nested responses only)

/// Minimal airport summary for nested response structures
/// Main airport lists decode directly to RZFlight.Airport
struct APIAirportSummary: Codable, Sendable {
    let ident: String
    let name: String?
    let latitudeDeg: Double?
    let longitudeDeg: Double?
    let isoCountry: String?
    let municipality: String?
}

// MARK: - Route Search Response

struct APIRouteSearchResponse: Codable, Sendable {
    let departure: APIAirportSummary?
    let destination: APIAirportSummary?
    let airports: [APIAirportSummary]
    let routeDistanceNm: Double?
}

// MARK: - Locate Response

struct APILocateResponse: Codable, Sendable {
    let center: APICoordinate
    let radiusNm: Int
    let airports: [APIAirportSummary]
}

struct APICoordinate: Codable, Sendable {
    let latitude: Double
    let longitude: Double
}

// MARK: - GA Friendliness (for future use)

/// GA friendliness summary from API
struct APIGAFriendlySummary: Codable, Sendable {
    let features: [String: Double?]
    let personaScores: [String: Double?]
    let reviewCount: Int
    let lastReviewUtc: String?
    let tags: [String]?
    let summaryText: String?
    let notificationHassle: String?
}
