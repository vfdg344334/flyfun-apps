# iOS App Offline Mode

> Offline infrastructure: tile caching, bundled data, and on-device AI.

## Overview

Offline mode provides full functionality without network:

| Component | Offline Source |
|-----------|---------------|
| Airport data | Bundled `airports.db` (SQLite) |
| Rules | Bundled `rules.json` |
| Notifications | Bundled `ga_notifications.db` |
| Map tiles | `CachedTileOverlay` (pre-downloaded or cached) |
| AI | MediaPipe LLM (Gemma 2B) |

## Enabling Offline Mode

Toggle in **ChatView toolbar** (top-left):

```
┌─────────────────────────────────────┐
│ ✈️ Offline    Assistant      🗑️    │  ← Orange = offline
│ ☁️ Online     Assistant      🗑️    │  ← Blue = online
└─────────────────────────────────────┘
```

When offline mode is enabled:
- `ChatDomain.isOfflineMode = true`
- Map switches to `OfflineMapView`
- Chat uses `OfflineChatbotService`

## Tile Caching Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    OfflineTileManager                            │
│  (Singleton - manages downloads and storage)                     │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CachedTileOverlay                             │
│  (MKTileOverlay subclass - serves tiles from cache)              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ~/Caches/tiles/                               │
│  (File-based tile storage)                                       │
└─────────────────────────────────────────────────────────────────┘
```

## OfflineTileManager

Manages tile downloads and storage:

```swift
@Observable
final class OfflineTileManager {
    static let shared = OfflineTileManager()

    // State
    var isDownloading: Bool = false
    var downloadProgress: Double = 0.0
    var downloadedRegions: Set<String> = []
    var totalStorageBytes: Int64 = 0

    // Pre-defined European regions
    static let europeanRegions: [MapRegion] = [
        MapRegion(id: "western_europe", name: "Western Europe", estimatedStorageMB: 150),
        MapRegion(id: "central_europe", name: "Central Europe", estimatedStorageMB: 120),
        MapRegion(id: "uk_ireland", name: "UK & Ireland", estimatedStorageMB: 80),
        // ...
    ]

    func downloadRegion(_ region: MapRegion) async {
        isDownloading = true
        defer { isDownloading = false }

        // Download tiles for zoom levels 5-12
        for zoom in 5...12 {
            let tiles = tilesForRegion(region, zoom: zoom)
            for tile in tiles {
                try await downloadTile(tile)
                downloadProgress = /* update */
            }
        }

        downloadedRegions.insert(region.id)
    }

    func clearAllTiles() {
        try? FileManager.default.removeItem(at: tileCacheDirectory)
        downloadedRegions = []
        totalStorageBytes = 0
    }
}
```

## CachedTileOverlay

Custom `MKTileOverlay` that serves from cache:

```swift
final class CachedTileOverlay: MKTileOverlay {
    var offlineOnly: Bool = false

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let cacheURL = tileCacheURL(for: path)

        // Try cache first
        if let data = try? Data(contentsOf: cacheURL) {
            result(data, nil)
            return
        }

        // If offline-only, fail
        if offlineOnly {
            result(nil, TileError.offlineAndNotCached)
            return
        }

        // Fetch from network and cache
        Task {
            let tileURL = self.url(forTilePath: path)
            let (data, _) = try await URLSession.shared.data(from: tileURL)
            try data.write(to: cacheURL)
            result(data, nil)
        }
    }

    private func tileCacheURL(for path: MKTileOverlayPath) -> URL {
        // ~/Caches/tiles/{z}/{x}/{y}.png
        return tileCacheDirectory
            .appendingPathComponent("\(path.z)")
            .appendingPathComponent("\(path.x)")
            .appendingPathComponent("\(path.y).png")
    }
}
```

## OfflineMapsView (Settings UI)

User interface for managing offline maps:

```swift
struct OfflineMapsView: View {
    @StateObject private var tileManager = OfflineTileManager.shared

