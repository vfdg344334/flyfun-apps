//
//  OfflineGeocoder.swift
//  FlyFunEuroAIP
//
//  Provides offline geocoding using bundled European cities database from GeoNames.
//  Converts place names (e.g., "Bromley", "Nice") to coordinates.
//

import Foundation
import CoreLocation
import SQLite3
import OSLog
import RZUtilsSwift

/// Result of a geocoding lookup
struct GeocodingResult {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let countryCode: String
    let population: Int
}

/// Offline geocoder using bundled GeoNames European cities database
final class OfflineGeocoder {
    
    // MARK: - Singleton
    
    static let shared = OfflineGeocoder()
    
    // MARK: - State
    
    private var db: OpaquePointer?
    private var isInitialized = false
    
    // MARK: - Init
    
    private init() {
        openDatabase()
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    /// Open the bundled European cities database
    private func openDatabase() {
        guard let dbURL = Bundle.main.url(forResource: "european_cities", withExtension: "db") else {
            Logger.app.warning("european_cities.db not found in bundle")
            return
        }
        
        if sqlite3_open(dbURL.path, &db) == SQLITE_OK {
            isInitialized = true
            Logger.app.info("OfflineGeocoder initialized with european_cities.db")
        } else {
            Logger.app.error("Failed to open european_cities.db")
            db = nil
        }
    }
    
    // MARK: - Geocoding
    
    /// Geocode a place name to coordinates
    /// - Parameter query: Place name to search (e.g., "Bromley", "Nice", "Paris")
    /// - Returns: Best matching result or nil if not found
    func geocode(query: String) -> GeocodingResult? {
        guard isInitialized, let db = db else {
            Logger.app.warning("OfflineGeocoder not initialized")
            return nil
        }
        
        let results = searchCities(query: query, limit: 1)
        return results.first
    }
    
    /// Search for cities matching the query
    /// - Parameters:
    ///   - query: Search term (name or partial name)
    ///   - limit: Maximum results to return
    /// - Returns: Array of matching cities, ordered by population (largest first)
    func searchCities(query: String, limit: Int = 10) -> [GeocodingResult] {
        guard isInitialized, let db = db else {
            Logger.app.warning("OfflineGeocoder: database not initialized")
            return []
        }
        
        var results: [GeocodingResult] = []
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Logger.app.info("OfflineGeocoder: Searching for '\(trimmedQuery)'")
        
        // First try exact name match (case insensitive)
        let exactQuery = """
            SELECT name, latitude, longitude, country_code, population
            FROM cities
            WHERE name = ? COLLATE NOCASE
            ORDER BY population DESC
            LIMIT ?
        """
        
        results = executeQuery(db: db, sql: exactQuery, params: [trimmedQuery, limit])
        
        if !results.isEmpty {
            Logger.app.info("OfflineGeocoder: Found \(results.count) exact matches for '\(trimmedQuery)'")
            return results
        }
        
        // If no exact match, try prefix match
        let prefixQuery = """
            SELECT name, latitude, longitude, country_code, population
            FROM cities
            WHERE name LIKE ? COLLATE NOCASE
            ORDER BY population DESC
            LIMIT ?
        """
        results = executeQuery(db: db, sql: prefixQuery, params: ["\(trimmedQuery)%", limit])
        
        if !results.isEmpty {
            Logger.app.info("OfflineGeocoder: Found \(results.count) prefix matches for '\(trimmedQuery)%'")
            return results
        }
        
        // If still no match, try alternate names (contains match)
        let alternateQuery = """
            SELECT name, latitude, longitude, country_code, population
            FROM cities
            WHERE alternate_names LIKE ? COLLATE NOCASE
            ORDER BY population DESC
            LIMIT ?
        """
        results = executeQuery(db: db, sql: alternateQuery, params: ["%\(trimmedQuery)%", limit])
        
        if !results.isEmpty {
            Logger.app.info("OfflineGeocoder: Found \(results.count) alternate name matches for '%\(trimmedQuery)%'")
        } else {
            Logger.app.warning("OfflineGeocoder: No matches found for '\(trimmedQuery)'")
        }
        
        return results
    }
    
    // MARK: - Private Helpers
    
    private func executeQuery(db: OpaquePointer, sql: String, params: [Any]) -> [GeocodingResult] {
        var results: [GeocodingResult] = []
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Logger.app.error("Failed to prepare geocoding query: \(String(cString: sqlite3_errmsg(db)))")
            return []
        }
        
        defer { sqlite3_finalize(stmt) }
        
        // Keep NSString references alive during the query
        var nsStrings: [NSString] = []
        
        // Bind parameters using NSString for stable memory
        for (index, param) in params.enumerated() {
            let idx = Int32(index + 1)
            if let str = param as? String {
                let nsStr = str as NSString
                nsStrings.append(nsStr) // Keep alive
                let cStr = nsStr.utf8String!
                let result = sqlite3_bind_text(stmt, idx, cStr, -1, nil)
                if result != SQLITE_OK {
                    Logger.app.error("Failed to bind string param \(idx): \(str)")
                }
            } else if let int = param as? Int {
                sqlite3_bind_int(stmt, idx, Int32(int))
            }
        }
        
        // Execute and collect results
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(stmt, 0),
                  let countryPtr = sqlite3_column_text(stmt, 3) else {
                continue
            }
            
            let name = String(cString: namePtr)
            let latitude = sqlite3_column_double(stmt, 1)
            let longitude = sqlite3_column_double(stmt, 2)
            let countryCode = String(cString: countryPtr)
            let population = Int(sqlite3_column_int(stmt, 4))
            
            let result = GeocodingResult(
                name: name,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                countryCode: countryCode,
                population: population
            )
            results.append(result)
        }
        
        // nsStrings array keeps the strings alive until here
        _ = nsStrings.count
        
        return results
    }
}
