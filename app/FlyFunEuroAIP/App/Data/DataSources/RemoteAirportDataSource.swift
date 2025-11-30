//
//  RemoteAirportDataSource.swift
//  FlyFunEuroAIP
//
//  Remote data source using API.
//  Implements same protocol as LocalAirportDataSource for seamless switching.
//
//  Now uses direct JSON decoding to RZFlight models (no adapters needed).
//

import Foundation
import CoreLocation
import RZFlight
import OSLog
import RZUtilsSwift

/// Remote data source using the FlyFun EuroAIP API
/// Returns RZFlight models by decoding directly from API JSON responses
final class RemoteAirportDataSource: AirportRepositoryProtocol, @unchecked Sendable {
    
    // MARK: - Dependencies
    
    private let apiClient: APIClient
    
    /// Decoder for RZFlight models - does NOT use convertFromSnakeCase
    /// because RZFlight CodingKeys handle snake_case explicitly
    private let rzflightDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Note: NO convertFromSnakeCase - RZFlight handles keys explicitly
        return decoder
    }()
    
    // MARK: - Cache
    
    /// Cache border crossing ICAOs from API (loaded once)
    private var borderCrossingCache: Set<String>?
    
    // MARK: - Init
    
    init(apiClient: APIClient) {
        self.apiClient = apiClient
        Logger.app.info("RemoteAirportDataSource initialized with base URL: \(apiClient.baseURL.absoluteString)")
    }
    
    /// Convenience initializer with URL string
    convenience init(baseURLString: String) throws {
        let apiClient = try APIClient(baseURLString: baseURLString)
        self.init(apiClient: apiClient)
    }
    
    // MARK: - Region-Based Query
    
    func airportsInRegion(
        boundingBox: BoundingBox,
        filters: FilterConfig,
        limit: Int
    ) async throws -> [RZFlight.Airport] {
        // API doesn't have bounding box endpoint yet
        // For now, get all airports with filters and filter client-side
        // TODO: Add bounding box endpoint to API
        
        let endpoint = Endpoint.airports(filters: filters, limit: limit)
        let airports: [RZFlight.Airport] = try await apiClient.get(endpoint, decoder: rzflightDecoder)
        
        // Filter by bounding box client-side
        return airports.filter { airport in
            boundingBox.contains(airport.coord)
        }
    }
    
    // MARK: - General Queries
    
    func airports(matching filters: FilterConfig, limit: Int) async throws -> [RZFlight.Airport] {
        let endpoint = Endpoint.airports(filters: filters, limit: limit)
        return try await apiClient.get(endpoint, decoder: rzflightDecoder)
    }
    
    func searchAirports(query: String, limit: Int) async throws -> [RZFlight.Airport] {
        let endpoint = Endpoint.searchAirports(query: query, limit: limit)
        return try await apiClient.get(endpoint, decoder: rzflightDecoder)
    }
    
    func airportDetail(icao: String) async throws -> RZFlight.Airport? {
        let endpoint = Endpoint.airportDetail(icao: icao)
        return try await apiClient.get(endpoint, decoder: rzflightDecoder)
    }
    
    // MARK: - Route & Location
    
    func airportsNearRoute(from: String, to: String, distanceNm: Int, filters: FilterConfig) async throws -> RouteResult {
        let endpoint = Endpoint.routeSearch(from: from, to: to, distanceNm: distanceNm, filters: filters)
        let response: APIRouteSearchResponse = try await apiClient.get(endpoint)
        
        // Convert route airports from response
        let airports: [RZFlight.Airport] = response.airports.compactMap { summary in
            // Decode each airport summary - we need the raw JSON for this
            // For now, use a simple conversion
            Airport(
                location: CLLocationCoordinate2D(
                    latitude: summary.latitudeDeg ?? 0,
                    longitude: summary.longitudeDeg ?? 0
                ),
                icao: summary.ident
            )
        }
        
        return RouteResult(
            airports: airports,
            departure: response.departure?.ident ?? "",
            destination: response.destination?.ident ?? ""
        )
    }
    
    func airportsNearLocation(center: CLLocationCoordinate2D, radiusNm: Int, filters: FilterConfig) async throws -> [RZFlight.Airport] {
        let endpoint = Endpoint.locateAirports(
            latitude: center.latitude,
            longitude: center.longitude,
            radiusNm: radiusNm,
            filters: filters
        )
        let response: APILocateResponse = try await apiClient.get(endpoint)
        
        // Convert located airports
        return response.airports.map { summary in
            Airport(
                location: CLLocationCoordinate2D(
                    latitude: summary.latitudeDeg ?? 0,
                    longitude: summary.longitudeDeg ?? 0
                ),
                icao: summary.ident
            )
        }
    }
    
    // MARK: - In-Memory Filtering
    
    func applyInMemoryFilters(_ filters: FilterConfig, to airports: [RZFlight.Airport]) -> [RZFlight.Airport] {
        // For remote data source, filtering is done server-side
        // This method is mostly for compatibility with the protocol
        // Only apply filters that might not be supported by the API
        
        var result = airports
        
        // Country filter (usually done server-side, but double-check)
        if let country = filters.country {
            result = result.filter { $0.country == country }
        }
        
        return result
    }
    
    // MARK: - Metadata
    
    func availableCountries() async throws -> [String] {
        struct CountryResponse: Codable {
            let code: String
            let name: String
            let count: Int
        }
        
        let response: [CountryResponse] = try await apiClient.get(Endpoint.countries)
        return response.map(\.code).sorted()
    }
    
    func borderCrossingICAOs() async throws -> Set<String> {
        // Check cache first
        if let cached = borderCrossingCache {
            return cached
        }
        
        // Load border crossing airports from API
        let filters = FilterConfig(pointOfEntry: true)
        let endpoint = Endpoint.airports(filters: filters, limit: 5000)
        let airports: [RZFlight.Airport] = try await apiClient.get(endpoint, decoder: rzflightDecoder)
        
        let icaos = Set(airports.map(\.icao))
        borderCrossingCache = icaos
        
        Logger.app.info("Loaded \(icaos.count) border crossing ICAOs from API")
        return icaos
    }
}

// MARK: - Health Check

extension RemoteAirportDataSource {
    
    /// Check if the API is reachable
    func isAPIAvailable() async -> Bool {
        do {
            struct HealthResponse: Codable {
                let status: String
            }
            let response: HealthResponse = try await apiClient.get(Endpoint.health)
            return response.status == "ok"
        } catch {
            Logger.app.warning("API health check failed: \(error.localizedDescription)")
            return false
        }
    }
}

