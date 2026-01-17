# FlyFun EuroAIP App

An iOS aviation planning assistant for European general aviation pilots.

## Features

- **Airport Search & Discovery**: Find airports by ICAO code, name, city, or location
- **Route Planning**: Find airports along flight routes
- **Rules & Regulations**: Access country-specific aviation rules
- **Border Crossing**: Find airports with customs/immigration facilities
- **AI Chat Assistant**: Natural language queries about airports and procedures
- **Apple Sign-In**: Mandatory authentication with Sign in with Apple
- **Online/Offline Mode**: Full functionality with on-device AI or cloud API

## Authentication

The app requires **Sign in with Apple** for authentication. Users must sign in before accessing the app.

### Flow
1. App launches → `LandingSignInView` displayed
2. User taps "Sign in with Apple"
3. Apple handles authentication (Face ID/Touch ID)
4. App exchanges token with backend
5. User info stored in Keychain
6. Main app view displayed

### Sign Out
Sign out is available in: **Filters Panel → Sign Out** (red button at bottom)

### Key Files
- `AuthenticationService.swift` - Authentication logic & Keychain storage
- `LandingSignInView.swift` - Sign-in screen with branding
- `AccountView.swift` - User account management

## Offline Mode

The app supports full offline functionality using on-device AI inference.

### Framework

**MediaPipe LLM Inference SDK** (via CocoaPods)
- `MediaPipeTasksGenAI` - Core GenAI inference
- `MediaPipeTasksGenAIC` - C bindings for LLM inference

### Model

**Qwen 2.5 1.5B Instruct** (Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task)
- Optimised for mobile devices
- ~1.5GB model file (quantized to 8-bit)
- Supports tool calling for structured queries
- Minimum RAM: 3GB

**Download:** Contact maintainer for model download URL and API key.

### Offline Tools

The offline mode supports these tools via `LocalToolDispatcher`:

| Tool | Description |
|------|-------------|
| `search_airports` | Search by ICAO, name, or city |
| `get_airport_details` | Get detailed airport information |
| `find_airports_near_route` | Find airports along a flight route |
| `find_airports_near_location` | Find airports near a location with optional notification filter |
| `find_airports_by_notification` | Find airports by notification requirements |
| `get_border_crossing_airports` | Get customs/border crossing airports |
| `list_rules_for_country` | Get aviation rules for a country |
| `compare_rules_between_countries` | Compare rules between two countries |

### Offline Databases

- **airports.db** - Airport data (via RZFlight library)
- **ga_notifications.db** - GA notification requirements (hours notice, operating hours)
- **rules.json** - Country-specific aviation rules
- **european_cities.db** - European city geocoding data (from GeoNames)

### Offline Geocoding

The app includes offline geocoding capability for resolving city/town names to coordinates.

#### Architecture

```
Services/Offline/
└── OfflineGeocoder.swift    # SQLite-based city geocoding
```

#### Data Source

