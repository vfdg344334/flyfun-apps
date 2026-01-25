# FlyFunBrief iOS App Architecture

> **Read this first** before working on any FlyFunBrief feature.

## Executive Summary

Native iOS/iPadOS/macOS app for managing pre-flight briefings. Key differentiator: **NOTAM status tracking across briefing updates**.

**Core Principles:**
- **RZFlight-first**: All domain models from RZFlight library (Briefing, Notam, Route)
- **Composed AppState**: Single source of truth via composed domains (mirrors FlyFunEuroAIP)
- **Enriched Models**: Wrap RZFlight models with user state for display
- **Identity-based tracking**: NOTAMs matched across briefings via identity keys

## Platform Requirements

| Platform | Minimum | Notes |
|----------|---------|-------|
| iOS | 18.0+ | `@Observable`, modern SwiftUI |
| iPadOS | 18.0+ | NavigationSplitView |
| macOS | 15.0+ | Native (no Catalyst) |

## File Organization

```
app/FlyFunBrief/
├── App/
│   ├── FlyFunBriefApp.swift       # Entry point
│   ├── State/
│   │   ├── AppState.swift         # Composed state
│   │   └── Domains/
│   │       ├── BriefingDomain     # Import, parsing
│   │       ├── NotamDomain        # Filtering, status
│   │       ├── FlightDomain       # CRUD, selection
│   │       ├── NavigationDomain   # Tabs, sheets
│   │       └── SettingsDomain     # Preferences
│   ├── Services/
│   │   └── BriefingService.swift  # API communication
│   ├── Data/
│   │   ├── CoreData/              # Persistence
│   │   └── Repositories/          # CRUD abstraction
│   ├── Models/                    # App-specific only
│   └── Config/
│       └── SecretsManager.swift
└── UserInterface/
    └── Views/
        ├── iPhone/                # Tab bar layout
        ├── iPad/                  # Split view layout
        ├── Flights/               # Flight CRUD views
        ├── NotamList/             # NOTAM list/row
        ├── NotamDetail/           # NOTAM detail sheet
        ├── Filters/               # Filter panel
        └── IgnoreList/            # Global ignore list
```

## RZFlight Model Reuse

### Rules
1. **Use RZFlight models directly** - Do NOT create duplicate Briefing, Notam, Route models
2. **Extend RZFlight, not the app** - Missing functionality → enhance RZFlight library
3. **App-specific types for display only** - EnrichedNotam wraps Notam with user status

### Available RZFlight Models

```swift
import RZFlight

// Domain models - use directly
let briefing: RZFlight.Briefing
let notams: [RZFlight.Notam]
let route: RZFlight.Route

// Categorization
let category: RZFlight.NotamCategory
```

| Model | Key Features |
|-------|--------------|
| `Briefing` | route, notams[], source, date |
| `Notam` | id, qCode, location, effectiveFrom/To, message |
| `Route` | departure, destination, alternates, waypoints |
| `NotamCategory` | runway, navigation, airspace, obstacle, etc. |

## AppState - Composed Single Source of Truth

### Domain Structure

```
┌─────────────────────────────────────────────────────────────┐
│                        AppState                              │
│                   (Single Source of Truth)                   │
│                                                             │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ │
│  │BriefingDomain│ │ NotamDomain  │ │   FlightDomain       │ │
│  │  ~166 lines  │ │  ~657 lines  │ │     ~278 lines       │ │
│  └──────────────┘ └──────────────┘ └──────────────────────┘ │
│                                                             │
│  ┌──────────────┐ ┌──────────────┐                         │
│  │NavigationDom │ │SettingsDomain│                         │
│  │  ~163 lines  │ │  ~100 lines  │                         │
│  └──────────────┘ └──────────────┘                         │
└─────────────────────────────────────────────────────────────┘
```

### Domain Responsibilities

| Domain | State | Actions |
|--------|-------|---------|
| **BriefingDomain** | currentBriefing, isLoading, importProgress | importBriefing, loadBriefing |
| **NotamDomain** | allNotams, enrichedNotams, filters, annotations | setStatus, filter, search |
| **FlightDomain** | flights, selectedFlight | create, select, archive, importBriefing |
| **NavigationDomain** | selectedTab, presentedSheet, isViewingFlight | showSheet, enterFlightView |
| **SettingsDomain** | apiBaseURL, defaultGrouping, autoMarkAsRead | save/restore via UserDefaults |

