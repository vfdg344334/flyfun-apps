//
//  GAFriendlinessService.swift
//  FlyFunEuroAIP
//
//  Service for accessing GA friendliness data (hotel, restaurant, fees).
//  Loads from bundled ga_persona.db for offline-first access.
//  Mirrors Python GAFriendlinessService architecture.
//

import Foundation
import FMDB
import OSLog
import RZUtilsSwift

// MARK: - Types

/// Hospitality availability level (matches ga_airfield_stats encoding)
enum HospitalityInfo: Int, Sendable, CaseIterable {
    case unknown = 0
    case vicinity = 1
    case atAirport = 2

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .vicinity: return "Nearby"
        case .atAirport: return "At Airport"
        }
    }
}

/// Filter mode for hospitality queries
enum HospitalityFilter: String, Sendable, CaseIterable {
    case vicinity    // includes at_airport (1 or 2)
    case atAirport   // only at_airport (2)

    var displayName: String {
        switch self {
        case .vicinity: return "Nearby or At Airport"
        case .atAirport: return "At Airport Only"
        }
    }

    func matches(_ info: HospitalityInfo) -> Bool {
        switch self {
        case .vicinity:
            return info == .vicinity || info == .atAirport
        case .atAirport:
            return info == .atAirport
        }
    }
}

/// Landing fee information
struct LandingFee: Sendable {
    let icao: String
    let amount: Double
    let currency: String
    let mtowMinKg: Double?
    let mtowMaxKg: Double?
    let source: String?
}

/// Airfield statistics from ga_airfield_stats table
struct AirfieldStats: Sendable {
    let icao: String
    let hotelInfo: HospitalityInfo
    let restaurantInfo: HospitalityInfo
    let feeBand0_749kg: Double?
    let feeBand750_1199kg: Double?
    let feeBand1200_1499kg: Double?
    let feeBand1500_1999kg: Double?
    let feeBand2000_3999kg: Double?
    let feeBand4000PlusKg: Double?
    let feeCurrency: String?

    /// Get fee for a given MTOW
    func feeForWeight(_ mtowKg: Int) -> Double? {
        switch mtowKg {
        case 0..<750: return feeBand0_749kg
        case 750..<1200: return feeBand750_1199kg
        case 1200..<1500: return feeBand1200_1499kg
        case 1500..<2000: return feeBand1500_1999kg
        case 2000..<4000: return feeBand2000_3999kg
        default: return feeBand4000PlusKg
        }
    }
}

// MARK: - Service

/// Service for accessing GA friendliness data from bundled database
/// Mirrors Python GAFriendlinessService architecture
final class GAFriendlinessService: @unchecked Sendable {
    // MARK: - Private

    private let db: FMDatabase
    private var statsCache: [String: AirfieldStats] = [:]
    private let cacheQueue = DispatchQueue(label: "net.ro-z.flyfun.gafriendliness.cache")

    /// Whether the service is available
    let isAvailable: Bool

    // MARK: - Init

    init(databasePath: String) throws {
        let db = FMDatabase(path: databasePath)
        guard db.open() else {
            throw AppError.databaseOpenFailed(path: databasePath)
        }
        self.db = db
        self.isAvailable = true
        Logger.app.info("GAFriendlinessService initialized from \(databasePath)")
    }

    /// Initialize with bundled database
    static func createFromBundle() -> GAFriendlinessService? {
        guard let path = Bundle.main.path(forResource: "ga_persona", ofType: "db") else {
            Logger.app.warning("ga_persona.db not found in bundle")
            return nil
        }
        do {
            return try GAFriendlinessService(databasePath: path)
        } catch {
            Logger.app.error("Failed to initialize GAFriendlinessService: \(error)")
            return nil
        }
    }

    // MARK: - Preloading

    /// Preload all airfield stats into cache (call at startup)
    func preloadAll() async {
        let query = """
            SELECT icao, aip_hotel_info, aip_restaurant_info,
                   fee_band_0_749kg, fee_band_750_1199kg, fee_band_1200_1499kg,
                   fee_band_1500_1999kg, fee_band_2000_3999kg, fee_band_4000_plus_kg,
                   fee_currency
            FROM ga_airfield_stats
        """

        guard let results = db.executeQuery(query, withArgumentsIn: []) else {
            Logger.app.error("Failed to query ga_airfield_stats for preload")
            return
        }

        var loaded = 0
        while results.next() {
            if let stats = parseStatsRow(results) {
                cacheQueue.sync {
                    statsCache[stats.icao] = stats
                }
                loaded += 1
            }
        }
        results.close()
        Logger.app.info("Preloaded \(loaded) airfield stats into GA cache")
    }

    /// Number of cached entries
    var cachedCount: Int {
        cacheQueue.sync { statsCache.count }
    }

    // MARK: - Hotel/Restaurant Queries

    /// Get hotel info for a single airport
    func getHotelInfo(icao: String) -> HospitalityInfo {
        cacheQueue.sync {
            statsCache[icao.uppercased()]?.hotelInfo ?? .unknown
        }
    }

    /// Get restaurant info for a single airport
    func getRestaurantInfo(icao: String) -> HospitalityInfo {
        cacheQueue.sync {
            statsCache[icao.uppercased()]?.restaurantInfo ?? .unknown
        }
    }

