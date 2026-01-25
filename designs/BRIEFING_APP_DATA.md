# FlyFunBrief Data Layer

> Core Data stack, repositories, and persistence patterns.

## Intent

Manage flight and briefing persistence with CloudKit sync. Track NOTAM status across briefing updates using identity-based matching.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Domains                             │
│  (FlightDomain, NotamDomain, BriefingDomain)            │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│                    Repositories                          │
│  ┌──────────────────┐  ┌─────────────────────────────┐  │
│  │ FlightRepository │  │    IgnoreListManager        │  │
│  │  - Flight CRUD   │  │  - Global ignore list       │  │
│  │  - Briefing imp  │  │  - Identity key cache       │  │
│  │  - Status update │  │  - Auto-expiration          │  │
│  └──────────────────┘  └─────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│               PersistenceController                      │
│  - NSPersistentCloudKitContainer                        │
│  - iCloud sync (iCloud.com.ro-z.flyfunbrief)           │
│  - History tracking enabled                             │
└─────────────────────────────────────────────────────────┘
```

## Core Data Entities

### CDFlight
Flight record with route information.

| Attribute | Type | Notes |
|-----------|------|-------|
| id | UUID | Primary key |
| origin | String | ICAO code |
| destination | String | ICAO code |
| departureTime | Date? | Planned departure |
| routeICAOs | String? | JSON array of route waypoints |
| isArchived | Bool | Soft delete |
| createdAt | Date | |
| updatedAt | Date | |

**Relationships:** `briefings` → [CDBriefing] (cascade delete)

**Extensions:**
```swift
extension CDFlight {
    var routeArray: [String]           // Decode routeICAOs JSON
    var displayTitle: String           // "LFPG → EGLL"
    var sortedBriefings: [CDBriefing]  // By importedAt descending
    var latestBriefing: CDBriefing?
    var unreadNotamCount: Int
}
```

### CDBriefing
Briefing snapshot with full RZFlight Briefing JSON.

| Attribute | Type | Notes |
|-----------|------|-------|
| id | UUID | |
| briefingData | Data | Encoded RZFlight.Briefing |
| source | String | "ForeFlight", "SkyDemon", etc. |
| importedAt | Date | |
| routeSummary | String? | Quick display text |

**Relationships:**
- `flight` → CDFlight
- `statuses` → [CDNotamStatus] (cascade delete)

**Extensions:**
```swift
extension CDBriefing {
    var decodedBriefing: Briefing?              // Decode JSON
    var statusesByNotamId: [String: CDNotamStatus]
    var statusesByIdentityKey: [String: CDNotamStatus]

    static func create(from briefing: Briefing,
                       for flight: CDFlight) -> CDBriefing
}
```

### CDNotamStatus
Per-NOTAM status within a briefing.

| Attribute | Type | Notes |
|-----------|------|-------|
| id | UUID | |
| notamId | String | NOTAM ID from source |
| identityKey | String | Stable key for matching |
| status | Int16 | NotamStatus raw value |
| textNote | String? | User annotation |
| statusChangedAt | Date? | |
| createdAt | Date | |

**Relationships:** `briefing` → CDBriefing

**Extensions:**
```swift
extension CDNotamStatus {
    var statusEnum: NotamStatus { get set }
    var hasNote: Bool

    func copy(from other: CDNotamStatus)  // Transfer status
}
```

### CDIgnoredNotam
Global ignore list entries.

| Attribute | Type | Notes |
|-----------|------|-------|
| id | UUID | |
| identityKey | String | Matches NotamIdentity.key |
| notamId | String | Original NOTAM ID |
| reason | String? | User's ignore reason |
| expiresAt | Date? | Auto-expire date (from NOTAM effectiveTo) |
| isPermanent | Bool | Never expires |
| createdAt | Date | |

**Extensions:**
```swift
extension CDIgnoredNotam {
    var isExpired: Bool
    static func cleanupExpired(context:)  // Delete expired entries
}
```

## Repositories

### FlightRepository

Primary repository for flight and briefing CRUD.

```swift
@MainActor final class FlightRepository {
    private let persistenceController: PersistenceController

    // Flight CRUD
    func createFlight(origin: String, destination: String,
                      departureTime: Date?, routeICAOs: [String]?) -> CDFlight
    func updateFlight(_ flight: CDFlight, origin: String, ...)
    func deleteFlight(_ flight: CDFlight)
    func archiveFlight(_ flight: CDFlight)
    func unarchiveFlight(_ flight: CDFlight)

    // Fetch
    func fetchActiveFlights() -> [CDFlight]
    func fetchArchivedFlights() -> [CDFlight]

