# FlyFun EuroAIP iOS/macOS App Design

## Executive Summary

This document describes the architecture and design for the FlyFun EuroAIP native app targeting iOS, iPadOS, and macOS. The app will replicate most web functionality with a key differentiator: **offline/online hybrid operation**.

**Core Principles:**
- **Offline-first**: Full functionality with bundled database when offline
- **Online-enhanced**: Live data, full chatbot, and sync when online
- **Shared logic**: Abstract common code between offline/online modes
- **Adaptive UI**: Responsive layouts for iPhone, iPad, and Mac
- **RZFlight-first**: Maximize reuse of existing RZFlight models and functionality

---

## ⚠️ Critical Design Rule: RZFlight Model Reuse

### Philosophy

The app MUST maximize reuse of models and functionality from the [RZFlight Swift package](https://github.com/roznet/rzflight). RZFlight is the Swift equivalent of `euro_aip` in Python - they share the same database schema and conceptual model.

### Rules

1. **Use RZFlight models directly** - Do NOT create duplicate Airport, Runway, Procedure, or AIPEntry models in the app. Use `RZFlight.Airport`, `RZFlight.Runway`, etc.

2. **Use KnownAirports as the primary data interface** - All airport queries should go through `KnownAirports`, not raw SQL.

3. **Extend RZFlight, not the app** - If functionality exists in `euro_aip` (Python) but not in RZFlight (Swift), propose an enhancement to RZFlight rather than implementing it in the app.

4. **App-specific types only when necessary** - Only create app-level types for:
   - UI-specific state (e.g., `MapHighlight`, `VisualizationPayload`)
   - API response models (for online mode)
   - App configuration (e.g., `FilterConfig` for UI binding)

### Available RZFlight Models

| Model | Description | Key Features |
|-------|-------------|--------------|
| `Airport` | Complete airport data | name, icao, coord, country, type, runways[], procedures[], aipEntries[], elevation_ft, iataCode, etc. |
| `Runway` | Runway with both ends | length_ft, width_ft, surface, lighted, closed, le/he RunwayEnds, isHardSurface |
| `Procedure` | IFR procedures | procedureType (approach/departure/arrival), approachType (ILS/RNAV/etc.), precisionCategory |
| `AIPEntry` | AIP field data | section, field, value, standardField, isStandardized |
| `KnownAirports` | Main query interface | KDTree-based spatial queries, filtering, route search |

### Available KnownAirports Methods

```swift
// Basic queries
func airport(icao:ensureRunway:ensureProcedures:ensureAIP:) -> Airport?
func airportWithExtendedData(icao:) -> Airport?

// Spatial queries
func nearestAirport(coord:) -> Airport?
func nearest(coord:count:) -> [Airport]
func nearestMatching(coord:needle:count:) -> [Airport]
func matching(needle:) -> [Airport]

// Feature queries
func airportsWithBorderCrossing() -> [Airport]
func airportsWithBorderCrossing(near:within:limit:) -> [Airport]
func airportsWithApproach(_:near:within:limit:) -> [Airport]
func airportsWithPrecisionApproaches(near:within:limit:) -> [Airport]
func airportsWithAIPField(_:useStandardized:) -> [Airport]
func airportsNearRoute(_:within:) -> [Airport]
```

### Available Array<Airport> Extensions

```swift
func borderCrossingOnly(db:) -> [Airport]
func withRunwayLength(minimumFeet:) -> [Airport]
func withRunwayLength(minimumFeet:maximumFeet:) -> [Airport]
func withProcedures() -> [Airport]
func withApproaches() -> [Airport]
func withPrecisionApproaches() -> [Airport]
func withHardRunways() -> [Airport]
func withLightedRunways() -> [Airport]
func inCountry(_:) -> [Airport]
func matching(_:) -> [Airport]
```

### Gap Analysis: RZFlight vs euro_aip

Features that may need to be added to RZFlight (enhance library, not app):

| Feature | euro_aip (Python) | RZFlight (Swift) | Action |
|---------|------------------|------------------|--------|
| Fuel filtering (AVGAS/Jet-A) | ✅ | ❌ | Add to RZFlight |
| Landing fee filtering | ✅ | ❌ | Add to RZFlight |
| AIP field value filtering | ✅ | ⚠️ Partial | Enhance in RZFlight |
| Country list query | ✅ | ❌ | Add to RZFlight |
| Filter config application | ✅ | ❌ | Add to RZFlight |

---

## 1. Architecture Overview

### 1.1 High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         SwiftUI Views                             │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │ MapView  │ │SearchView│ │FilterView│ │ ChatView │            │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘            │
│       │            │            │            │                    │
├───────┴────────────┴────────────┴────────────┴───────────────────┤
│                       ViewModels (ObservableObject)               │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────────┐ │
│  │AirportMapVM     │ │ AirportDetailVM │ │   ChatbotVM         │ │
│  │- airports       │ │- airport detail │ │- messages           │ │
│  │- filters        │ │- procedures     │ │- streaming          │ │
│  │- search         │ │- AIP entries    │ │- visualizations     │ │
│  └────────┬────────┘ └────────┬────────┘ └─────────┬───────────┘ │
│           │                   │                    │              │
├───────────┴───────────────────┴────────────────────┴─────────────┤
│                        Repository Layer                           │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │                    AirportRepository                         ││
│  │  - Unified API for data access                               ││
│  │  - Abstracts offline/online sources                          ││
│  │  - Caching and sync strategy                                 ││
│  └────────────┬─────────────────────────────┬───────────────────┘│
│               │                             │                     │
│  ┌────────────┴───────────┐    ┌───────────┴──────────────────┐ │
│  │   LocalDataSource      │    │     RemoteDataSource         │ │
│  │   (SQLite/RZFlight)    │    │     (REST API Client)        │ │
│  └────────────────────────┘    └──────────────────────────────┘ │
│                                                                   │
├──────────────────────────────────────────────────────────────────┤
│                       Chatbot Layer                               │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │                  ChatbotService                              ││
│  │  ┌────────────────────┐  ┌─────────────────────────────────┐││
│  │  │OfflineChatbot      │  │OnlineChatbot                    │││
│  │  │(On-device LLM)     │  │(API streaming)                  │││
│  │  └────────────────────┘  └─────────────────────────────────┘││
│  └──────────────────────────────────────────────────────────────┘│
│                                                                   │
├──────────────────────────────────────────────────────────────────┤
│                     Core Services                                 │
│  ┌────────────┐ ┌─────────────┐ ┌──────────────┐ ┌────────────┐ │
│  │Connectivity│ │ SyncService │ │FilterEngine  │ │Preferences │ │
│  │  Monitor   │ │             │ │              │ │            │ │
│  └────────────┘ └─────────────┘ └──────────────┘ └────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

### 1.2 Design Patterns

| Pattern | Purpose |
|---------|---------|
| **MVVM** | Clean separation of UI and business logic |
| **Repository** | Abstract data sources (offline/online) |
| **Strategy** | Swap chatbot implementations (offline/online) |
| **Observer** | Reactive UI updates via Combine/SwiftUI |
| **Dependency Injection** | Testability and modularity |

### 1.3 Connectivity Modes

```swift
enum ConnectivityMode: Equatable {
    case offline        // No network, local DB only
    case online         // Network available, prefer API
    case hybrid         // Online with local cache fallback
}
```

**Mode Behavior:**

| Feature | Offline | Online |
|---------|---------|--------|
| Airport search | Local DB | API (latest data) |
| Airport details | Local DB | API |
| Filters | Local DB | API |
| Procedures | Local DB | API |
| AIP entries | Local DB (cached) | API |
| Chatbot | On-device LLM (limited) | Full API streaming |
| Map data | Cached tiles | Live tiles |
| Sync | N/A | Background sync |

---

## 2. Data Layer Design

### 2.1 Repository Pattern

**Important:** The repository returns `RZFlight.Airport` directly, not app-specific types.

```swift
import RZFlight

/// Protocol for airport data access - abstracts offline/online sources
/// All methods return RZFlight types directly
protocol AirportRepositoryProtocol {
    // MARK: - Airport Queries (returns RZFlight.Airport)
    func getAirports(filters: FilterConfig, limit: Int) async throws -> [Airport]
    func searchAirports(query: String, limit: Int) async throws -> [Airport]
    func getAirportDetail(icao: String) async throws -> Airport?  // With extended data loaded
    
    // MARK: - Route & Location (returns RZFlight.Airport)
    func getAirportsNearRoute(from: String, to: String, distanceNm: Int, filters: FilterConfig) async throws -> RouteResult
    func getAirportsNearLocation(center: CLLocationCoordinate2D, radiusNm: Int, filters: FilterConfig) async throws -> [Airport]
    
    // MARK: - Extended Data (returns RZFlight types)
    // Note: Procedures, runways, AIP entries are already on Airport
    // Use airport.addProcedures(db:) or airportWithExtendedData(icao:) to load
    func getCountryRules(countryCode: String) async throws -> CountryRules?
    
    // MARK: - Metadata
    func getAvailableCountries() async throws -> [String]
    func getFilterMetadata() async throws -> FilterMetadata
}

/// Route result wrapper
struct RouteResult {
    let airports: [Airport]  // RZFlight.Airport
    let departure: String
    let destination: String
}
```

### 2.2 Local Data Source

Leverages existing `RZFlight` library with `KnownAirports`. **Use RZFlight types directly.**

```swift
import RZFlight

/// Local data source using bundled SQLite database
/// Returns RZFlight.Airport directly - no conversion needed
final class LocalAirportDataSource: AirportRepositoryProtocol {
    private let db: FMDatabase
    private let knownAirports: KnownAirports
    
    init(databasePath: String) throws {
        self.db = FMDatabase(path: databasePath)
        guard db.open() else { throw DataSourceError.databaseOpenFailed }
        self.knownAirports = KnownAirports(db: db)
    }
    
    func getAirports(filters: FilterConfig, limit: Int) async throws -> [Airport] {
        // Start with all airports or filtered subset
        var airports: [Airport]
        
        if filters.pointOfEntry == true {
            airports = knownAirports.airportsWithBorderCrossing()
        } else {
            airports = Array(knownAirports.known.values)
        }
        
        // Apply filters using RZFlight Array extensions
        airports = filters.apply(to: airports, db: db)
        
        return Array(airports.prefix(limit))
    }
    
    func searchAirports(query: String, limit: Int) async throws -> [Airport] {
        // Use KnownAirports.matching() - returns RZFlight.Airport directly
        return Array(knownAirports.matching(needle: query).prefix(limit))
    }
    
    func getAirportsNearRoute(from: String, to: String, distanceNm: Int, filters: FilterConfig) async throws -> RouteResult {
        // Use KnownAirports.airportsNearRoute() directly
        let routeAirports = knownAirports.airportsNearRoute([from, to], within: Double(distanceNm))
        let filtered = filters.apply(to: routeAirports, db: db)
        return RouteResult(airports: filtered, departure: from, destination: to)
    }
    
    func getAirportDetail(icao: String) async throws -> Airport? {
        // Use airportWithExtendedData to load runways, procedures, AIP entries
        return knownAirports.airportWithExtendedData(icao: icao)
    }
    
    // ... other methods leverage KnownAirports directly
}
```

### 2.3 Remote Data Source (With API → RZFlight Adapters)

The remote data source fetches from the API and **converts responses to RZFlight models**.

```swift
import RZFlight

/// Remote data source using web API
/// Converts all API responses to RZFlight models for consistency
final class RemoteAirportDataSource: AirportRepositoryProtocol {
    private let apiClient: APIClient
    private let baseURL: URL
    
    init(baseURL: URL = URL(string: "https://maps.flyfun.aero/api")!) {
        self.baseURL = baseURL
        self.apiClient = APIClient()
    }
    
    func getAirports(filters: FilterConfig, limit: Int) async throws -> [Airport] {
        let endpoint = AirportEndpoint.list(filters: filters, limit: limit)
        let response: APIAirportListResponse = try await apiClient.request(endpoint)
        
        // Convert API response to RZFlight.Airport
        return response.airports.map { APIAirportAdapter.toRZFlight($0) }
    }
    
    func getAirportDetail(icao: String) async throws -> Airport? {
        let endpoint = AirportEndpoint.detail(icao: icao)
        let response: APIAirportDetailResponse = try await apiClient.request(endpoint)
        
        // Convert with extended data (runways, procedures, AIP entries)
        return APIAirportAdapter.toRZFlightWithExtendedData(response)
    }
    
    // ... other methods follow same pattern
}
```

### 2.4 API Response Models (Internal Only)

These models match the API JSON structure. They are **internal** and converted to RZFlight immediately.

```swift
/// Internal: API response structure (DO NOT expose outside adapter)
struct APIAirportListResponse: Decodable {
    let airports: [APIAirport]
    let total: Int
    let page: Int
}

/// Internal: API airport structure
struct APIAirport: Decodable {
    let ident: String
    let name: String?
    let municipality: String?
    let iso_country: String?
    let latitude_deg: Double?
    let longitude_deg: Double?
    let elevation_ft: Int?
    let type: String?
    let continent: String?
    let iata_code: String?
    let longest_runway_length_ft: Int?
    let point_of_entry: Bool?
    let has_procedures: Bool?
    let has_aip_data: Bool?
    let procedure_count: Int?
    let runway_count: Int?
}

/// Internal: API runway structure
struct APIRunway: Decodable {
    let length_ft: Int
    let width_ft: Int?
    let surface: String?
    let lighted: Bool?
    let closed: Bool?
    let le_ident: String?
    let he_ident: String?
    let le_heading_degT: Double?
    let he_heading_degT: Double?
    // ... other fields
}

/// Internal: API procedure structure  
struct APIProcedure: Decodable {
    let name: String
    let procedure_type: String
    let approach_type: String?
    let runway_ident: String?
    // ... other fields
}
```

### 2.5 API → RZFlight Adapters

Adapters convert API responses to RZFlight models. This ensures **one model type throughout the app**.

```swift
import RZFlight

/// Converts API responses to RZFlight models
enum APIAirportAdapter {
    
    /// Convert API airport to RZFlight.Airport
    static func toRZFlight(_ api: APIAirport) -> Airport {
        // Create Airport using the coordinate-based initializer
        var airport = Airport(
            location: CLLocationCoordinate2D(
                latitude: api.latitude_deg ?? 0,
                longitude: api.longitude_deg ?? 0
            ),
            icao: api.ident
        )
        
        // Note: RZFlight.Airport is a struct with let properties
        // For API responses, we may need to use a different initializer
        // or propose an API-friendly initializer to RZFlight
        
        return airport
    }
    
    /// Convert API airport with extended data
    static func toRZFlightWithExtendedData(_ response: APIAirportDetailResponse) -> Airport {
        var airport = toRZFlight(response.airport)
        
        // Convert and attach runways
        airport.runways = response.runways.map { toRZFlight($0) }
        
        // Convert and attach procedures
        airport.procedures = response.procedures.map { toRZFlight($0) }
        
        // Convert and attach AIP entries
        airport.aipEntries = response.aip_entries.map { toRZFlight($0) }
        
        return airport
    }
    
    /// Convert API runway to RZFlight.Runway
    static func toRZFlight(_ api: APIRunway) -> Runway {
        // Build Runway matching RZFlight structure
        // May need to propose Runway initializer to RZFlight
    }
    
    /// Convert API procedure to RZFlight.Procedure
    static func toRZFlight(_ api: APIProcedure) -> Procedure {
        let procedureType = Procedure.ProcedureType(rawValue: api.procedure_type) ?? .approach
        let approachType = api.approach_type.flatMap { Procedure.ApproachType(rawValue: $0) }
        
        return Procedure(
            name: api.name,
            procedureType: procedureType,
            approachType: approachType,
            runwayIdent: api.runway_ident
        )
    }
    
    /// Convert API AIP entry to RZFlight.AIPEntry
    static func toRZFlight(_ api: APIAIPEntry) -> AIPEntry {
        let section = AIPEntry.Section(rawValue: api.section) ?? .operational
        
        return AIPEntry(
            ident: api.airport_icao,
            section: section,
            field: api.field,
            value: api.value,
            altValue: api.alt_value
        )
    }
}
```

### 2.6 RZFlight Initializer Enhancements (Proposed)

The current RZFlight models are primarily designed for database loading. For API usage, we may need to propose these enhancements:

```swift
// Proposed addition to RZFlight.Airport
extension Airport {
    /// Initialize from API-style data (proposed for RZFlight)
    public init(
        icao: String,
        name: String,
        city: String,
        country: String,
        latitude: Double,
        longitude: Double,
        elevation_ft: Int = 0,
        type: AirportType = .none,
        continent: Continent = .none,
        iataCode: String? = nil,
        runways: [Runway] = [],
        procedures: [Procedure] = [],
        aipEntries: [AIPEntry] = []
    ) {
        // Full memberwise initializer
    }
}

// Proposed addition to RZFlight.Runway
extension Runway {
    /// Initialize from API-style data (proposed for RZFlight)
    public init(
        length_ft: Int,
        width_ft: Int,
        surface: String,
        lighted: Bool,
        closed: Bool,
        le: RunwayEnd,
        he: RunwayEnd
    ) {
        // Memberwise initializer
    }
}
```
```

### 2.4 Unified Repository

```swift
/// Main repository that switches between offline/online sources
final class AirportRepository: AirportRepositoryProtocol, ObservableObject {
    @Published private(set) var connectivityMode: ConnectivityMode = .offline
    
    private let localDataSource: LocalAirportDataSource
    private let remoteDataSource: RemoteAirportDataSource
    private let connectivityMonitor: ConnectivityMonitor
    
    private var activeSource: AirportRepositoryProtocol {
        switch connectivityMode {
        case .offline: return localDataSource
        case .online, .hybrid: return remoteDataSource
        }
    }
    
    func getAirports(filters: FilterConfig, limit: Int) async throws -> [Airport] {
        do {
            return try await activeSource.getAirports(filters: filters, limit: limit)
        } catch {
            // Fallback to local on network error (hybrid mode)
            if connectivityMode == .hybrid {
                return try await localDataSource.getAirports(filters: filters, limit: limit)
            }
            throw error
        }
    }
}
```

---

## 3. Models

### 3.1 RZFlight Models (USE THESE - DO NOT DUPLICATE)

The app uses models directly from [RZFlight](https://github.com/roznet/rzflight). **Do NOT create duplicate model types.**

```swift
import RZFlight

// ✅ CORRECT: Use RZFlight types directly
let airport: RZFlight.Airport
let runways: [RZFlight.Runway]
let procedures: [RZFlight.Procedure]
let entries: [RZFlight.AIPEntry]

// ❌ WRONG: Don't create app-level duplicates
// struct AppAirport { ... }  // NO!
```

**RZFlight.Airport** already provides:
- `icao`, `name`, `city`, `country`, `coord`
- `runways: [Runway]`, `procedures: [Procedure]`, `aipEntries: [AIPEntry]`
- `elevation_ft`, `type`, `continent`, `iataCode`
- `approaches`, `departures`, `arrivals` (computed)
- `isBorderCrossing(db:)`, `hasCustoms(db:)`
- Conforms to `Identifiable`, `Hashable`, `Codable`

**RZFlight.Runway** already provides:
- `length_ft`, `width_ft`, `surface`, `lighted`, `closed`
- `le`, `he` (RunwayEnd with coordinates, headings)
- `isHardSurface` (computed)
- `ident1`, `ident2` (runway identifiers)

**RZFlight.Procedure** already provides:
- `name`, `procedureType` (approach/departure/arrival)
- `approachType` (ILS/RNAV/VOR/NDB/etc.)
- `precisionCategory` (precision/rnav/non-precision)
- `fullRunwayIdent`, `isApproach`, `isDeparture`, `isArrival`

**RZFlight.AIPEntry** already provides:
- `section` (admin/operational/handling/passenger)
- `field`, `value`, `standardField`, `mappingScore`
- `isStandardized`, `effectiveFieldName`, `effectiveValue`

### 3.2 App-Specific Types (Only When Necessary)

Only create app-level types for things NOT in RZFlight:
```

```swift
/// App-specific: Filter configuration for UI binding (not in RZFlight)
struct FilterConfig: Codable, Equatable {
    var country: String?
    var hasProcedures: Bool?
    var hasAIPData: Bool?
    var hasHardRunway: Bool?
    var pointOfEntry: Bool?
    var hasAvgas: Bool?
    var hasJetA: Bool?
    var minRunwayLengthFt: Int?
    var maxRunwayLengthFt: Int?
    var maxLandingFee: Int?
    var aipField: String?
    var aipValue: String?
    var aipOperator: AIPOperator?
    
    enum AIPOperator: String, Codable {
        case contains, equals, notEmpty, startsWith, endsWith
    }
    
    static let `default` = FilterConfig()
    
    /// Apply filters to airport array using RZFlight extensions
    func apply(to airports: [Airport], db: FMDatabase) -> [Airport] {
        var result = airports
        
        if let country = country {
            result = result.inCountry(country)
        }
        if pointOfEntry == true {
            result = result.borderCrossingOnly(db: db)
        }
        if hasHardRunway == true {
            result = result.withHardRunways()
        }
        if hasProcedures == true {
            result = result.withProcedures()
        }
        if let minLength = minRunwayLengthFt {
            result = result.withRunwayLength(minimumFeet: minLength)
        }
        // ... additional filters
        
        return result
    }
}

/// App-specific: Map visualization highlight
struct MapHighlight: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let radius: Double
    let popup: String?
}

/// App-specific: Route visualization
struct RouteVisualization {
    let coordinates: [CLLocationCoordinate2D]
    let departure: String  // ICAO
    let destination: String  // ICAO
}

/// App-specific: API response wrapper (for online mode)
struct APIAirportResponse: Codable {
    let airports: [Airport]  // Uses RZFlight.Airport
    let total: Int
    let page: Int
}
```

---

## 4. Chatbot Design

### 4.1 Chatbot Architecture

```swift
/// Protocol for chatbot implementations
protocol ChatbotService {
    var isOnline: Bool { get }
    var capabilities: ChatbotCapabilities { get }
    
    func sendMessage(_ message: String) -> AsyncThrowingStream<ChatEvent, Error>
    func clearHistory()
}

/// Chatbot capabilities (varies by mode)
struct ChatbotCapabilities {
    let supportsStreaming: Bool
    let supportsToolCalls: Bool
    let supportsVisualization: Bool
    let supportedFilters: [String]
    let maxContextLength: Int
}
```

### 4.2 Online Chatbot (Full Functionality)

```swift
/// Online chatbot using web API (SSE streaming)
final class OnlineChatbotService: ChatbotService {
    private let apiClient: APIClient
    private var sessionId: String?
    private var conversationHistory: [ChatMessage] = []
    
    var isOnline: Bool { true }
    
    var capabilities: ChatbotCapabilities {
        ChatbotCapabilities(
            supportsStreaming: true,
            supportsToolCalls: true,
            supportsVisualization: true,
            supportedFilters: FilterConfig.allFilterNames,
            maxContextLength: 128_000
        )
    }
    
    func sendMessage(_ message: String) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let request = ChatRequest(messages: conversationHistory + [.user(message)])
                
                for try await event in apiClient.streamSSE(endpoint: .chatStream(request)) {
                    switch event {
                    case .plan(let plan):
                        continuation.yield(.thinking(plan.reasoning))
                    case .toolCallStart(let name, let args):
                        continuation.yield(.toolCall(name: name, args: args))
                    case .message(let chunk):
                        continuation.yield(.content(chunk))
                    case .uiPayload(let payload):
                        continuation.yield(.visualization(VisualizationPayload(from: payload)))
                    case .done(let tokenInfo):
                        continuation.yield(.done(tokenInfo))
                        continuation.finish()
                    case .error(let error):
                        continuation.finish(throwing: ChatbotError.apiError(error))
                    }
                }
            }
        }
    }
}
```

### 4.3 Offline Chatbot (On-Device LLM)

```swift
/// Offline chatbot using on-device LLM (Apple Intelligence / Core ML)
final class OfflineChatbotService: ChatbotService {
    private let llmEngine: OnDeviceLLMEngine
    private let toolRegistry: OfflineToolRegistry
    private var conversationHistory: [ChatMessage] = []
    
    var isOnline: Bool { false }
    
    var capabilities: ChatbotCapabilities {
        ChatbotCapabilities(
            supportsStreaming: true,  // Token-by-token streaming
            supportsToolCalls: true,  // Limited tools (local DB queries)
            supportsVisualization: true, // Can generate map markers
            supportedFilters: ["country", "hasProcedures", "pointOfEntry", "hasHardRunway"],
            maxContextLength: 4_096   // Smaller context for on-device
        )
    }
    
    func sendMessage(_ message: String) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // 1. Generate plan using on-device LLM
                let plan = try await generatePlan(for: message)
                continuation.yield(.thinking(plan.reasoning))
                
                // 2. Execute tool locally
                if let tool = plan.selectedTool {
                    let result = try await toolRegistry.execute(tool, arguments: plan.arguments)
                    continuation.yield(.toolCall(name: tool, args: plan.arguments))
                }
                
                // 3. Stream response
                for await token in llmEngine.generate(prompt: formatPrompt(plan)) {
                    continuation.yield(.content(token))
                }
                
                // 4. Generate visualization
                if let viz = generateVisualization(from: plan) {
                    continuation.yield(.visualization(viz))
                }
                
                continuation.finish()
            }
        }
    }
}

/// On-device LLM engine (Apple Intelligence or Core ML)
protocol OnDeviceLLMEngine {
    func generate(prompt: String) -> AsyncStream<String>
}
```

### 4.4 Offline Tool Registry

```swift
/// Tools available offline
final class OfflineToolRegistry {
    private let airportRepository: LocalAirportDataSource
    
    /// Available offline tools (subset of online)
    enum OfflineTool: String, CaseIterable {
        case searchAirports = "search_airports"
        case getAirportInfo = "get_airport_info"
        case findAirportsInCountry = "find_airports_in_country"
        case findAirportsNearLocation = "find_airports_near_location"
        // Note: Route search, AIP queries, etc. may be limited offline
    }
    
    func execute(_ tool: String, arguments: [String: Any]) async throws -> ToolResult {
        guard let offlineTool = OfflineTool(rawValue: tool) else {
            throw ToolError.notAvailableOffline(tool)
        }
        
        switch offlineTool {
        case .searchAirports:
            let query = arguments["query"] as? String ?? ""
            let airports = try await airportRepository.searchAirports(query: query, limit: 50)
            return ToolResult(airports: airports)
            
        case .getAirportInfo:
            let icao = arguments["icao"] as? String ?? ""
            let detail = try await airportRepository.getAirportDetail(icao: icao)
            return ToolResult(airportDetail: detail)
            
        // ... other tools
        }
    }
}
```

### 4.5 Chatbot Events

```swift
/// Events streamed from chatbot
enum ChatEvent: Sendable {
    case thinking(String)              // Reasoning/planning
    case toolCall(name: String, args: [String: Any])  // Tool execution
    case content(String)               // Response text chunk
    case visualization(VisualizationPayload)  // Map visualization
    case done(TokenUsage?)             // Completion
}

/// Visualization payload (matches web app)
struct VisualizationPayload: Sendable {
    let kind: VisualizationKind
    let airports: [Airport]?
    let route: RouteVisualization?
    let point: PointVisualization?
    let filterProfile: FilterConfig?
    
    enum VisualizationKind: String {
        case markers
        case routeWithMarkers = "route_with_markers"
        case markerWithDetails = "marker_with_details"
        case pointWithMarkers = "point_with_markers"
    }
}
```

---

## 5. ViewModels

### 5.1 Airport Map ViewModel

```swift
@MainActor
final class AirportMapViewModel: ObservableObject {
    // MARK: - Published State
    @Published var airports: [Airport] = []
    @Published var filteredAirports: [Airport] = []
    @Published var selectedAirport: Airport?
    @Published var filters: FilterConfig = .default
    @Published var searchQuery: String = ""
    @Published var mapRegion: MKCoordinateRegion
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    // MARK: - Visualization State
    @Published var legendMode: LegendMode = .airportType
    @Published var highlights: [String: MapHighlight] = [:]
    @Published var activeRoute: RouteVisualization?
    
    // MARK: - Connectivity
    @Published var connectivityMode: ConnectivityMode = .offline
    
    // MARK: - Dependencies
    private let repository: AirportRepository
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Actions
    func loadAirports() async { ... }
    func search(query: String) async { ... }
    func applyFilters(_ filters: FilterConfig) async { ... }
    func selectAirport(_ airport: Airport) { ... }
    func focusOnAirport(_ airport: Airport) { ... }
    
    // MARK: - Route Operations
    func searchRoute(from: String, to: String) async { ... }
    func clearRoute() { ... }
    
    // MARK: - Filter Operations
    func resetFilters() { ... }
    func toggleFilter(_ keyPath: WritableKeyPath<FilterConfig, Bool?>) { ... }
}

enum LegendMode: String, CaseIterable {
    case airportType = "Airport Type"
    case procedurePrecision = "Procedure Precision"
    case runwayLength = "Runway Length"
    case country = "Country"
}
```

### 5.2 Chatbot ViewModel

```swift
@MainActor
final class ChatbotViewModel: ObservableObject {
    // MARK: - Published State
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var currentThinking: String?
    @Published var pendingVisualization: VisualizationPayload?
    @Published var isOnline: Bool = false
    
    // MARK: - Dependencies
    private let chatbotService: ChatbotService
    private let mapViewModel: AirportMapViewModel  // For applying visualizations
    
    // MARK: - Actions
    func sendMessage() async {
        guard !inputText.isEmpty else { return }
        
        let userMessage = ChatMessage(role: .user, content: inputText)
        messages.append(userMessage)
        inputText = ""
        isStreaming = true
        
        var assistantContent = ""
        
        do {
            for try await event in chatbotService.sendMessage(userMessage.content) {
                switch event {
                case .thinking(let thought):
                    currentThinking = thought
                case .content(let chunk):
                    assistantContent += chunk
                    // Update last message in real-time
                    updateStreamingMessage(assistantContent)
                case .visualization(let payload):
                    pendingVisualization = payload
                    applyVisualization(payload)
                case .done:
                    finalizeMessage(assistantContent)
                default:
                    break
                }
            }
        } catch {
            messages.append(ChatMessage(role: .assistant, content: "Sorry, I encountered an error: \(error.localizedDescription)"))
        }
        
        isStreaming = false
        currentThinking = nil
    }
    
    private func applyVisualization(_ payload: VisualizationPayload) {
        // Apply to map view model
        switch payload.kind {
        case .markers:
            if let airports = payload.airports {
                mapViewModel.airports = airports
            }
        case .routeWithMarkers:
            if let route = payload.route {
                mapViewModel.activeRoute = route
            }
        // ... other cases
        }
        
        // Apply filter profile
        if let filterProfile = payload.filterProfile {
            mapViewModel.filters = filterProfile
        }
    }
}
```

---

## 6. UI Design

### 6.1 Adaptive Layouts

```
┌─────────────────────────────────────────────────────────────────────┐
│                      iPhone (Compact)                                │
├─────────────────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │                        Map (Full Screen)                        │ │
│ │                                                                 │ │
│ │  ┌──────────────┐  ┌───┐                                       │ │
│ │  │  Search...   │  │ ⚙ │  <- Floating controls                 │ │
│ │  └──────────────┘  └───┘                                       │ │
│ │                                                                 │ │
│ └─────────────────────────────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────────────────────────────┐ │
│ │  Results / Filters / Chat (Sheet - swipe up)                    │ │
│ └─────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                    iPad / Mac (Regular)                              │
├─────────────────────────────────────────────────────────────────────┤
│ ┌─────────────┐ ┌───────────────────────────────┐ ┌───────────────┐ │
│ │             │ │                               │ │               │ │
│ │   Search    │ │           Map                 │ │   Filters     │ │
│ │   Results   │ │                               │ │   OR          │ │
│ │             │ │                               │ │   Chat        │ │
│ │   Airport   │ │                               │ │               │ │
│ │   Details   │ │                               │ │               │ │
│ │             │ │                               │ │               │ │
│ └─────────────┘ └───────────────────────────────┘ └───────────────┘ │
│     Sidebar          Main Content                   Inspector        │
└─────────────────────────────────────────────────────────────────────┘
```

### 6.2 View Hierarchy

```swift
// Root View - handles adaptive layout
struct ContentView: View {
    @StateObject private var mapViewModel = AirportMapViewModel()
    @StateObject private var chatViewModel = ChatbotViewModel()
    @Environment(\.horizontalSizeClass) private var sizeClass
    
    var body: some View {
        Group {
            if sizeClass == .regular {
                RegularLayout(mapViewModel: mapViewModel, chatViewModel: chatViewModel)
            } else {
                CompactLayout(mapViewModel: mapViewModel, chatViewModel: chatViewModel)
            }
        }
        .environmentObject(mapViewModel)
        .environmentObject(chatViewModel)
    }
}

// iPad/Mac Layout
struct RegularLayout: View {
    @ObservedObject var mapViewModel: AirportMapViewModel
    @ObservedObject var chatViewModel: ChatbotViewModel
    @State private var showChat = false
    
    var body: some View {
        NavigationSplitView {
            // Sidebar: Search + Results
            SearchSidebar(viewModel: mapViewModel)
        } content: {
            // Main: Map
            AirportMapView(viewModel: mapViewModel)
        } detail: {
            // Detail: Filters or Chat or Airport Detail
            if let airport = mapViewModel.selectedAirport {
                AirportDetailView(airport: airport)
            } else if showChat {
                ChatView(viewModel: chatViewModel)
            } else {
                FilterPanel(viewModel: mapViewModel)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showChat.toggle() }) {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
            }
        }
    }
}

// iPhone Layout
struct CompactLayout: View {
    @ObservedObject var mapViewModel: AirportMapViewModel
    @ObservedObject var chatViewModel: ChatbotViewModel
    @State private var sheetDetent: PresentationDetent = .fraction(0.25)
    
    var body: some View {
        ZStack {
            AirportMapView(viewModel: mapViewModel)
                .ignoresSafeArea()
            
            // Floating search bar
            VStack {
                SearchBarCompact(viewModel: mapViewModel)
                    .padding()
                Spacer()
            }
        }
        .sheet(isPresented: .constant(true)) {
            CompactSheetContent(mapViewModel: mapViewModel, chatViewModel: chatViewModel)
                .presentationDetents([.fraction(0.25), .medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
    }
}
```

### 6.3 Key Views

```swift
// Map View with annotations
struct AirportMapView: View {
    @ObservedObject var viewModel: AirportMapViewModel
    
    var body: some View {
        Map(position: $viewModel.mapPosition) {
            // Airport markers
            ForEach(viewModel.filteredAirports) { airport in
                Annotation(airport.icao, coordinate: airport.coordinate) {
                    AirportMarker(airport: airport, legendMode: viewModel.legendMode)
                        .onTapGesture {
                            viewModel.selectAirport(airport)
                        }
                }
            }
            
            // Route polyline
            if let route = viewModel.activeRoute {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(.blue, lineWidth: 3)
            }
            
            // Highlights
            ForEach(Array(viewModel.highlights.values)) { highlight in
                MapCircle(center: highlight.coordinate, radius: highlight.radius)
                    .foregroundStyle(highlight.color.opacity(0.3))
                    .stroke(highlight.color, lineWidth: 2)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapCompass()
            MapScaleView()
            MapUserLocationButton()
        }
    }
}

// Filter Panel
struct FilterPanel: View {
    @ObservedObject var viewModel: AirportMapViewModel
    
    var body: some View {
        Form {
            Section("Country") {
                Picker("Country", selection: $viewModel.filters.country) {
                    Text("All").tag(nil as String?)
                    ForEach(viewModel.availableCountries, id: \.self) { country in
                        Text(country).tag(country as String?)
                    }
                }
            }
            
            Section("Airport Features") {
                Toggle("Border Crossing", isOn: filterBinding(\.pointOfEntry))
                Toggle("Has Procedures", isOn: filterBinding(\.hasProcedures))
                Toggle("Has AIP Data", isOn: filterBinding(\.hasAIPData))
                Toggle("Hard Runway", isOn: filterBinding(\.hasHardRunway))
            }
            
            Section("Fuel") {
                Toggle("AVGAS", isOn: filterBinding(\.hasAvgas))
                Toggle("Jet-A", isOn: filterBinding(\.hasJetA))
            }
            
            Section("Runway") {
                Stepper(
                    "Min Length: \(viewModel.filters.minRunwayLengthFt ?? 0) ft",
                    value: Binding(
                        get: { viewModel.filters.minRunwayLengthFt ?? 0 },
                        set: { viewModel.filters.minRunwayLengthFt = $0 > 0 ? $0 : nil }
                    ),
                    in: 0...10000,
                    step: 500
                )
            }
            
            Section {
                Button("Reset Filters") {
                    viewModel.resetFilters()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Filters")
    }
}

// Chat View
struct ChatView: View {
    @ObservedObject var viewModel: ChatbotViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Connection status
            if !viewModel.isOnline {
                OfflineBanner()
            }
            
            // Message list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            ChatBubble(message: message)
                        }
                        
                        if viewModel.isStreaming {
                            TypingIndicator()
                        }
                    }
                    .padding()
                }
            }
            
            // Thinking indicator
            if let thinking = viewModel.currentThinking {
                ThinkingBanner(text: thinking)
            }
            
            // Input
            ChatInputBar(
                text: $viewModel.inputText,
                isStreaming: viewModel.isStreaming,
                onSend: { Task { await viewModel.sendMessage() } }
            )
        }
        .navigationTitle("Aviation Assistant")
    }
}
```

---

## 7. Feature Breakdown

### 7.1 Feature Matrix

| Feature | Offline | Online | Notes |
|---------|---------|--------|-------|
| **Map** |
| Display airports | ✅ | ✅ | Bundled vs latest data |
| Map tiles | ✅ (cached) | ✅ | Cache offline tiles |
| Airport markers | ✅ | ✅ | |
| Legend modes | ✅ | ✅ | |
| Route display | ✅ | ✅ | |
| **Search** |
| ICAO/Name search | ✅ | ✅ | |
| Route search | ✅ (basic) | ✅ | Online: optimized routing |
| Location search | ✅ (coords) | ✅ | Online: geocoding |
| **Filters** |
| Country | ✅ | ✅ | |
| Border crossing | ✅ | ✅ | |
| Has procedures | ✅ | ✅ | |
| Has AIP data | ✅ | ✅ | |
| Hard runway | ✅ | ✅ | |
| AVGAS/Jet-A | ⚠️ (limited) | ✅ | May lack fuel data offline |
| Runway length | ✅ | ✅ | |
| Landing fees | ❌ | ✅ | Requires latest data |
| AIP field search | ⚠️ (cached) | ✅ | |
| **Details** |
| Airport info | ✅ | ✅ | |
| Runways | ✅ | ✅ | |
| Procedures | ✅ | ✅ | |
| AIP entries | ⚠️ (cached) | ✅ | May be outdated offline |
| Country rules | ⚠️ (bundled) | ✅ | |
| **Chatbot** |
| Basic queries | ✅ | ✅ | |
| Airport search | ✅ | ✅ | |
| Route planning | ⚠️ (basic) | ✅ | Limited reasoning offline |
| Complex filters | ⚠️ (limited) | ✅ | |
| Streaming | ✅ | ✅ | |
| Visualizations | ✅ | ✅ | |
| **Sync** |
| Database update | N/A | ✅ | Background download |
| Cache AIP data | N/A | ✅ | |

### 7.2 Offline Limitations

1. **Data Freshness**: Bundled database may be weeks/months old
2. **AIP Data**: Only cached entries available
3. **Fuel Info**: May be incomplete
4. **Chatbot Intelligence**: Smaller model, limited reasoning
5. **Geocoding**: No address/city lookup (coordinates only)
6. **Map Tiles**: Only cached regions available

### 7.3 Online Enhancements

1. **Latest Data**: Real-time airport data
2. **Full AIP Access**: Complete AIP entries
3. **Smart Chatbot**: Full GPT-4 powered assistant
4. **Geocoding**: City/address to coordinates
5. **Live Map Tiles**: Current satellite/map imagery
6. **Sync**: Keep local database updated

---

## 8. Data Sync Strategy

### 8.1 Sync Architecture

```swift
/// Manages database synchronization
final class SyncService: ObservableObject {
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    @Published var downloadProgress: Double = 0
    
    enum SyncStatus {
        case idle
        case checking
        case downloading(progress: Double)
        case applying
        case complete
        case failed(Error)
    }
    
    /// Check for updates and sync if needed
    func syncIfNeeded() async throws {
        syncStatus = .checking
        
        // Check server for latest database version
        let serverVersion = try await apiClient.getDatabaseVersion()
        
        guard serverVersion > localDatabaseVersion else {
            syncStatus = .complete
            return
        }
        
        // Download incremental updates or full database
        syncStatus = .downloading(progress: 0)
        
        if let deltaURL = try await apiClient.getDeltaUpdate(from: localDatabaseVersion) {
            // Apply incremental update
            try await applyDelta(deltaURL)
        } else {
            // Download full database
            try await downloadFullDatabase()
        }
        
        syncStatus = .complete
        lastSyncDate = Date()
    }
}
```

### 8.2 Caching Strategy

```swift
/// Cache manager for AIP entries and other data
final class CacheManager {
    private let cache: URLCache
    private let fileManager: FileManager
    
    /// Cache AIP entries for offline access
    func cacheAIPEntries(for icao: String, entries: [AIPEntry]) {
        let data = try? JSONEncoder().encode(entries)
        let key = "aip-\(icao)"
        UserDefaults.standard.set(data, forKey: key)
    }
    
    /// Get cached AIP entries
    func getCachedAIPEntries(for icao: String) -> [AIPEntry]? {
        guard let data = UserDefaults.standard.data(forKey: "aip-\(icao)"),
              let entries = try? JSONDecoder().decode([AIPEntry].self, from: data) else {
            return nil
        }
        return entries
    }
    
    /// Cache map tiles for offline regions
    func cacheMapTiles(for region: MKCoordinateRegion) async {
        // Pre-cache tiles for specified region
    }
}
```

---

## 9. Implementation Phases

### Phase 1: Foundation (2-3 weeks)
- [ ] Repository pattern with offline/online sources
- [ ] Core models (Airport, Runway, Procedure, etc.)
- [ ] Connectivity monitoring
- [ ] Enhanced AirportMapViewModel
- [ ] Basic filter implementation

### Phase 2: UI Enhancement (2-3 weeks)
- [ ] Adaptive layouts (iPhone/iPad/Mac)
- [ ] Filter panel with all filters
- [ ] Airport detail view
- [ ] Search with route detection
- [ ] Legend modes

### Phase 3: Online Integration (2 weeks)
- [ ] API client implementation
- [ ] Remote data source
- [ ] Sync service
- [ ] Cache management
- [ ] Error handling & fallbacks

### Phase 4: Chatbot - Online (2-3 weeks)
- [ ] SSE streaming client
- [ ] ChatbotViewModel
- [ ] Chat UI (messages, streaming, thinking)
- [ ] Visualization handling
- [ ] Filter profile application

### Phase 5: Chatbot - Offline (3-4 weeks)
- [ ] On-device LLM integration (Core ML / Apple Intelligence)
- [ ] Offline tool registry
- [ ] Simplified planning
- [ ] Local tool execution
- [ ] Offline visualization

### Phase 6: Polish & Testing (2 weeks)
- [ ] Performance optimization
- [ ] Offline map tile caching
- [ ] Error handling refinement
- [ ] UI polish and animations
- [ ] Testing on all platforms

---

## 10. Dependencies

### Required
- **RZFlight** - Airport data and spatial queries
- **RZUtilsSwift** - Utilities and logging
- **FMDB** - SQLite access

### Recommended
- **MapKit** - Native maps (already used)
- **Combine** - Reactive programming
- **Core ML** - On-device LLM (Phase 5)

### Optional
- **SwiftLint** - Code quality
- **Quick/Nimble** - Testing

---

## 11. Open Questions

1. **On-device LLM**: Which model to use?
   - Apple Intelligence (iOS 18.1+)?
   - Custom Core ML model?
   - Third-party (e.g., llama.cpp)?

2. **Map tiles**: How to handle offline caching?
   - Pre-cache Europe on first launch?
   - User-selected regions?
   - Cache as user browses?

3. **Database updates**: Update strategy?
   - Full download vs incremental deltas?
   - Update frequency?
   - Storage constraints?

4. **Platform targeting**:
   - iOS minimum version (17? 18?)?
   - macOS minimum version?
   - Apple Silicon only for on-device LLM?

---

## 12. RZFlight Enhancement Proposals

When functionality exists in `euro_aip` (Python) but not in RZFlight (Swift), propose enhancements to RZFlight rather than implementing in the app. Track proposals here:

### 12.1 Proposed Enhancements

| Enhancement | euro_aip Reference | Priority | Status |
|-------------|-------------------|----------|--------|
| **API-friendly initializers** | For API → RZFlight conversion | **Critical** | Proposed |
| **Fuel filtering** | `has_avgas`, `has_jet_a` fields | High | Proposed |
| **Landing fee filtering** | `max_landing_fee` filter | Medium | Proposed |
| **Country list query** | `get_available_countries()` | High | Proposed |
| **Filter config object** | `FilterConfig` class | Medium | Proposed |
| **AIP value search** | `filter_by_aip_field()` | Medium | Proposed |

### 12.2 How to Propose

1. **Check euro_aip**: Review the Python implementation in `src/euro-aip/euro_aip/`
2. **Design Swift API**: Follow existing RZFlight patterns
3. **Update RZFlight**: Submit changes to [roznet/rzflight](https://github.com/roznet/rzflight)
4. **Update app**: Use new functionality once available

### 12.3 Example Enhancement: API-Friendly Initializers (Critical)

Currently RZFlight models are designed for database loading (`FMResultSet`). For API responses, we need memberwise initializers:

```swift
// Proposed addition to RZFlight.Airport
extension Airport {
    /// Initialize from API-style data
    public init(
        icao: String,
        name: String,
        city: String = "",
        country: String = "",
        latitude: Double,
        longitude: Double,
        elevation_ft: Int = 0,
        type: AirportType = .none,
        continent: Continent = .none,
        isoRegion: String? = nil,
        iataCode: String? = nil,
        runways: [Runway] = [],
        procedures: [Procedure] = [],
        aipEntries: [AIPEntry] = []
    ) {
        self.icao = icao
        self.name = name
        self.city = city
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.elevation_ft = elevation_ft
        self.type = type
        self.continent = continent
        self.isoRegion = isoRegion
        self.iataCode = iataCode
        self.runways = runways
        self.procedures = procedures
        self.aipEntries = aipEntries
        // ... set remaining properties to defaults
    }
}

// Proposed addition to RZFlight.Runway
extension Runway {
    public init(
        length_ft: Int,
        width_ft: Int = 0,
        surface: String = "",
        lighted: Bool = false,
        closed: Bool = false,
        le: RunwayEnd,
        he: RunwayEnd
    ) {
        self.length_ft = length_ft
        self.width_ft = width_ft
        self.surface = surface
        self.lighted = lighted
        self.closed = closed
        self.le = le
        self.he = he
    }
}
```

### 12.4 Example Enhancement: Fuel Filtering

```swift
// Proposed addition to KnownAirports
extension KnownAirports {
    /// Get airports with AVGAS fuel available
    func airportsWithAvgas() -> [Airport] {
        // Query airports where AIP entry indicates AVGAS
        // Similar to Python: filter_by_aip_field("fuel_types", "AVGAS")
    }
    
    /// Get airports with Jet-A fuel available
    func airportsWithJetA() -> [Airport] {
        // Query airports where AIP entry indicates Jet-A
    }
}

// Proposed addition to Array<Airport> extension
extension Array where Element == Airport {
    func withAvgas() -> [Airport] {
        return self.filter { airport in
            airport.aipEntries.contains { $0.effectiveFieldName == "fuel_types" && $0.effectiveValue.contains("AVGAS") }
        }
    }
}
```

---

## Appendix A: API Endpoints

```
GET  /api/airports?country=&limit=&...     List airports with filters
GET  /api/airports/{icao}                   Airport detail
GET  /api/airports/{icao}/procedures        Airport procedures
GET  /api/airports/{icao}/runways           Airport runways
GET  /api/airports/{icao}/aip-entries       AIP entries
GET  /api/airports/search/{query}           Search airports
POST /api/airports/route                    Route search
POST /api/airports/locate                   Location search
GET  /api/filters/all                       Filter metadata
GET  /api/rules/{country}                   Country rules
POST /api/aviation-agent/chat/stream        Chatbot (SSE)
GET  /api/sync/version                      Database version
GET  /api/sync/delta?from={version}         Delta update
```

---

## Appendix B: Related Documents

- `designs/UI_FILTER_STATE_DESIGN.md` - Web state management
- `designs/CHATBOT_WEBUI_DESIGN.md` - Chatbot architecture
- `designs/GA_FRIENDLINESS_DESIGN.md` - GA friendliness features

