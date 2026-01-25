# FlyFunBrief NOTAM System

> NOTAM domain, filtering, enrichment, and identity matching.

## Intent

Provide comprehensive NOTAM management with user status tracking, intelligent filtering, and cross-briefing status transfer. The system wraps RZFlight's Notam model with user-specific state.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       NotamDomain                            │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐   │
│  │ allNotams   │  │   filters    │  │  annotations      │   │
│  │ [Notam]     │  │  FilterState │  │  [id: Annotation] │   │
│  └─────────────┘  └──────────────┘  └───────────────────┘   │
│                            │                                 │
│                            ▼                                 │
│              ┌─────────────────────────┐                    │
│              │   enrichedNotams        │                    │
│              │   [EnrichedNotam]       │                    │
│              └─────────────────────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

## EnrichedNotam Model

Wraps RZFlight's Notam with user-specific display state:

```swift
struct EnrichedNotam: Identifiable {
    let notam: Notam              // RZFlight model
    let status: NotamStatus       // read/unread/important/ignored/followUp
    let textNote: String?         // User annotation
    let isNew: Bool               // First time seen in this flight's history
    let isGloballyIgnored: Bool   // Matches global ignore list

    var id: String { notam.id }
    var identityKey: String { NotamIdentity.key(for: notam) }

    // Convenience forwarding
    var message: String { notam.message }
    var location: String? { notam.location }
    var effectiveFrom: Date? { notam.effectiveFrom }
    var effectiveTo: Date? { notam.effectiveTo }
    var category: NotamCategory { notam.category }
}

enum NotamStatus: Int16 {
    case unread = 0
    case read = 1
    case important = 2
    case ignored = 3
    case followUp = 4
}
```

## NotamIdentity

Stable identity keys for matching NOTAMs across briefing updates:

```swift
enum NotamIdentity {
    /// Generate stable identity key
    /// Format: "ID|QCode|Location|EffectiveFrom"
    static func key(for notam: Notam) -> String {
        let parts = [
            notam.id,
            notam.qCode ?? "",
            notam.location ?? "",
            notam.effectiveFrom?.ISO8601 ?? ""
        ]
        return parts.joined(separator: "|")
    }

    /// Check if two NOTAMs represent the same real-world notice
    static func areEqual(_ a: Notam, _ b: Notam) -> Bool {
        return key(for: a) == key(for: b)
    }

    /// Transfer statuses from old briefing to new
    static func transferStatuses(
        from oldStatuses: [String: CDNotamStatus],
        to newNotams: [Notam]
    ) -> [String: NotamStatus]

    /// Find NOTAMs not seen in previous briefings
    static func findNewNotams(
        current: [Notam],
        previousKeys: Set<String>
    ) -> Set<String>
}
```

**Why identity keys?** NOTAM IDs can change between briefing sources or updates. The identity key captures the essential characteristics that make a NOTAM unique.

## NotamDomain

Central domain for NOTAM state and filtering (~657 lines).

### State

```swift
@Observable @MainActor
final class NotamDomain {
    // Source data
    var allNotams: [Notam] = []
    var currentBriefing: Briefing?
    var currentCDBriefing: CDBriefing?

    // User state
    var annotations: [String: NotamAnnotation] = [:]  // keyed by notam.id

    // Filter state
    var searchQuery: String = ""
    var grouping: NotamGrouping = .none
    var categoryFilters: Set<NotamCategory> = Set(NotamCategory.allCases)
    var statusFilter: StatusFilter = .all
    var showIgnored: Bool = false
    var showRead: Bool = true
    var corridorWidth: Double = 25.0  // NM
    var preFlightBuffer: TimeInterval = 2 * 3600   // 2 hours
    var postFlightBuffer: TimeInterval = 2 * 3600  // 2 hours

    // Computed
    var enrichedNotams: [EnrichedNotam]
    var filteredEnrichedNotams: [EnrichedNotam]
    var enrichedNotamsGroupedByAirport: [(String, [EnrichedNotam])]
    var enrichedNotamsGroupedByCategory: [(NotamCategory, [EnrichedNotam])]
}
```

### Filter Pipeline

```swift
var filteredEnrichedNotams: [EnrichedNotam] {
    enrichedNotams
        // 1. Route corridor filter
        .filter { corridorFilter($0.notam) }
        // 2. Category filter
        .filter { categoryFilters.contains($0.category) }
        // 3. Text search
        .filter { searchQuery.isEmpty || $0.matchesSearch(searchQuery) }
        // 4. Status filter
        .filter { statusFilter.matches($0.status) }
        // 5. Visibility filters
        .filter { showIgnored || !$0.isGloballyIgnored }
        .filter { showRead || $0.status != .read }
        // 6. Time window filter
        .filter { timeWindowFilter($0.notam) }
}
```

### Key Methods

```swift
// Set briefing and build enriched NOTAMs
func setBriefing(_ briefing: Briefing,
                  cdBriefing: CDBriefing?,
                  previousKeys: Set<String>,
                  ignoredKeys: Set<String>)

// Status updates
func setStatus(_ status: NotamStatus, for notam: Notam)
func toggleRead(_ notam: Notam)
func toggleImportant(_ notam: Notam)
func addNote(_ note: String, for notam: Notam)

// Bulk operations
func markAllAsRead()
func clearFilters()

// Computed stats
var unreadCount: Int
var importantCount: Int
var newNotamCount: Int
var hasActiveFilters: Bool
```

