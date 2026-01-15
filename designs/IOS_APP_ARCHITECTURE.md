# iOS App Architecture

> **Read this first** before working on any iOS app feature.

## Executive Summary

Native app for iOS, iPadOS, and macOS. Key differentiator: **offline/online hybrid operation**.

**Core Principles:**
- **Offline-first**: Full functionality with bundled database when offline
- **Online-enhanced**: Live data, full chatbot, and sync when online
- **RZFlight-first**: Maximize reuse of RZFlight models
- **Composed AppState**: Single source of truth, but not a god-class

## Platform Requirements

| Platform | Minimum | Notes |
|----------|---------|-------|
| iOS | 18.0+ | Latest SwiftUI, `@Observable` |
| iPadOS | 18.0+ | Full NavigationSplitView |
| macOS | 15.0+ | Native (no Catalyst) |

**Why Latest Only:**
- `@Observable` macro (no legacy `ObservableObject`)
- Native `@Environment` injection
- Modern MapKit with `Map { }` builder
- No backward compatibility complexity

## Critical Rule: RZFlight Model Reuse

### Rules

1. **Use RZFlight models directly** - Do NOT create duplicate Airport, Runway, Procedure models
2. **Use KnownAirports as primary interface** - All airport queries through `KnownAirports`
3. **Extend RZFlight, not the app** - Missing functionality → enhance RZFlight library
4. **App-specific types only when necessary** - UI state, API responses, config only

### Available RZFlight Models

```swift
import RZFlight

// ✅ CORRECT
let airport: RZFlight.Airport
let runways: [RZFlight.Runway]
let procedures: [RZFlight.Procedure]

// ❌ WRONG - Don't duplicate
// struct AppAirport { ... }
```

| Model | Key Features |
|-------|--------------|
| `Airport` | icao, name, coord, country, runways[], procedures[], aipEntries[] |
| `Runway` | length_ft, width_ft, surface, lighted, isHardSurface |
| `Procedure` | procedureType, approachType, precisionCategory |
| `AIPEntry` | section, field, value, standardField |
| `KnownAirports` | KDTree spatial queries, filtering, route search |

## AppState - Composed Single Source of Truth

### Why Composed?

**Problems with Multiple ViewModels:**
- State sync between Map, Detail, Chat views
- Chatbot needs to update map (visualizations)
- Complex coordination

**Problems with Monolithic AppState:**
- God-class anti-pattern (2000+ lines)
- Hard to test
- Merge conflicts

**Solution:** One `@Observable` store composed of domain objects.

### Domain Structure

```
┌─────────────────────────────────────────────────────────────────┐
│                        AppState                                  │
│                   (Single Source of Truth)                       │
│                                                                 │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────┐ │
│  │AirportDomain │ │  ChatDomain  │ │   NavigationDomain       │ │
│  │  ~400 lines  │ │  ~300 lines  │ │     ~200 lines           │ │
│  └──────────────┘ └──────────────┘ └──────────────────────────┘ │
│                                                                 │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────────┐ │
│  │ SystemDomain │ │SettingsDomain│ │   NotificationService    │ │
│  │  ~150 lines  │ │  ~250 lines  │ │     ~200 lines           │ │
│  └──────────────┘ └──────────────┘ └──────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Domain Responsibilities

| Domain | State | Actions |
|--------|-------|---------|
| **AirportDomain** | airports, selectedAirport, filters, mapPosition, legendMode, highlights, activeRoute | search, select, focusMap, applyVisualization |
| **ChatDomain** | messages, input, isStreaming, isOfflineMode, suggestedQueries | send, clear, setOfflineMode, useSuggestion |
| **NavigationDomain** | selectedTab, showingFilters, showingChat, leftOverlayMode | showChat, hideChat, toggleFilters |
| **SystemDomain** | connectivityMode, isLoading, error | setLoading, setError, startMonitoring |
| **SettingsDomain** | units, defaultFilters, sessionState | saveSessionState |

### Cross-Domain Communication

Domains communicate via **callbacks**, not direct references:

```swift
// In AppState.setupCrossDomainWiring()
chat.onVisualization = { [weak self] payload in
    self?.airports.applyVisualization(payload)
}

chat.onClearVisualization = { [weak self] in
    self?.airports.clearVisualization()
}
```

### Environment Injection

```swift
// View access
struct AirportMapView: View {
    @Environment(\.appState) private var state

    var body: some View {
        // state?.airports.select(airport)
    }
}

// Environment key
private struct AppStateKey: EnvironmentKey {
    static let defaultValue: AppState? = nil
}

extension EnvironmentValues {
    var appState: AppState? {
        get { self[AppStateKey.self] }
        set { self[AppStateKey.self] = newValue }
    }
}
```

## No ViewModels Rule

**Do NOT create:**
- `*ViewModel.swift` files
- `@StateObject` or `ObservableObject` classes
- Per-view state containers

**Instead:**
- Use domains in AppState
- Use `@State` for truly local UI state (text fields, animations)
- ViewCoordinators are structs with computed properties only

## Modern Swift Patterns

| Pattern | Usage |
|---------|-------|
| `@Observable` | All domains in AppState |
| `@Environment` | Dependency injection |
| `async/await` | All async operations |
| `AsyncStream` | SSE streaming |
| `@MainActor` | All state mutations |

## File Organization

```
app/FlyFunEuroAIP/
├── App/
│   ├── FlyFunEuroAIPApp.swift      # Entry point
│   ├── State/
│   │   ├── AppState.swift          # Composed state
│   │   └── Domains/
│   │       ├── AirportDomain.swift
│   │       ├── ChatDomain.swift
│   │       ├── NavigationDomain.swift
│   │       ├── SystemDomain.swift
│   │       └── SettingsDomain.swift
│   ├── Data/
│   │   ├── DataSources/
│   │   └── Repositories/
│   ├── Models/                      # App-specific only
│   └── Services/
│       ├── Chatbot/
│       ├── Offline/
│       └── NotificationService.swift
├── UserInterface/
│   └── Views/
│       ├── Map/
│       ├── Chat/
│       ├── Airport/
│       └── Settings/
└── Assets.xcassets/
```

## Related Documents

- [IOS_APP_DATA.md](IOS_APP_DATA.md) - Repository pattern, data sources
- [IOS_APP_MAP.md](IOS_APP_MAP.md) - Map views, legends, markers
- [IOS_APP_CHAT.md](IOS_APP_CHAT.md) - Chat system, AI, tools
- [IOS_APP_OFFLINE.md](IOS_APP_OFFLINE.md) - Offline mode details