    var body: some View {
        List {
            // Storage section
            Section("Storage") {
                HStack {
                    Label("Storage Used", systemImage: "internaldrive")
                    Spacer()
                    Text(formatBytes(tileManager.totalStorageBytes))
                }

                Button("Clear All Maps", role: .destructive) {
                    tileManager.clearAllTiles()
                }
            }

            // Download progress
            if tileManager.isDownloading {
                Section("Download Progress") {
                    ProgressView(value: tileManager.downloadProgress)
                    Button("Cancel") { tileManager.cancelDownload() }
                }
            }

            // Regions
            Section("European Regions") {
                ForEach(OfflineTileManager.europeanRegions) { region in
                    HStack {
                        Text(region.name)
                        Spacer()
                        if tileManager.downloadedRegions.contains(region.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button { Task { await tileManager.downloadRegion(region) } } label: {
                                Image(systemName: "arrow.down.circle")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Offline Maps")
    }
}
```

## Bundled Data

### airports.db
Bundled SQLite database with all European airports, runways, procedures, AIP entries.

```swift
// In LocalAirportDataSource
init() throws {
    guard let dbPath = Bundle.main.path(forResource: "airports", ofType: "db") else {
        throw DataSourceError.bundledDatabaseNotFound
    }
    self.db = FMDatabase(path: dbPath)
    self.knownAirports = KnownAirports(db: db)
}
```

### rules.json
Bundled aviation rules by country (~7500 lines):

```swift
// In LocalToolDispatcher
func initialize(airportDataSource: LocalAirportDataSource) async throws {
    self.airportDataSource = airportDataSource

    // Load bundled rules
    if let rulesURL = Bundle.main.url(forResource: "rules", withExtension: "json") {
        let data = try Data(contentsOf: rulesURL)
        self.rulesManager = try RulesManager(jsonData: data)
    }
}
```

### ga_notifications.db
Bundled notification requirements database:

```swift
// In NotificationService
static func createFromBundle() -> NotificationService? {
    guard let dbPath = Bundle.main.path(forResource: "ga_notifications", ofType: "db") else {
        return nil
    }
    return NotificationService(databasePath: dbPath)
}
```

## On-Device AI

### MediaPipe LLM

Uses MediaPipe's LLM Inference API with Gemma 2B:

```swift
// InferenceEngine.swift
import MediaPipeTasksGenAI

final class InferenceEngine {
    private var llmInference: LlmInference?

    func loadModel(at path: String) async throws {
        let options = LlmInference.Options(modelPath: path)
        options.maxTokens = 2048
        options.temperature = 0.7
        options.topK = 40
        llmInference = try LlmInference(options: options)
    }

    func generate(prompt: String) async throws -> String {
        guard let llm = llmInference else {
            throw InferenceError.modelNotLoaded
        }
        return try llm.generateResponse(inputText: prompt)
    }
}
```

### Model File

The model file (`gemma-2b-it-cpu-int4.bin`) can be:
1. **Bundled** in app (increases app size ~1.5GB)
2. **Downloaded** on first use to `~/Documents/models/`

```swift
// ModelManager.swift
final class ModelManager {
    var modelPath: String {
        // Prefer bundled
        if let bundled = Bundle.main.path(forResource: "gemma-2b-it-cpu-int4", ofType: "bin") {
            return bundled
        }
        // Fall back to downloaded
        return documentsDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("gemma-2b-it-cpu-int4.bin")
            .path
    }

    var isModelAvailable: Bool {
        FileManager.default.fileExists(atPath: modelPath)
    }

    func downloadModel() async throws {
        // Download from server if not bundled
    }
}
```

## Offline vs Online Feature Matrix

| Feature | Online | Offline |
|---------|--------|---------|
| Airport search | API | Local SQLite |
| Airport details | API | Local SQLite |
| Route search | API | Local KDTree |
| Rules lookup | API | Bundled JSON |
| Notification data | API | Bundled SQLite |
| AI responses | Claude (server) | Gemma 2B (device) |
| Map tiles | Live OSM | Cached tiles |
| Suggested queries | Server-generated | Not available |

## Notification Mode Offline

When in offline mode, notification legend shows gray for all airports:

```swift
// In OfflineMapView.Coordinator
case .notification:
    // Notification data not available offline - show gray
    return .gray
```

This is because `NotificationService` requires the bundled DB which may not have all airports' notification data readily computable offline.

## File Locations

```
App Bundle:
├── airports.db              # Airport data
├── rules.json               # Aviation rules
├── ga_notifications.db      # Notification data
└── gemma-2b-it-cpu-int4.bin # LLM model (optional)

~/Caches/
└── tiles/
    └── {z}/{x}/{y}.png      # Cached map tiles

~/Documents/
└── models/
    └── gemma-2b-it-cpu-int4.bin  # Downloaded model
```

## Related Documents

- [IOS_APP_ARCHITECTURE.md](IOS_APP_ARCHITECTURE.md) - Core patterns
- [IOS_APP_MAP.md](IOS_APP_MAP.md) - Map views, OfflineMapView
- [IOS_APP_CHAT.md](IOS_APP_CHAT.md) - OfflineChatbotService