### Cross-Domain Communication

Domains communicate via **callbacks** set up in AppState.init():

```swift
// In AppState.init() - setupCrossDomainWiring()
briefing.onBriefingParsed = { [weak self] briefing in
    self?.flights.importBriefing(briefing)
}

briefing.onBriefingLoaded = { [weak self] briefing, cdBriefing in
    self?.notams.setBriefing(briefing, cdBriefing: cdBriefing)
}

flights.onFlightSelected = { [weak self] flight in
    self?.navigation.enterFlightView(flightId: flight.id)
    // Load briefing if available
}
```

### Environment Injection

```swift
// View access
struct NotamListView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        // appState?.notams.filteredEnrichedNotams
    }
}

// Entry point injection
WindowGroup {
    ContentView()
        .environment(\.appState, appState)
}
```

## No ViewModels Rule

**Do NOT create:**
- `*ViewModel.swift` files
- `@StateObject` or `ObservableObject` classes
- Per-view state containers

**Instead:**
- Use domains in AppState
- Use `@State` for truly local UI state only

## Key Architectural Patterns

### 1. Enriched Model Pattern

Keep RZFlight models pure; wrap with user state for display:

```swift
struct EnrichedNotam {
    let notam: Notam           // RZFlight model (read-only)
    let status: NotamStatus    // User status (read/important/etc.)
    let textNote: String?      // User annotation
    let isNew: Bool            // First time seen
    let isGloballyIgnored: Bool

    var identityKey: String { NotamIdentity.key(for: notam) }
}
```

### 2. Identity Key-Based Tracking

NOTAMs matched across briefing updates via stable identity keys:

```swift
enum NotamIdentity {
    // Key = ID|QCode|Location|EffectiveFrom
    static func key(for notam: Notam) -> String
    static func transferStatuses(from old: [...], to new: [...]) -> [...]
    static func findNewNotams(current: [...], previousKeys: Set<String>) -> [...]
}
```

### 3. Repository Abstraction

Core Data operations go through repositories:

```swift
@MainActor final class FlightRepository {
    func createFlight(origin:destination:...) -> CDFlight
    func importBriefing(_ briefing: Briefing, for flight: CDFlight)
    func updateNotamStatus(_ notam: Notam, status: NotamStatus)
}
```

### 4. Actor-Based Services

Thread-safe API and persistence:

```swift
actor BriefingService {
    func parseBriefing(pdfData: Data, source: String) async throws -> Briefing
}

actor AnnotationStore {
    func saveAnnotation(_ annotation: NotamAnnotation) async throws
}
```

## Data Flow Patterns

### Briefing Import Flow

```
User imports PDF
    ↓
BriefingDomain.importBriefing(url)
    ↓
BriefingService.parseBriefing() → Briefing
    ↓
onBriefingParsed callback
    ↓
FlightDomain.importBriefing()
    ↓
FlightRepository.importBriefing()
  - Create CDBriefing
  - Create CDNotamStatus for each NOTAM
  - Transfer statuses from previous via identity keys
    ↓
onBriefingImported callback
    ↓
NotamDomain.setBriefing()
  - Build EnrichedNotam array
  - Apply global ignore list
  - Mark new NOTAMs
```

### NOTAM Status Update Flow

```
User marks NOTAM important
    ↓
NotamDomain.setStatus(.important, for: notam)
    ↓
Update local annotations dict
    ↓
FlightRepository.updateNotamStatus() (async)
    ↓
NotamDomain.refreshEnrichedNotams()
    ↓
UI re-renders (@Observable)
```

## Modern Swift Patterns

| Pattern | Usage |
|---------|-------|
| `@Observable` | All domains in AppState |
| `@Environment` | Dependency injection |
| `async/await` | All async operations |
| `@MainActor` | All state mutations |
| `actor` | Thread-safe services |

## Related Documents

- [BRIEFING_APP_DATA.md](BRIEFING_APP_DATA.md) - Core Data, repositories, persistence
- [BRIEFING_APP_NOTAMS.md](BRIEFING_APP_NOTAMS.md) - NOTAM domain, filtering, enrichment
- [IOS_APP_ARCHITECTURE.md](IOS_APP_ARCHITECTURE.md) - FlyFunEuroAIP patterns (reference)
