# RZFlight Enhancement Request: API-Friendly Initializers

## Context

The FlyFun EuroAIP iOS app (Phase 4: Online Integration) needs to convert API JSON responses into RZFlight models. Currently, RZFlight models only have `FMResultSet` initializers, which makes it impossible to create `Airport`, `Runway`, `Procedure`, and `AIPEntry` instances from API data.

## Problem

When the iOS app receives airport data from the REST API, it needs to convert JSON responses to RZFlight models. The current initializers require `FMResultSet`, which is SQLite-specific and not available for API responses.

**Current situation:**
```swift
// ❌ Can't do this - no API-friendly initializer
let airport = Airport(
    icao: "EGLL",
    name: "London Heathrow",
    latitude: 51.4700,
    longitude: -0.4543,
    // ... other properties
)
```

**Workaround (temporary):**
- Create minimal `Airport` with only location/ICAO
- Lose all other data (runways, procedures, AIP entries)
- Can't properly display airport details from API

## Requested Enhancements

### 1. Airport Initializer

**File:** `Sources/RZFlight/Airport.swift`

Add a public initializer that accepts all airport properties:

```swift
public init(
    icao: String,
    name: String,
    latitude: Double,
    longitude: Double,
    elevationFt: Int = 0,
    type: AirportType = .none,
    continent: Continent = .none,
    country: String = "",
    isoRegion: String? = nil,
    city: String = "",
    scheduledService: String? = nil,
    gpsCode: String? = nil,
    iataCode: String? = nil,
    localCode: String? = nil,
    homeLink: String? = nil,
    wikipediaLink: String? = nil,
    keywords: String? = nil,
    sources: [String] = [],
    runways: [Runway] = [],
    procedures: [Procedure] = [],
    aipEntries: [AIPEntry] = [],
    createdAt: Date? = nil,
    updatedAt: Date? = nil
) {
    self.icao = icao
    self.name = name
    self.latitude = latitude
    self.longitude = longitude
    self.elevation_ft = elevationFt
    self.type = type
    self.continent = continent
    self.country = country
    self.isoRegion = isoRegion
    self.city = city
    self.scheduledService = scheduledService
    self.gpsCode = gpsCode
    self.iataCode = iataCode
    self.localCode = localCode
    self.homeLink = homeLink
    self.wikipediaLink = wikipediaLink
    self.keywords = keywords
    self.sources = sources
    self.runways = runways
    self.procedures = procedures
    self.aipEntries = aipEntries
    self.createdAt = createdAt
    self.updatedAt = updatedAt
}
```

**Usage in iOS app:**
```swift
let airport = Airport(
    icao: api.ident,
    name: api.name ?? "",
    latitude: api.latitudeDeg ?? 0,
    longitude: api.longitudeDeg ?? 0,
    elevationFt: Int(api.elevationFt ?? 0),
    type: AirportType(rawValue: api.type ?? "") ?? .none,
    country: api.isoCountry ?? "",
    city: api.municipality ?? "",
    runways: api.runways.compactMap { APIRunwayAdapter.toRZFlight($0) },
    procedures: api.procedures.compactMap { APIProcedureAdapter.toRZFlight($0) },
    aipEntries: api.aipEntries.compactMap { APIAIPEntryAdapter.toRZFlight($0) }
)
```

### 2. Runway Initializer

**File:** `Sources/RZFlight/Runway.swift`

Add a public initializer for creating runways from API data:

```swift
public init(
    leIdent: String,
    heIdent: String,
    lengthFt: Int? = nil,
    widthFt: Int? = nil,
    surface: String? = nil,
    lighted: Bool? = nil,
    closed: Bool? = nil,
    leLatitude: Double? = nil,
    leLongitude: Double? = nil,
    leElevationFt: Double? = nil,
    leHeadingTrue: Double? = nil,
    leDisplacedThresholdFt: Double? = nil,
    heLatitude: Double? = nil,
    heLongitude: Double? = nil,
    heElevationFt: Double? = nil,
    heHeadingTrue: Double? = nil,
    heDisplacedThresholdFt: Double? = nil
) {
    self.le = RunwayEnd(
        ident: leIdent,
        latitude: leLatitude,
        longitude: leLongitude,
        elevationFt: leElevationFt,
        headingTrue: leHeadingTrue ?? 0,
        displacedThresholdFt: leDisplacedThresholdFt
    )
    self.he = RunwayEnd(
        ident: heIdent,
        latitude: heLatitude,
        longitude: heLongitude,
        elevationFt: heElevationFt,
        headingTrue: heHeadingTrue ?? 0,
        displacedThresholdFt: heDisplacedThresholdFt
    )
    self.length_ft = lengthFt
    self.width_ft = widthFt
    self.surface = surface
    self.lighted = lighted
    self.closed = closed
}
```

**Usage:**
```swift
let runway = Runway(
    leIdent: api.leIdent,
    heIdent: api.heIdent,
    lengthFt: api.lengthFt,
    widthFt: api.widthFt,
    surface: api.surface,
    lighted: api.lighted,
    closed: api.closed,
    leLatitude: api.leLatitudeDeg,
    leLongitude: api.leLongitudeDeg,
    leElevationFt: api.leElevationFt.map { Double($0) },
    leHeadingTrue: api.leHeadingDegT,
    leDisplacedThresholdFt: api.leDisplacedThresholdFt.map { Double($0) },
    heLatitude: api.heLatitudeDeg,
    heLongitude: api.heLongitudeDeg,
    heElevationFt: api.heElevationFt.map { Double($0) },
    heHeadingTrue: api.heHeadingDegT,
    heDisplacedThresholdFt: api.heDisplacedThresholdFt.map { Double($0) }
)
```