**european_cities.db** - SQLite database derived from [GeoNames](https://www.geonames.org/)
- Contains European cities with population > 1,000
- Fields: `name`, `latitude`, `longitude`, `country_code`, `population`, `alternate_names`

#### How It Works

1. **Exact match** (case-insensitive) - Fastest, prioritizes exact city name
2. **Prefix match** - Fallback for partial names (e.g., "Lond" → "London")
3. **Alternate names** - Fallback for localized spellings (e.g., "München" → "Munich")

Results are sorted by population (largest first) to prioritize major cities.

#### Usage

The `OfflineGeocoder` is used by `LocalToolDispatcher.findAirportsNearLocation()`:

```swift
// Query: "Find airports near London"
if let result = OfflineGeocoder.shared.geocode(query: "London") {
    // result.coordinate = (51.5074, -0.1278)
    // result.countryCode = "GB"
    // Now search airports within radius of these coordinates
}
```

#### SQLite String Binding

Uses `NSString.utf8String` for proper memory management with SQLite C API:

```swift
let nsStr = queryString as NSString
let cStr = nsStr.utf8String!
sqlite3_bind_text(stmt, 1, cStr, -1, nil)
```

### Offline Maps

The app supports offline map tiles using a custom `MKTileOverlay` implementation with local caching.

#### Architecture

```
Services/Offline/
├── OfflineTileManager.swift    # Downloads & manages tile cache
├── CachedTileOverlay.swift     # Custom MKTileOverlay with caching

UserInterface/Views/
├── Map/OfflineMapView.swift    # UIViewRepresentable for MKMapView
└── Settings/OfflineMapsView.swift  # UI for managing downloads
```

#### How It Works

1. **Tile Source**: OpenStreetMap tiles (`https://tile.openstreetmap.org/{z}/{x}/{y}.png`)

2. **Caching Strategy**:
   - Tiles cached to `Documents/MapTiles/{z}/{x}/{y}.png`
   - Pre-defined European regions available for bulk download
   - Tiles also cached as you browse

3. **Offline Mode Behavior**:
   - When offline: `CachedTileOverlay.offlineOnly = true`
   - Only serves tiles from local cache
   - No network requests for missing tiles (shows blank)
   - When online: Falls back to network for uncached tiles

4. **Pre-defined Regions**:
   | Region | Coverage | Est. Size |
   |--------|----------|-----------|
   | UK & Ireland | 49-61°N, 11°W-2°E | ~50 MB |
   | Germany | 47-55°N, 5-15°E | ~40 MB |
   | France | 41-51°N, 6°W-10°E | ~45 MB |
   | Western Europe | 35-55°N, 10°W-5°E | ~80 MB |
   | Central Europe | 45-55°N, 5-20°E | ~60 MB |
   | Northern Europe | 54-71°N, 4-31°E | ~50 MB |
   | Southern Europe | 35-45°N, 10°W-20°E | ~55 MB |

#### Usage

1. **Download Tiles**: Chat → Map icon (🗺️) → Select regions
2. **Toggle Offline Mode**: Chat → Airplane icon
3. **View Offline Map**: Map tab shows cached OSM tiles with "Offline Map" badge

#### Code Flow

```
OfflineMapView (UIViewRepresentable)
    └── MKMapView with CachedTileOverlay
            │
            ├── loadTile(at:) → Check local cache
            │       │
            │       ├── Cached? → Return data
            │       └── Not cached + online? → Fetch & cache
            │
            └── rendererFor(overlay:) → MKTileOverlayRenderer
```

### Tool Replication from Web Version

The offline tools replicate the server-side API functionality:

**Web API** → **LocalToolDispatcher**

| Web Endpoint | Offline Tool | Data Source |
|--------------|--------------|-------------|
| `/api/airports/search` | `search_airports` | RZFlight KnownAirports |
| `/api/airports/{icao}` | `get_airport_details` | RZFlight airportWithExtendedData |
| `/api/airports/near-route` | `find_airports_near_route` | RZFlight airportsNearRoute |
| `/api/airports/near-location` | `find_airports_near_location` | RZFlight nearest + SQLite notifications |
| `/api/airports/by-notification` | `find_airports_by_notification` | SQLite ga_notifications.db |
| `/api/airports/border-crossing` | `get_border_crossing_airports` | RZFlight airportsWithBorderCrossing |
| `/api/rules/{country}` | `list_rules_for_country` | rules.json |
| `/api/rules/compare` | `compare_rules_between_countries` | rules.json |

**Key Differences:**
- Web uses PostgreSQL; offline uses SQLite + RZFlight KDTree
- Notification data is bundled from `ga_notifications.db` (synced from Android assets)
- Tool dispatch uses JSON-based tool calling with LLM instead of function calling API

## Architecture

```
App/
├── Services/Offline/
│   ├── OfflineChatbotService.swift  # Main offline chat orchestration
│   ├── InferenceEngine.swift        # MediaPipe LLM wrapper
│   ├── LocalToolDispatcher.swift    # Tool execution
│   └── ModelManager.swift           # Model file management
├── Data/DataSources/
│   └── LocalAirportDataSource.swift # SQLite airport queries
└── State/Domains/
    └── ChatDomain.swift             # Chat state management
```

## Setup

### Prerequisites
- Xcode 15+
- iOS 17+
- CocoaPods

### Installation

```bash
cd app
pod install
open FlyFunEuroAIP.xcworkspace
```

### Code Signing Setup

Copy the sample config and add your Apple Developer Team ID:

```bash
cp Local.xcconfig.sample Local.xcconfig
```

Edit `Local.xcconfig` and set your Team ID:
```
DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
```

Find your Team ID at [Apple Developer Account](https://developer.apple.com/account) → Membership Details.

### Model Setup

1. Download `gemma-3n-e2b.task` model file
2. Copy to app container Documents/models/ directory
3. Or use `xcrun simctl` for simulator:
   ```bash
   xcrun simctl get_app_container booted net.ro-z.FlyFunEuroAIP data
   # Copy model to that path/Documents/models/
   ```

## Configuration

Create `secrets.json` from the sample:
```bash
cp FlyFunEuroAIP/secrets.json.sample FlyFunEuroAIP/secrets.json
```

## License

Copyright © Ro-Z.net