    // Briefing import (see flow below)
    func importBriefing(_ briefing: Briefing, for flight: CDFlight) -> CDBriefing

    // Status management
    func updateNotamStatus(_ notam: Notam, briefing: CDBriefing,
                           status: NotamStatus, textNote: String?)
    func getPreviousIdentityKeys(for flight: CDFlight,
                                  excluding: CDBriefing?) -> Set<String>
}
```

### IgnoreListManager

Global ignore list with caching.

```swift
@MainActor final class IgnoreListManager {
    private var ignoredKeysCache: Set<String> = []

    // CRUD
    func addToIgnoreList(_ notam: Notam, reason: String?)
    func removeFromIgnoreList(_ notam: Notam)
    func removeFromIgnoreList(identityKey: String)

    // Lookup (cache-backed for performance)
    func isIgnored(_ notam: Notam) -> Bool
    func isIgnored(identityKey: String) -> Bool
    func getIgnoredIdentityKeys() -> Set<String>

    // Maintenance
    func cleanupExpired()
    func refreshCache()
}
```

## Key Data Flows

### Briefing Import with Status Transfer

```swift
func importBriefing(_ briefing: Briefing, for flight: CDFlight) -> CDBriefing {
    // 1. Get previous identity keys for "new NOTAM" detection
    let previousKeys = getPreviousIdentityKeys(for: flight, excluding: nil)

    // 2. Get statuses from previous briefing for transfer
    let previousStatuses = flight.latestBriefing?.statusesByIdentityKey ?? [:]

    // 3. Create new CDBriefing
    let cdBriefing = CDBriefing.create(from: briefing, for: flight)

    // 4. Create CDNotamStatus for each NOTAM
    for notam in briefing.notams {
        let identityKey = NotamIdentity.key(for: notam)
        let status = CDNotamStatus.create(context: context)
        status.notamId = notam.id
        status.identityKey = identityKey
        status.briefing = cdBriefing

        // Transfer status from previous briefing if exists
        if let previous = previousStatuses[identityKey] {
            status.copy(from: previous)
        } else {
            status.statusEnum = .unread
        }
    }

    // 5. Save
    try context.save()
    return cdBriefing
}
```

### Global Ignore List Usage

```swift
// In NotamDomain.buildEnrichedNotams()
let ignoredKeys = ignoreListManager.getIgnoredIdentityKeys()

enrichedNotams = allNotams.map { notam in
    let key = NotamIdentity.key(for: notam)
    return EnrichedNotam(
        notam: notam,
        status: statuses[key]?.statusEnum ?? .unread,
        isGloballyIgnored: ignoredKeys.contains(key)
    )
}
```

## PersistenceController

```swift
@MainActor final class PersistenceController {
    static let shared = PersistenceController()
    static var preview: PersistenceController  // In-memory for previews

    let container: NSPersistentCloudKitContainer
    var viewContext: NSManagedObjectContext { container.viewContext }

    func newBackgroundContext() -> NSManagedObjectContext
}
```

**CloudKit Configuration:**
- Container ID: `iCloud.com.ro-z.flyfunbrief`
- History tracking enabled for sync
- Remote change notifications handled

## Legacy: AnnotationStore

SQLite-based annotation storage (FMDB). Being phased out in favor of Core Data.

```swift
actor AnnotationStore {
    // DB: ~/Library/Application Support/FlyFunBrief/annotations.db

    func loadAnnotations(forBriefingId: String) async throws -> [NotamAnnotation]
    func saveAnnotation(_ annotation: NotamAnnotation) async throws
    func deleteAnnotation(notamId: String, briefingId: String) async throws
}
```

**Migration path:** Use Core Data CDNotamStatus for all new features. AnnotationStore remains for legacy handwritten note support.

## Secrets Management

Same pattern as FlyFunEuroAIP:

```swift
// secrets.json (git-ignored)
{
    "api_base_url": "http://localhost:8000"
}

// Access via
let url = SecretsManager.shared.apiBaseURL
```

## Gotchas

1. **Always use identity keys for NOTAM matching** - NOTAM IDs can change between briefings
2. **Ignore list auto-expires** - Entries removed when NOTAM's effectiveTo date passes
3. **Status transfer happens at import time** - Not retroactive
4. **Cache invalidation** - Call `IgnoreListManager.refreshCache()` after bulk operations

## References

- Key code: `app/FlyFunBrief/App/Data/`
- Related: [BRIEFING_APP_ARCHITECTURE.md](BRIEFING_APP_ARCHITECTURE.md)
