# FlyFun EuroAIP iOS App - Implementation Plan

## Overview

This document provides a detailed implementation roadmap for the FlyFun EuroAIP iOS/macOS app. It breaks down the design into actionable phases with specific tasks, dependencies, and deliverables.

**Reference:** `designs/IOS_APP_DESIGN.md` for architecture and design decisions.

---

## ⚠️ Critical Rule: RZFlight Model Reuse

**DO NOT create duplicate models.** Use [RZFlight](https://github.com/roznet/rzflight) types directly:

```swift
// ✅ CORRECT
import RZFlight
let airports: [Airport]  // RZFlight.Airport
let runways: [Runway]    // RZFlight.Runway

// ❌ WRONG - Don't create app-level duplicates
struct AppAirport { ... }  // NO!
```

**If functionality is missing:**
1. Check if it exists in `euro_aip` (Python)
2. If yes, propose enhancement to RZFlight, not the app
3. Track in `designs/IOS_APP_DESIGN.md` Section 12

---

## Current State Assessment

### What Exists (Proof of Concept)

| Component | Status | Notes |
|-----------|--------|-------|
| Project setup | ✅ | Xcode project, targets, dependencies |
| RZFlight integration | ✅ | Package linked, KnownAirports working |
| AppModel | ✅ | Async initialization, database loading |
| AirportMapViewModel | ⚠️ | Basic, filters not functional |
| ContentView | ✅ | Adaptive layout detection |
| RegularLayout | ✅ | iPad/Mac side panel |
| CompactLayout | ✅ | iPhone overlay layout |
| SearchBar | ✅ | Basic search UI |
| FilterPanel | ⚠️ | UI only, not connected |
| SearchResultsList | ✅ | Basic results display |
| UI Airport struct | ⚠️ | Duplicate! Should use RZFlight.Airport |

### What Needs to Be Built

1. **Remove duplicate Airport model** - Use RZFlight.Airport directly
2. **Data Layer**: Repository pattern wrapping KnownAirports, remote data source
3. **FilterConfig**: App-specific filter state with apply() using RZFlight extensions
4. **Filters**: Connect FilterPanel to FilterConfig → KnownAirports filtering
5. **Details View**: Airport detail using airport.runways, procedures, aipEntries
6. **Route Search**: Use KnownAirports.airportsNearRoute()
7. **Chatbot**: Online (SSE) and offline (on-device LLM)
8. **Sync**: Database updates, cache management
9. **UI Polish**: Animations, legends, better markers

### Immediate Cleanup Required

The current PoC has a duplicate `Airport` struct in `AirportMapViewModel.swift`:

```swift
// ❌ CURRENT (wrong) - duplicates RZFlight.Airport
struct Airport: Identifiable {
    let name: String
    let icao: String
    let coordinate: CLLocationCoordinate2D
}

// ✅ SHOULD BE - use RZFlight directly
import RZFlight
// RZFlight.Airport already has all these + much more
```

---

## Phase 1: Foundation - Data Layer & RZFlight Integration

**Duration:** 2-3 weeks  
**Goal:** Solid data foundation using RZFlight models with offline/online abstraction

### 1.1 RZFlight Integration (NO NEW MODELS)

**Rule:** Use `RZFlight.Airport`, `RZFlight.Runway`, `RZFlight.Procedure`, `RZFlight.AIPEntry` directly.

**Tasks:**
- [ ] Verify RZFlight package is properly linked
- [ ] Ensure `KnownAirports` initializes correctly with bundled database
- [ ] Test all existing `KnownAirports` methods work as expected
- [ ] Document any missing functionality (for RZFlight enhancement)

**RZFlight provides (DO NOT DUPLICATE):**
- `Airport` with runways[], procedures[], aipEntries[]
- `Runway` with length_ft, surface, isHardSurface
- `Procedure` with procedureType, approachType, precisionCategory
- `AIPEntry` with section, field, value, standardField
- `KnownAirports` for all queries

### 1.2 App-Specific Types (Only What's Missing)

**File:** `App/Models/AppTypes.swift`

- [ ] **FilterConfig.swift** - UI filter configuration (not in RZFlight)
  ```swift
  struct FilterConfig: Codable, Equatable {
      var country: String?
      var hasProcedures: Bool?
      var hasHardRunway: Bool?
      var pointOfEntry: Bool?
      var minRunwayLengthFt: Int?
      // ...
      
      /// Apply using RZFlight Array extensions
      func apply(to airports: [Airport], db: FMDatabase) -> [Airport]
  }
  ```

- [ ] **RouteResult.swift** - Route search result wrapper
- [ ] **MapHighlight.swift** - UI visualization
- [ ] **ConnectivityMode.swift** - Network state

**Deliverables:**
- Minimal app-specific types only
- FilterConfig with apply() using RZFlight extensions
- Unit tests for filter application

### 1.2 Repository Protocol

**File:** `App/Data/Repositories/AirportRepository.swift`

- [ ] Define `AirportRepositoryProtocol`
- [ ] Define all required methods
- [ ] Create async/throws signatures

### 1.3 Local Data Source (Using KnownAirports)

**File:** `App/Data/DataSources/LocalAirportDataSource.swift`

- [ ] Implement `AirportRepositoryProtocol`
- [ ] Wrap `KnownAirports` - DO NOT duplicate its logic
- [ ] Use `FilterConfig.apply()` with RZFlight Array extensions
- [ ] Return `RZFlight.Airport` directly (no mapping needed)

**Tasks:**
- [ ] Initialize `KnownAirports` from bundled database
- [ ] Implement `getAirports()` using KnownAirports + filter extensions
- [ ] Implement `searchAirports()` using `knownAirports.matching()`
- [ ] Implement `getAirportDetail()` using `knownAirports.airportWithExtendedData()`
- [ ] Implement `getAirportsNearRoute()` using `knownAirports.airportsNearRoute()`
- [ ] Implement `getAirportsNearLocation()` using `knownAirports.nearest(coord:count:)`

**Key Pattern:**
```swift
func getAirports(filters: FilterConfig, limit: Int) async throws -> [Airport] {
    // Use KnownAirports directly - returns RZFlight.Airport
    var airports = knownAirports.airportsWithBorderCrossing()  // or all airports
    
    // Apply filters using RZFlight Array extensions
    airports = filters.apply(to: airports, db: db)
    
    return Array(airports.prefix(limit))
}
```

### 1.4 Connectivity Monitor

**File:** `App/Services/ConnectivityMonitor.swift`

- [ ] Create `ConnectivityMonitor` using NWPathMonitor
- [ ] Publish connection state
- [ ] Distinguish WiFi vs cellular

```swift
final class ConnectivityMonitor: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var connectionType: ConnectionType = .none
    
    enum ConnectionType {
        case none, wifi, cellular
    }
}
```

### 1.5 Filter Engine

**File:** `App/Data/Filtering/FilterEngine.swift`

- [ ] Port filter logic from web app
- [ ] Client-side filtering for local data
- [ ] Filter validation

---

## Phase 2: ViewModel & Filter Enhancement

**Duration:** 2 weeks  
**Goal:** Functional filters and improved state management

### 2.1 Enhanced AirportMapViewModel

**File:** `UserInterface/ViewModels/AirportMapViewModel.swift`

- [ ] Add complete filter state
- [ ] Implement filter application
- [ ] Add route state
- [ ] Add legend mode
- [ ] Add highlights support
- [ ] Add error handling

**State to add:**
```swift
@Published var filters: FilterConfig = .default
@Published var legendMode: LegendMode = .airportType
@Published var highlights: [String: MapHighlight] = [:]
@Published var activeRoute: RouteVisualization?
@Published var availableCountries: [String] = []
@Published var isLoading: Bool = false
@Published var error: AppError?
```

**Actions to implement:**
```swift
func loadAirports() async
func search(query: String) async
func applyFilters() async
func searchRoute(from: String, to: String) async
func clearRoute()
func resetFilters()
```

### 2.2 Airport Detail ViewModel

**File:** `UserInterface/ViewModels/AirportDetailViewModel.swift`

- [ ] Create detail view model
- [ ] Load runways, procedures, AIP entries
- [ ] Handle loading states
- [ ] Support offline/online data

### 2.3 Filter Binding Helpers

**File:** `UserInterface/Helpers/FilterBindings.swift`

- [ ] Create binding helpers for optional booleans
- [ ] Create reusable filter toggle components

---

## Phase 3: UI Implementation

**Duration:** 2-3 weeks  
**Goal:** Complete, polished UI for all platforms

### 3.1 Map Enhancements

**File:** `UserInterface/Views/Map/`

- [ ] **AirportMapView.swift** - Enhanced map view
  - [ ] Legend mode-based marker colors
  - [ ] Route polyline rendering
  - [ ] Highlight circles
  - [ ] Annotation clustering (for large datasets)

- [ ] **AirportMarker.swift** - Custom marker view
  ```swift
  struct AirportMarker: View {
      let airport: Airport
      let legendMode: LegendMode
      
      var body: some View {
          ZStack {
              Circle()
                  .fill(markerColor)
                  .frame(width: 32, height: 32)
              Text(airport.icao)
                  .font(.caption2.bold())
                  .foregroundStyle(.white)
          }
      }
      
      var markerColor: Color {
          switch legendMode {
          case .airportType: return airportTypeColor
          case .procedurePrecision: return procedureColor
          case .runwayLength: return runwayLengthColor
          case .country: return countryColor
          }
      }
  }
  ```

- [ ] **MapLegend.swift** - Legend overlay

### 3.2 Filter Panel

**File:** `UserInterface/Views/Filters/`

- [ ] **FilterPanel.swift** - Complete filter UI
  - [ ] Country picker
  - [ ] Boolean toggles (border crossing, procedures, etc.)
  - [ ] Fuel toggles
  - [ ] Runway length stepper/slider
  - [ ] Reset button
  - [ ] Apply button (for API mode)

- [ ] **FilterChips.swift** - Active filter chips display

### 3.3 Airport Detail View

**File:** `UserInterface/Views/Detail/`

- [ ] **AirportDetailView.swift** - Main detail view
  - [ ] Header with name, ICAO, location
  - [ ] Tab view (Info, Runways, Procedures, AIP)

- [ ] **AirportInfoTab.swift** - Basic info tab
- [ ] **RunwaysTab.swift** - Runways list
- [ ] **ProceduresTab.swift** - Procedures grouped by type
- [ ] **AIPEntriesTab.swift** - AIP entries by section

### 3.4 Search Enhancement

**File:** `UserInterface/Views/Search/`

- [ ] **SearchBar.swift** - Update with route detection
- [ ] **SearchResultsView.swift** - Enhanced results
  - [ ] Group by type (exact match, route, location)
  - [ ] Show distance for route results

### 3.5 Layout Refinement

- [ ] **RegularLayout.swift** - Refine iPad/Mac layout
  - [ ] Proper NavigationSplitView
  - [ ] Sidebar with search + results
  - [ ] Inspector with filters/details

- [ ] **CompactLayout.swift** - Refine iPhone layout
  - [ ] Bottom sheet with detents
  - [ ] Floating search bar
  - [ ] Tab bar for switching content

### 3.6 Components

**File:** `UserInterface/Views/Components/`

- [ ] **ConnectivityBanner.swift** - Offline indicator
- [ ] **LoadingOverlay.swift** - Loading state
- [ ] **ErrorBanner.swift** - Error display
- [ ] **EmptyStateView.swift** - No results state

---

## Phase 4: Online Integration

**Duration:** 2 weeks  
**Goal:** Full API integration with fallback, converting all responses to RZFlight models

### 4.1 API Client

**File:** `App/Networking/`

- [ ] **APIClient.swift** - Base networking
  ```swift
  final class APIClient {
      let baseURL: URL
      let session: URLSession
      
      func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
      func streamSSE(_ endpoint: Endpoint) -> AsyncThrowingStream<SSEEvent, Error>
  }
  ```

- [ ] **Endpoint.swift** - Endpoint definitions
- [ ] **APIError.swift** - Error types

### 4.2 API Response Models (Internal)

**File:** `App/Networking/APIModels/`

These are **internal** models matching API JSON structure. Never exposed outside the adapter.

- [ ] **APIAirport.swift** - API airport response
- [ ] **APIRunway.swift** - API runway response
- [ ] **APIProcedure.swift** - API procedure response
- [ ] **APIAIPEntry.swift** - API AIP entry response
- [ ] **APIResponses.swift** - List/detail response wrappers

### 4.3 API → RZFlight Adapters

**File:** `App/Data/Adapters/`

**Critical:** All API responses MUST be converted to RZFlight models.

- [ ] **APIAirportAdapter.swift** - Convert APIAirport → RZFlight.Airport
  ```swift
  enum APIAirportAdapter {
      static func toRZFlight(_ api: APIAirport) -> Airport
      static func toRZFlightWithExtendedData(_ response: APIAirportDetailResponse) -> Airport
  }
  ```

- [ ] **APIRunwayAdapter.swift** - Convert APIRunway → RZFlight.Runway
- [ ] **APIProcedureAdapter.swift** - Convert APIProcedure → RZFlight.Procedure
- [ ] **APIAIPEntryAdapter.swift** - Convert APIAIPEntry → RZFlight.AIPEntry

**Pattern:**
```swift
// ✅ CORRECT: API response → Adapter → RZFlight model
func getAirports() async throws -> [Airport] {  // Returns RZFlight.Airport
    let response: APIAirportListResponse = try await apiClient.request(endpoint)
    return response.airports.map { APIAirportAdapter.toRZFlight($0) }
}

// ❌ WRONG: Exposing API models directly
func getAirports() async throws -> [APIAirport] {  // NO!
    return try await apiClient.request(endpoint)
}
```

### 4.4 RZFlight Initializer Proposals

If RZFlight models don't have convenient initializers for API data:

- [ ] Propose `Airport.init(icao:name:city:country:latitude:longitude:...)` to RZFlight
- [ ] Propose `Runway.init(length_ft:width_ft:surface:lighted:closed:le:he:)` to RZFlight
- [ ] Temporary workaround: Use internal extension until PR merged

**Temporary Extension (if needed):**
```swift
// App/Extensions/RZFlight+APIInit.swift
extension Airport {
    /// Temporary: API-friendly initializer (propose to RZFlight)
    static func fromAPI(
        icao: String,
        name: String,
        // ... other params
    ) -> Airport {
        // Build using available initializers
    }
}
```

### 4.5 Remote Data Source

**File:** `App/Data/DataSources/RemoteAirportDataSource.swift`

- [ ] Implement `AirportRepositoryProtocol`
- [ ] Use adapters to convert ALL responses to RZFlight models
- [ ] Return `RZFlight.Airport` (same as LocalDataSource)
- [ ] Handle pagination
- [ ] Error mapping

### 4.3 Unified Repository

**File:** `App/Data/Repositories/AirportRepository.swift`

- [ ] Implement strategy pattern for offline/online
- [ ] Add fallback logic
- [ ] Add caching layer
- [ ] Publish connectivity mode

### 4.4 Sync Service

**File:** `App/Services/SyncService.swift`

- [ ] Check for database updates
- [ ] Download new database
- [ ] Apply updates
- [ ] Track sync status

---

## Phase 5: Online Chatbot

**Duration:** 2-3 weeks  
**Goal:** Streaming chatbot with visualizations

### 5.1 Chat Models

**File:** `App/Models/Chat/`

- [ ] **ChatMessage.swift** - Message model
- [ ] **ChatEvent.swift** - Streaming events
- [ ] **VisualizationPayload.swift** - Visualization data

### 5.2 SSE Streaming

**File:** `App/Networking/SSEClient.swift`

- [ ] Implement SSE parsing
- [ ] Handle reconnection
- [ ] Parse event types (plan, thinking, message, ui_payload, done)

### 5.3 Online Chatbot Service

**File:** `App/Services/Chatbot/OnlineChatbotService.swift`

- [ ] Implement `ChatbotService` protocol
- [ ] Send messages via API
- [ ] Stream responses
- [ ] Handle visualizations

### 5.4 Chatbot ViewModel

**File:** `UserInterface/ViewModels/ChatbotViewModel.swift`

- [ ] Manage conversation state
- [ ] Handle streaming updates
- [ ] Apply visualizations to map
- [ ] Track thinking state

### 5.5 Chat UI

**File:** `UserInterface/Views/Chat/`

- [ ] **ChatView.swift** - Main chat view
- [ ] **ChatBubble.swift** - Message bubble
- [ ] **ChatInputBar.swift** - Input with send button
- [ ] **ThinkingIndicator.swift** - Typing/thinking state
- [ ] **VisualizationCard.swift** - Embedded visualization preview

---

## Phase 6: Offline Chatbot

**Duration:** 3-4 weeks  
**Goal:** On-device LLM for offline operation

### 6.1 Research & Selection

- [ ] Evaluate on-device LLM options:
  - Apple Intelligence (iOS 18.1+)
  - Core ML with custom model
  - llama.cpp (MLX on Apple Silicon)
  
- [ ] Determine minimum device requirements
- [ ] Select model size (2B-7B parameters)

### 6.2 On-Device LLM Engine

**File:** `App/Services/LLM/OnDeviceLLMEngine.swift`

- [ ] Implement LLM engine protocol
- [ ] Load model on startup
- [ ] Generate tokens with streaming
- [ ] Handle memory constraints

```swift
protocol OnDeviceLLMEngine {
    var isAvailable: Bool { get }
    func load() async throws
    func generate(prompt: String, maxTokens: Int) -> AsyncStream<String>
    func unload()
}
```

### 6.3 Offline Tool Registry

**File:** `App/Services/Chatbot/OfflineToolRegistry.swift`

- [ ] Define available offline tools
- [ ] Implement tool execution
- [ ] Map to local data source

### 6.4 Offline Chatbot Service

**File:** `App/Services/Chatbot/OfflineChatbotService.swift`

- [ ] Implement `ChatbotService` protocol
- [ ] Simple planning prompt
- [ ] Tool selection and execution
- [ ] Response generation
- [ ] Visualization generation

### 6.5 Chatbot Service Factory

**File:** `App/Services/Chatbot/ChatbotServiceFactory.swift`

- [ ] Create appropriate service based on connectivity
- [ ] Handle graceful degradation
- [ ] Notify user of limitations

---

## Phase 7: Polish & Testing

**Duration:** 2 weeks  
**Goal:** Production-ready quality

### 7.1 Performance

- [ ] Profile and optimize filter queries
- [ ] Lazy loading for large lists
- [ ] Map marker clustering
- [ ] Memory management for LLM

### 7.2 Offline Experience

- [ ] Pre-cache map tiles for Europe
- [ ] Download manager UI
- [ ] Storage management
- [ ] Clear cache option

### 7.3 Error Handling

- [ ] Comprehensive error types
- [ ] User-friendly error messages
- [ ] Retry mechanisms
- [ ] Offline fallback UI

### 7.4 Accessibility

- [ ] VoiceOver labels
- [ ] Dynamic type support
- [ ] Reduce motion support
- [ ] Color contrast

### 7.5 Testing

- [ ] Unit tests for models
- [ ] Unit tests for view models
- [ ] Unit tests for repository
- [ ] UI tests for critical flows
- [ ] Performance tests

### 7.6 App Store Preparation

- [ ] App icons (all sizes)
- [ ] Screenshots for all devices
- [ ] Privacy policy
- [ ] App Store description

---

## File Structure (Target)

**Note:** Core models (Airport, Runway, Procedure, AIPEntry) come from RZFlight package.
Only app-specific types are defined locally.

```
app/FlyFunEuroAIP/
├── App/
│   ├── FlyFunEuroAIPApp.swift
│   ├── AppModel.swift
│   ├── Log.swift
│   ├── Settings.swift
│   │
│   ├── Models/                         # App-specific types ONLY
│   │   ├── FilterConfig.swift          # UI filter state (not in RZFlight)
│   │   ├── RouteResult.swift           # Route query result wrapper
│   │   ├── MapHighlight.swift          # Map visualization
│   │   ├── ConnectivityMode.swift      # Network state
│   │   └── Chat/
│   │       ├── ChatMessage.swift
│   │       ├── ChatEvent.swift
│   │       └── VisualizationPayload.swift
│   │   # NOTE: Airport, Runway, Procedure, AIPEntry are from RZFlight
│   │
│   ├── Data/
│   │   ├── Repositories/
│   │   │   └── AirportRepository.swift  # Wraps KnownAirports + Remote
│   │   ├── DataSources/
│   │   │   ├── LocalAirportDataSource.swift   # Uses KnownAirports
│   │   │   └── RemoteAirportDataSource.swift  # API → RZFlight adapter
│   │   ├── Adapters/                          # API → RZFlight converters
│   │   │   ├── APIAirportAdapter.swift
│   │   │   ├── APIRunwayAdapter.swift
│   │   │   ├── APIProcedureAdapter.swift
│   │   │   └── APIAIPEntryAdapter.swift
│   │   └── Extensions/
│   │       ├── FilterConfig+Apply.swift       # Filter application
│   │       └── RZFlight+APIInit.swift         # Temp: API-friendly inits
│   │
│   ├── Networking/
│   │   ├── APIClient.swift
│   │   ├── Endpoint.swift
│   │   ├── APIError.swift
│   │   ├── SSEClient.swift
│   │   └── APIModels/                         # Internal API response models
│   │       ├── APIAirport.swift               # DO NOT expose
│   │       ├── APIRunway.swift
│   │       ├── APIProcedure.swift
│   │       ├── APIAIPEntry.swift
│   │       └── APIResponses.swift
│   │
│   └── Services/
│       ├── ConnectivityMonitor.swift
│       ├── SyncService.swift
│       ├── CacheManager.swift
│       ├── Chatbot/
│       │   ├── ChatbotService.swift
│       │   ├── OnlineChatbotService.swift
│       │   ├── OfflineChatbotService.swift
│       │   ├── OfflineToolRegistry.swift
│       │   └── ChatbotServiceFactory.swift
│       └── LLM/
│           └── OnDeviceLLMEngine.swift
│
├── UserInterface/
│   ├── ContentView.swift
│   │
│   ├── ViewModels/
│   │   ├── AirportMapViewModel.swift
│   │   ├── AirportDetailViewModel.swift
│   │   ├── ChatbotViewModel.swift
│   │   └── PreviewSamples.swift
│   │
│   ├── Views/
│   │   ├── Layouts/
│   │   │   ├── RegularLayout.swift
│   │   │   └── CompactLayout.swift
│   │   │
│   │   ├── Map/
│   │   │   ├── AirportMapView.swift
│   │   │   ├── AirportMarker.swift
│   │   │   └── MapLegend.swift
│   │   │
│   │   ├── Search/
│   │   │   ├── SearchBar.swift
│   │   │   ├── SearchFieldCompact.swift
│   │   │   └── SearchResultsView.swift
│   │   │
│   │   ├── Filters/
│   │   │   ├── FilterPanel.swift
│   │   │   └── FilterChips.swift
│   │   │
│   │   ├── Detail/
│   │   │   ├── AirportDetailView.swift
│   │   │   ├── AirportInfoTab.swift
│   │   │   ├── RunwaysTab.swift
│   │   │   ├── ProceduresTab.swift
│   │   │   └── AIPEntriesTab.swift
│   │   │
│   │   ├── Chat/
│   │   │   ├── ChatView.swift
│   │   │   ├── ChatBubble.swift
│   │   │   ├── ChatInputBar.swift
│   │   │   ├── ThinkingIndicator.swift
│   │   │   └── VisualizationCard.swift
│   │   │
│   │   └── Components/
│   │       ├── ConnectivityBanner.swift
│   │       ├── LoadingOverlay.swift
│   │       ├── ErrorBanner.swift
│   │       └── EmptyStateView.swift
│   │
│   └── Helpers/
│       └── FilterBindings.swift
│
├── Assets.xcassets/
├── Data/
│   └── airports.db
└── Development Assets/
    └── airports_small.db
```

---

## Dependencies

### Current (Keep)
- **RZFlight** - Airport data, KnownAirports, spatial queries
  - Provides: `Airport`, `Runway`, `Procedure`, `AIPEntry`, `KnownAirports`
  - Source: [github.com/roznet/rzflight](https://github.com/roznet/rzflight)
- **RZUtilsSwift** - Logging, utilities
- **FMDB** - SQLite access (used by RZFlight)

### Add
- **None required** - Using native Apple frameworks

### Optional (Consider)
- **SwiftLint** - Code style enforcement
- **Quick/Nimble** - BDD testing (if preferred)

---

## RZFlight Enhancement Tracking

When implementing features, if functionality exists in `euro_aip` (Python) but not in RZFlight:

1. **Don't implement in the app** - propose RZFlight enhancement
2. **Track here** until implemented
3. **Workaround if needed** - use local extension temporarily

### Proposed Enhancements

| Feature | Python Reference | Priority | Workaround |
|---------|-----------------|----------|------------|
| **API-friendly initializers** | For API → RZFlight | **Critical** | Extension in app |
| Fuel filtering (AVGAS/Jet-A) | `has_avgas`, `has_jet_a` | High | AIP entry search |
| Landing fee filtering | `max_landing_fee` | Medium | AIP entry search |
| Country list | `get_countries()` | High | SQL query |
| Airport count by country | `count_by_country()` | Low | Compute locally |

### API-Friendly Initializers (Critical for Phase 4)

RZFlight models currently use `FMResultSet` initializers. For API responses, we need:

```swift
// Needed in RZFlight
Airport.init(icao:name:city:country:latitude:longitude:elevation_ft:type:...)
Runway.init(length_ft:width_ft:surface:lighted:closed:le:he:)
Procedure.init(name:procedureType:approachType:runwayIdent:...)
AIPEntry.init(ident:section:field:value:...)
```

**Workaround until merged:** Define extensions in `App/Extensions/RZFlight+APIInit.swift`

### How to Propose Enhancement

```bash
# 1. Clone RZFlight
git clone https://github.com/roznet/rzflight

# 2. Add feature following existing patterns
# 3. Add tests
# 4. Submit PR
```

---

## Milestones & Timeline

| Phase | Duration | Milestone |
|-------|----------|-----------|
| Phase 1 | Week 1-3 | Data layer complete, models defined |
| Phase 2 | Week 4-5 | Filters working, enhanced state |
| Phase 3 | Week 6-8 | UI complete for all platforms |
| Phase 4 | Week 9-10 | Online API integration |
| Phase 5 | Week 11-13 | Online chatbot working |
| Phase 6 | Week 14-17 | Offline chatbot working |
| Phase 7 | Week 18-19 | Polish, testing, release prep |

**Total: ~19 weeks (5 months)**

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| On-device LLM performance | Medium | High | Test early, have fallback to simple Q&A |
| API changes | Low | Medium | Version API, handle gracefully |
| Large database size | Medium | Medium | Incremental sync, compression |
| Memory constraints (iPhone) | Medium | High | Lazy loading, proper cleanup |
| Apple Intelligence availability | High | Medium | Support alternative (Core ML) |

---

## Next Steps

1. **Immediate**: Start Phase 1 - Core models and local data source
2. **Decision needed**: Minimum iOS version (17 or 18?)
3. **Decision needed**: On-device LLM approach
4. **Setup**: Configure SwiftLint, testing framework

---

## Related Documents

- `designs/IOS_APP_DESIGN.md` - Architecture and design
- `designs/UI_FILTER_STATE_DESIGN.md` - Web state patterns (reference)
- `designs/CHATBOT_WEBUI_DESIGN.md` - Chatbot patterns (reference)

