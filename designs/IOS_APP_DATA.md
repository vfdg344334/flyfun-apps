# iOS App Data Layer

> Repository pattern, data sources, and filtering.

## Repository Pattern

The repository abstracts offline/online data sources and returns `RZFlight.Airport` directly.

```
┌─────────────────────────────────────────────────────────────────┐
│                    AirportRepository                             │
│         (Unified API - returns RZFlight types)                   │
└─────────────────────────────┬───────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │                               │
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────────────┐
│   LocalAirportDataSource│     │     RemoteAirportDataSource     │
│   (KnownAirports/SQLite)│     │   (API → RZFlight Adapter)      │
└─────────────────────────┘     └─────────────────────────────────┘
```

## AirportRepositoryProtocol

```swift
protocol AirportRepositoryProtocol: Sendable {
    // Region-based (primary for map performance)
    func airportsInRegion(
        boundingBox: BoundingBox,
        filters: FilterConfig,
        limit: Int
    ) async throws -> [Airport]

    // Search
    func searchAirports(query: String, limit: Int) async throws -> [Airport]

    // Detail
    func airportDetail(icao: String) async throws -> Airport?

    // Route & Location
    func airportsNearRoute(from: String, to: String, distanceNm: Int, filters: FilterConfig) async throws -> RouteResult
    func airportsNearLocation(center: CLLocationCoordinate2D, radiusNm: Int, filters: FilterConfig) async throws -> [Airport]

    // Metadata
    func availableCountries() async throws -> [String]
    func borderCrossingICAOs() async throws -> Set<String>
}
```

## LocalAirportDataSource

Uses `KnownAirports` from RZFlight for all queries.

```swift
final class LocalAirportDataSource: AirportRepositoryProtocol {
    private let db: FMDatabase
    private let knownAirports: KnownAirports

    init(databasePath: String) throws {
        self.db = FMDatabase(path: databasePath)
        guard db.open() else { throw DataSourceError.databaseOpenFailed }
        self.knownAirports = KnownAirports(db: db)
    }

    func airportsInRegion(boundingBox: BoundingBox, filters: FilterConfig, limit: Int) async throws -> [Airport] {
        // KDTree spatial query + filtering
        let regionAirports = knownAirports.known.values.filter { airport in
            boundingBox.contains(airport.coord)
        }

        var filtered = Array(regionAirports)
        filtered = applyFilters(filters, to: filtered)
        return Array(filtered.prefix(limit))
    }

    func searchAirports(query: String, limit: Int) async throws -> [Airport] {
        return Array(knownAirports.matching(needle: query).prefix(limit))
    }

    func airportDetail(icao: String) async throws -> Airport? {
        return knownAirports.airportWithExtendedData(icao: icao)
    }
}
```

## FilterConfig

**Pure data struct** - no database logic. Filtering is done by repository.

```swift
struct FilterConfig: Codable, Equatable, Sendable {
    // Geographic
    var country: String?

    // Features
    var hasProcedures: Bool?
    var hasHardRunway: Bool?
    var hasLightedRunway: Bool?
    var pointOfEntry: Bool?

    // Runway
    var minRunwayLengthFt: Int?
    var maxRunwayLengthFt: Int?

    // Approaches
    var hasILS: Bool?
    var hasRNAV: Bool?
    var hasPrecisionApproach: Bool?

    // Computed
    var hasActiveFilters: Bool { /* check all fields */ }
    var activeFilterCount: Int { /* count non-nil fields */ }

    static let `default` = FilterConfig()

    // NOTE: No apply(to:db:) method!
    // Filtering is done by repository, not FilterConfig.
}
```

## BoundingBox

For region-based queries (map performance).

```swift
struct BoundingBox: Sendable, Equatable {
    let minCoord: CLLocationCoordinate2D  // Southwest
    let maxCoord: CLLocationCoordinate2D  // Northeast

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        coordinate.latitude >= minCoord.latitude &&
        coordinate.latitude <= maxCoord.latitude &&
        coordinate.longitude >= minCoord.longitude &&
        coordinate.longitude <= maxCoord.longitude
    }

    func contains(_ airport: RZFlight.Airport) -> Bool {
        contains(airport.coord)
    }
}

extension MKCoordinateRegion {
    var boundingBox: BoundingBox { /* convert */ }
    func paddedBy(factor: Double) -> MKCoordinateRegion { /* expand */ }
}
```

## Region-Based Loading

Key to map performance: only load visible airports.

```swift
// In AirportDomain
func onRegionChange(_ region: MKCoordinateRegion) {
    guard !isSearchActive else { return }  // Don't overwrite search results

    regionUpdateTask?.cancel()
    regionUpdateTask = Task {
        // Debounce 300ms
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        visibleRegion = region
        airports = try await repository.airportsInRegion(
            boundingBox: region.paddedBy(factor: 1.3).boundingBox,
            filters: filters,
            limit: 500  // Cap for performance
        )
    }
}
```

## App-Specific Models

Only create types for things NOT in RZFlight:

```swift
// Route result
struct RouteResult: Sendable {
    let airports: [RZFlight.Airport]
    let departure: String
    let destination: String
}

// Map highlight (from chat visualization)
struct MapHighlight: Identifiable, Sendable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let color: HighlightColor
    let radius: Double

    enum HighlightColor: String { case blue, red, green, orange, purple }
}

// Route visualization
struct RouteVisualization: Sendable {
    let coordinates: [CLLocationCoordinate2D]
    let departure: String
    let destination: String
}
```

## Connectivity Modes

```swift
enum ConnectivityMode: String, Sendable {
    case offline   // No network, local DB only
    case online    // Network available, prefer API
    case hybrid    // Online with local fallback
}
```

| Feature | Offline | Online |
|---------|---------|--------|
| Airport search | Local DB | API |
| Airport details | Local DB | API |
| Chatbot | MediaPipe LLM | Server API |
| Map tiles | Cached tiles | Live tiles |

## Related Documents

- [IOS_APP_ARCHITECTURE.md](IOS_APP_ARCHITECTURE.md) - Core patterns
- [IOS_APP_MAP.md](IOS_APP_MAP.md) - Map visualization
- [IOS_APP_OFFLINE.md](IOS_APP_OFFLINE.md) - Offline data bundling