## Filtering Options

### Grouping

```swift
enum NotamGrouping {
    case none       // Flat list
    case airport    // Group by location ICAO
    case category   // Group by NotamCategory
}
```

### Status Filter

```swift
enum StatusFilter {
    case all
    case unread
    case important
    case followUp

    func matches(_ status: NotamStatus) -> Bool
}
```

### Category Filter

Uses RZFlight's `NotamCategory` enum:
- `.runway` - Runway conditions, closures
- `.taxiway` - Taxiway conditions
- `.apron` - Apron/ramp
- `.navigation` - NAVAIDs, procedures
- `.airspace` - Airspace restrictions
- `.obstacle` - Obstacles, cranes
- `.services` - Fuel, handling
- `.other` - Uncategorized

### Route Corridor Filter

Spatial filtering based on flight route:

```swift
func corridorFilter(_ notam: Notam) -> Bool {
    guard let route = currentBriefing?.route,
          let notamCoord = notam.coordinate else {
        return true  // No route or no coordinate = include
    }

    // Check distance from route centerline
    let distance = route.distanceFromCenterline(notamCoord)
    return distance <= corridorWidth.nauticalMilesToMeters
}
```

### Time Window Filter

Filter by NOTAM validity during flight window:

```swift
func timeWindowFilter(_ notam: Notam) -> Bool {
    guard let departure = currentFlight?.departureTime else {
        return true
    }

    let windowStart = departure.addingTimeInterval(-preFlightBuffer)
    let windowEnd = departure.addingTimeInterval(estimatedFlightDuration + postFlightBuffer)

    // NOTAM must overlap with flight window
    return notam.overlapsTimeWindow(start: windowStart, end: windowEnd)
}
```

## Global Ignore List

Persistent ignore list applied across all briefings and flights:

```swift
// Add to ignore list
func ignoreGlobally(_ notam: Notam, reason: String?) {
    ignoreListManager.addToIgnoreList(notam, reason: reason)
    refreshEnrichedNotams()
}

// Check at enrichment time
let ignoredKeys = ignoreListManager.getIgnoredIdentityKeys()
let isIgnored = ignoredKeys.contains(identityKey)
```

**Auto-expiration:** Ignored entries automatically expire when the NOTAM's `effectiveTo` date passes, unless marked permanent.

## Usage Examples

### Build enriched NOTAMs from briefing

```swift
func setBriefing(_ briefing: Briefing, cdBriefing: CDBriefing?) {
    allNotams = briefing.notams
    currentBriefing = briefing
    currentCDBriefing = cdBriefing

    let statuses = cdBriefing?.statusesByIdentityKey ?? [:]
    let ignoredKeys = ignoreListManager.getIgnoredIdentityKeys()
    let previousKeys = getPreviousIdentityKeys()

    enrichedNotams = allNotams.map { notam in
        let key = NotamIdentity.key(for: notam)
        return EnrichedNotam(
            notam: notam,
            status: statuses[key]?.statusEnum ?? .unread,
            textNote: statuses[key]?.textNote,
            isNew: !previousKeys.contains(key),
            isGloballyIgnored: ignoredKeys.contains(key)
        )
    }
}
```

### Update NOTAM status

```swift
func setStatus(_ status: NotamStatus, for notam: Notam) {
    // Update local state
    annotations[notam.id] = NotamAnnotation(
        notamId: notam.id,
        status: status
    )

    // Persist asynchronously
    Task {
        if let cdBriefing = currentCDBriefing {
            flightRepository.updateNotamStatus(
                notam,
                briefing: cdBriefing,
                status: status,
                textNote: nil
            )
        }
    }

    refreshEnrichedNotams()
}
```

### Filter by multiple criteria

```swift
// Show only unread runway NOTAMs within corridor
notamDomain.statusFilter = .unread
notamDomain.categoryFilters = [.runway]
notamDomain.corridorWidth = 15.0  // Narrow corridor
notamDomain.showRead = false

// Access filtered results
let notams = notamDomain.filteredEnrichedNotams
```

## UI Components

### NotamRowView
Displays single NOTAM in list with:
- Category chip (colored badge)
- Status indicator (unread dot, important star)
- "NEW" badge for first-seen NOTAMs
- Location and effective dates
- Swipe actions for status changes

### NotamDetailView
Full NOTAM detail sheet:
- Complete message text
- Q-code breakdown
- Map view (if coordinates available)
- Status buttons (read/important/ignore)
- Note editor
- Global ignore option

### FilterPanelView
Filter configuration:
- Category toggles
- Status filter picker
- Corridor width slider
- Time window adjustments
- Show/hide ignored toggle

## Gotchas

1. **Always use identity keys** - Not NOTAM IDs for matching
2. **Enrichment is expensive** - Cache and only rebuild when needed
3. **Ignored vs status.ignored** - Global ignore list is separate from per-NOTAM ignore status
4. **"New" is flight-scoped** - Compared to all previous briefings for this flight
5. **Filter order matters** - Route corridor first (expensive) then cheap filters

## References

- Key code: `app/FlyFunBrief/App/State/Domains/NotamDomain.swift`
- Related: [BRIEFING_APP_DATA.md](BRIEFING_APP_DATA.md) for persistence