    /// Get set of ICAOs that match hotel filter
    func airportsWithHotel(_ filter: HospitalityFilter) -> Set<String> {
        cacheQueue.sync {
            Set(statsCache.filter { filter.matches($0.value.hotelInfo) }.keys)
        }
    }

    /// Get set of ICAOs that match restaurant filter
    func airportsWithRestaurant(_ filter: HospitalityFilter) -> Set<String> {
        cacheQueue.sync {
            Set(statsCache.filter { filter.matches($0.value.restaurantInfo) }.keys)
        }
    }

    /// Get airfield stats for single airport
    func getStats(icao: String) -> AirfieldStats? {
        cacheQueue.sync {
            statsCache[icao.uppercased()]
        }
    }

    // MARK: - Landing Fee Queries

    /// Get landing fee for airport and aircraft weight
    func getLandingFee(icao: String, mtowKg: Int) -> Double? {
        cacheQueue.sync {
            statsCache[icao.uppercased()]?.feeForWeight(mtowKg)
        }
    }

    /// Get fee currency for airport
    func getFeeCurrency(icao: String) -> String? {
        cacheQueue.sync {
            statsCache[icao.uppercased()]?.feeCurrency
        }
    }

    /// Get set of ICAOs with landing fee at or below max (for typical GA weight ~1000kg)
    func airportsWithMaxLandingFee(_ maxFee: Double, mtowKg: Int = 1000) -> Set<String> {
        cacheQueue.sync {
            Set(statsCache.filter { _, stats in
                guard let fee = stats.feeForWeight(mtowKg) else { return false }
                return fee <= maxFee
            }.keys)
        }
    }

    /// Get set of ICAOs that have any fee data
    func airportsWithFeeData() -> Set<String> {
        cacheQueue.sync {
            Set(statsCache.filter { _, stats in
                stats.feeBand0_749kg != nil ||
                stats.feeBand750_1199kg != nil ||
                stats.feeBand1200_1499kg != nil
            }.keys)
        }
    }

    // MARK: - Batch Queries

    /// Get stats for multiple airports
    func getStats(icaos: [String]) -> [String: AirfieldStats] {
        cacheQueue.sync {
            var result: [String: AirfieldStats] = [:]
            for icao in icaos {
                if let stats = statsCache[icao.uppercased()] {
                    result[icao.uppercased()] = stats
                }
            }
            return result
        }
    }

    /// Get all ICAOs that have any data
    func allICAOs() -> Set<String> {
        cacheQueue.sync {
            Set(statsCache.keys)
        }
    }

    // MARK: - Statistics

    /// Get service statistics
    func getStatistics() -> GAStatistics {
        cacheQueue.sync {
            var withHotel = 0
            var withRestaurant = 0
            var withFees = 0

            for stats in statsCache.values {
                if stats.hotelInfo != .unknown { withHotel += 1 }
                if stats.restaurantInfo != .unknown { withRestaurant += 1 }
                if stats.feeBand0_749kg != nil { withFees += 1 }
            }

            return GAStatistics(
                total: statsCache.count,
                withHotelData: withHotel,
                withRestaurantData: withRestaurant,
                withFeeData: withFees
            )
        }
    }

    // MARK: - Private Helpers

    private func parseStatsRow(_ rs: FMResultSet) -> AirfieldStats? {
        guard let icao = rs.string(forColumn: "icao") else { return nil }

        let hotelRaw = rs.columnIsNull("aip_hotel_info") ? 0 : Int(rs.int(forColumn: "aip_hotel_info"))
        let restaurantRaw = rs.columnIsNull("aip_restaurant_info") ? 0 : Int(rs.int(forColumn: "aip_restaurant_info"))

        return AirfieldStats(
            icao: icao.uppercased(),
            hotelInfo: HospitalityInfo(rawValue: hotelRaw) ?? .unknown,
            restaurantInfo: HospitalityInfo(rawValue: restaurantRaw) ?? .unknown,
            feeBand0_749kg: rs.columnIsNull("fee_band_0_749kg") ? nil : rs.double(forColumn: "fee_band_0_749kg"),
            feeBand750_1199kg: rs.columnIsNull("fee_band_750_1199kg") ? nil : rs.double(forColumn: "fee_band_750_1199kg"),
            feeBand1200_1499kg: rs.columnIsNull("fee_band_1200_1499kg") ? nil : rs.double(forColumn: "fee_band_1200_1499kg"),
            feeBand1500_1999kg: rs.columnIsNull("fee_band_1500_1999kg") ? nil : rs.double(forColumn: "fee_band_1500_1999kg"),
            feeBand2000_3999kg: rs.columnIsNull("fee_band_2000_3999kg") ? nil : rs.double(forColumn: "fee_band_2000_3999kg"),
            feeBand4000PlusKg: rs.columnIsNull("fee_band_4000_plus_kg") ? nil : rs.double(forColumn: "fee_band_4000_plus_kg"),
            feeCurrency: rs.string(forColumn: "fee_currency")
        )
    }
}

// MARK: - Statistics

struct GAStatistics: Sendable {
    let total: Int
    let withHotelData: Int
    let withRestaurantData: Int
    let withFeeData: Int
}