### 3. Procedure Initializer

**File:** `Sources/RZFlight/Procedure.swift`

Add a public initializer:

```swift
public init(
    name: String,
    procedureType: ProcedureType,
    approachType: ApproachType? = nil,
    runwayNumber: String? = nil,
    runwayLetter: String? = nil,
    runwayIdent: String? = nil,
    source: String? = nil,
    authority: String? = nil,
    rawName: String? = nil,
    data: [String: Any]? = nil
) {
    self.name = name
    self.procedureType = procedureType
    self.approachType = approachType
    self.runwayNumber = runwayNumber
    self.runwayLetter = runwayLetter
    self.runwayIdent = runwayIdent
    self.source = source
    self.authority = authority
    self.rawName = rawName
    self.data = data
}
```

**Note:** `precisionCategory` should be computed from `approachType` (existing logic).

### 4. AIPEntry Initializer

**File:** `Sources/RZFlight/AIPEntry.swift`

Add a public initializer:

```swift
public init(
    ident: String,
    section: Section,
    field: String,
    value: String,
    standardField: AIPField? = nil,
    mappingScore: Double? = nil,
    altField: String? = nil,
    altValue: String? = nil,
    source: String? = nil,
    createdAt: Date? = nil
) {
    self.ident = ident
    self.section = section
    self.field = field
    self.value = value
    self.standardField = standardField
    self.mappingScore = mappingScore
    self.altField = altField
    self.altValue = altValue
    self.source = source
    // Note: createdAt might need to be parsed from ISO8601 string
}
```

**Note:** If `standardField` is provided via `stdFieldId`, look it up using `AIPFieldCatalog.field(for:)`.

## Additional Considerations

### Date Parsing

If the API returns ISO8601 date strings, consider adding a convenience initializer that accepts strings:

```swift
// In Airport
public init(
    // ... other params
    createdAtString: String? = nil,
    updatedAtString: String? = nil
) {
    // ... set other properties
    if let created = createdAtString {
        self.createdAt = ISO8601DateFormatter().date(from: created)
    }
    if let updated = updatedAtString {
        self.updatedAt = ISO8601DateFormatter().date(from: updated)
    }
}
```

### Backward Compatibility

- Keep existing `FMResultSet` initializers (they're still needed for local DB access)
- New initializers should be additive, not replacements
- Ensure all computed properties still work correctly

### Testing

Please add unit tests for the new initializers:
- Test with all properties set
- Test with minimal properties (defaults)
- Test with nil optionals
- Verify computed properties (e.g., `precisionCategory` for procedures)

## Priority

**High** - This blocks Phase 4 (Online Integration) completion. The iOS app can work with minimal data, but full feature parity requires these initializers.

## Timeline

The iOS app is currently in Phase 4. We can work around this temporarily, but would like to have these initializers available before Phase 5 (Online Chatbot) to ensure full API integration.

## Example: Complete Conversion

With these initializers, the iOS app adapter would look like:

```swift
// App/Data/Adapters/APIAirportAdapter.swift

enum APIAirportAdapter {
    static func toRZFlight(_ api: APIAirportDetail) -> Airport {
        return Airport(
            icao: api.ident,
            name: api.name ?? "",
            latitude: api.latitudeDeg ?? 0,
            longitude: api.longitudeDeg ?? 0,
            elevationFt: Int(api.elevationFt ?? 0),
            type: AirportType(rawValue: api.type ?? "") ?? .none,
            continent: Continent(rawValue: api.continent ?? "") ?? .none,
            country: api.isoCountry ?? "",
            isoRegion: api.isoRegion,
            city: api.municipality ?? "",
            scheduledService: api.scheduledService,
            gpsCode: api.gpsCode,
            iataCode: api.iataCode,
            localCode: api.localCode,
            homeLink: api.homeLink,
            wikipediaLink: api.wikipediaLink,
            keywords: api.keywords,
            sources: api.sources,
            runways: api.runways.compactMap { APIRunwayAdapter.toRZFlight($0) },
            procedures: api.procedures.compactMap { APIProcedureAdapter.toRZFlight($0) },
            aipEntries: api.aipEntries.compactMap { APIAIPEntryAdapter.toRZFlight($0) },
            createdAtString: api.createdAt,
            updatedAtString: api.updatedAt
        )
    }
}
```

## Questions / Clarifications

1. **Date handling:** Should we use `Date?` or ISO8601 strings in the initializers? (Prefer `Date?` with optional string parsing helper)

2. **AIPField lookup:** Should the initializer handle `stdFieldId` → `AIPField` lookup automatically, or should the caller do it?

3. **Procedure data:** The `data` field is `[String: Any]` - should this be `Codable` or remain as `Any`? (Current implementation uses `Any`)

4. **Backward compatibility:** Are there any breaking changes we should be aware of?

## Related Files in RZFlight

- `Sources/RZFlight/Airport.swift` - Add Airport initializer
- `Sources/RZFlight/Runway.swift` - Add Runway initializer  
- `Sources/RZFlight/Procedure.swift` - Add Procedure initializer
- `Sources/RZFlight/AIPEntry.swift` - Add AIPEntry initializer

## Contact

If you have questions about the iOS app's usage patterns or need clarification on any requirements, please reach out!

---

**Thank you for considering this enhancement!** 🙏

