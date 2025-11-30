# RZFlight Enhancement Request: API JSON Compatibility

## TL;DR

RZFlight models are already `Codable` - we just need to align the `CodingKeys` with the API's JSON keys so we can decode directly without any adapters.

## Current State

RZFlight already has:
- ✅ `Airport: Codable` with custom `init(from decoder:)`
- ✅ `Runway: Codable`
- ✅ `Procedure: Codable`
- ✅ `AIPEntry: Codable`

**Problem:** The JSON keys from the Python API don't match RZFlight's CodingKeys.

## Key Mapping Needed

### Airport

| RZFlight Key | API JSON Key | Notes |
|--------------|--------------|-------|
| `icao` | `ident` | Primary identifier |
| `city` | `municipality` | City name |
| `country` | `iso_country` | ISO country code |
| `latitude` | `latitude_deg` | Coordinates |
| `longitude` | `longitude_deg` | Coordinates |
| `isoRegion` | `iso_region` | With snake_case conversion |
| `elevation_ft` | `elevation_ft` | ✅ Already matches |
| `type` | `type` | ✅ Already matches |
| `name` | `name` | ✅ Already matches |

### Runway

| RZFlight Key | API JSON Key |
|--------------|--------------|
| `le.ident` | `le_ident` |
| `he.ident` | `he_ident` |
| `length_ft` | `length_ft` | ✅ Matches |
| `width_ft` | `width_ft` | ✅ Matches |
| `surface` | `surface` | ✅ Matches |
| `lighted` | `lighted` | ✅ Matches |
| `closed` | `closed` | ✅ Matches |
| `le.latitude` | `le_latitude_deg` |
| `le.longitude` | `le_longitude_deg` |
| `le.headingTrue` | `le_heading_degT` |

### Procedure

| RZFlight Key | API JSON Key |
|--------------|--------------|
| `name` | `name` | ✅ Matches |
| `procedureType` | `procedure_type` | snake_case |
| `approachType` | `approach_type` | snake_case |
| `runwayNumber` | `runway_number` | snake_case |
| `runwayLetter` | `runway_letter` | snake_case |
| `runwayIdent` | `runway_ident` | snake_case |

### AIPEntry

| RZFlight Key | API JSON Key |
|--------------|--------------|
| `ident` | `ident` | ✅ Matches |
| `section` | `section` | ✅ Matches |
| `field` | `field` | ✅ Matches |
| `value` | `value` | ✅ Matches |
| `standardField` | needs lookup from `std_field_id` |
| `mappingScore` | `mapping_score` | snake_case |
| `altField` | `alt_field` | snake_case |
| `altValue` | `alt_value` | snake_case |

## Proposed Solution

Update `CodingKeys` in each model to support API JSON keys:

### Airport.swift

```swift
enum CodingKeys: String, CodingKey {
    case name
    case city = "municipality"           // API uses municipality
    case country = "iso_country"         // API uses iso_country
    case isoRegion = "iso_region"
    case scheduledService = "scheduled_service"
    case gpsCode = "gps_code"
    case iataCode = "iata_code"
    case localCode = "local_code"
    case homeLink = "home_link"
    case wikipediaLink = "wikipedia_link"
    case keywords
    case sources
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case elevation_ft
    case icao = "ident"                  // API uses ident
    case type
    case continent
    case latitude = "latitude_deg"       // API uses latitude_deg
    case longitude = "longitude_deg"     // API uses longitude_deg
    case runways
    case procedures
    case aipEntries = "aip_entries"
}
```

### Alternative: Support Both Formats

If you want to support both the current format AND the API format, use a custom decoder that tries both keys:

```swift
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    
    // Support both "icao" and "ident"
    self.icao = try container.decodeIfPresent(String.self, forKey: .icao) 
        ?? try container.decodeIfPresent(String.self, forKey: .ident) 
        ?? ""
    
    // Support both "city" and "municipality"
    self.city = try container.decodeIfPresent(String.self, forKey: .city)
        ?? try container.decodeIfPresent(String.self, forKey: .municipality)
        ?? ""
    
    // ... etc
}

enum CodingKeys: String, CodingKey {
    case icao, ident                    // Both supported
    case city, municipality             // Both supported
    case country, iso_country           // Both supported
    case latitude, latitude_deg         // Both supported
    case longitude, longitude_deg       // Both supported
    // ... etc
}
```

## iOS App Usage (After Fix)

Once CodingKeys are aligned, the iOS app can decode directly:

```swift
// BEFORE (with adapters - complex)
let apiResponse: [APIAirportSummary] = try await apiClient.get(endpoint)
let airports = apiResponse.map { APIAirportAdapter.toRZFlight($0) }

// AFTER (direct decode - simple!)
let airports: [Airport] = try await apiClient.get(endpoint)
```

**No more:**
- `APIAirportModels.swift` (600+ lines)
- `APIAirportAdapter.swift`
- Manual property mapping

## JSONDecoder Configuration

The iOS app will use:

```swift
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase  // Handles most cases
decoder.dateDecodingStrategy = .iso8601              // For dates
```

## Testing

Please verify:
1. Decode from API JSON (snake_case keys)
2. Decode from existing JSON (if any uses current format)
3. Encode to JSON (for caching)
4. All computed properties still work after decode

## Priority

**High** - This simplifies the entire Phase 4 (Online Integration) significantly.

## Summary

| Before | After |
|--------|-------|
| API models + Adapters | Direct decode to RZFlight |
| ~800 lines of code | ~20 lines (CodingKeys update) |
| Manual mapping | Automatic |
| Potential bugs | Type-safe |

The models are already `Codable` - we just need the keys to match! 🎉
