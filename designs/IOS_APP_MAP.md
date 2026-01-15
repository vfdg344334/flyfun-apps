# iOS App Map

> Map views, legends, markers, and visualization.

## Map Architecture

Two map implementations based on mode:

```
┌─────────────────────────────────────────────────────────────────┐
│                      AirportMapView                              │
│                    (Main entry point)                            │
└─────────────────────────────┬───────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │ isOfflineMode?                │
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────────────┐
│   onlineMapContent      │     │       OfflineMapView            │
│   (SwiftUI Map)         │     │   (MKMapView + CachedTiles)     │
└─────────────────────────┘     └─────────────────────────────────┘
```

## AirportMapView

Main view that switches between online/offline based on `ChatDomain.isOfflineMode`:

```swift
struct AirportMapView: View {
    @Environment(\.appState) private var state

    private var isOfflineMode: Bool {
        state?.chat.isOfflineMode ?? false
    }

    var body: some View {
        Group {
            if isOfflineMode {
                offlineMapContent  // MKMapView with cached tiles
            } else {
                onlineMapContent(legendMode: currentLegendMode)  // SwiftUI Map
            }
        }
        .overlay(alignment: .bottomTrailing) { legendKeyOverlay }
        .overlay(alignment: .bottomLeading) { legendOverlay }
        .overlay(alignment: .top) {
            if isOfflineMode {
                // Orange "Offline Map" indicator
            }
        }
    }
}
```

## Online Map (SwiftUI Map)

Uses modern MapKit with `Map { }` builder:

```swift
@ViewBuilder
private func onlineMapContent(legendMode: LegendMode) -> some View {
    Map(position: mapPosition, selection: $selectedAirportID) {
        // Airport markers
        ForEach(airports, id: \.icao) { airport in
            Annotation(airport.icao, coordinate: airport.coord) {
                AirportMarkerView(
                    airport: airport,
                    legendMode: legendMode,
                    isSelected: airport.icao == state?.airports.selectedAirport?.icao,
                    isBorderCrossing: state?.airports.isBorderCrossing(airport) ?? false,
                    notificationInfo: state?.notificationService?.getNotification(icao: airport.icao)
                )
            }
            .tag(airport.icao)
        }

        // Route polyline
        if let route = state?.airports.activeRoute {
            MapPolyline(coordinates: route.coordinates)
                .stroke(.blue.opacity(0.8), lineWidth: 4)
        }

        // Highlights (from chat visualization)
        ForEach(Array(highlights.values), id: \.id) { highlight in
            MapCircle(center: highlight.coordinate, radius: highlight.radius)
                .foregroundStyle(highlightColor(highlight.color).opacity(0.2))
                .stroke(highlightColor(highlight.color), lineWidth: 2)
        }
    }
    .mapStyle(.standard(elevation: .realistic))
    .mapControls { MapCompass(); MapScaleView(); MapUserLocationButton() }
    .onMapCameraChange(frequency: .onEnd) { context in
        state?.airports.visibleRegion = context.region
        state?.airports.onRegionChange(context.region)
    }
}
```

## Offline Map (MKMapView)

Uses `UIViewRepresentable` with `CachedTileOverlay` for offline tiles:

```swift
struct OfflineMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var airports: [RZFlight.Airport]
    var selectedAirport: RZFlight.Airport?
    var onAirportSelected: ((RZFlight.Airport) -> Void)?
    var onRegionChange: ((MKCoordinateRegion) -> Void)?
    var useOfflineTiles: Bool
    var legendMode: LegendMode
    var borderCrossingAirports: Set<String>
    var activeRoute: RouteVisualization?
    var highlights: [String: MapHighlight]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        if useOfflineTiles {
            let tileOverlay = CachedTileOverlay(urlTemplate: nil)
            mapView.addOverlay(tileOverlay, level: .aboveRoads)
        }

        return mapView
    }
}
```

## Legend Modes

```swift
enum LegendMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case airportType = "Airport Type"
    case runwayLength = "Runway Length"
    case procedures = "IFR Procedures"
    case country = "Country"
    case notification = "Notification"

    var icon: String {
        switch self {
        case .airportType: return "airplane.circle"
        case .runwayLength: return "road.lanes"
        case .procedures: return "arrow.down.to.line.compact"
        case .country: return "flag"
        case .notification: return "bell"
        }
    }
}
```

### Legend Colors & Sizes

| Mode | Color Logic | Size Logic |
|------|-------------|------------|
| **Airport Type** | Green=Border Crossing, Yellow=IFR, Red=VFR | 16/14/12 by type |
| **Runway Length** | Green=>8000ft, Yellow=4000-8000ft, Red=<4000ft | 20/14/10 |
| **Procedures** | Yellow=ILS, Blue=RNAV, Orange=Non-precision, Gray=VFR | By procedure count |
| **Country** | Hash-based consistent color per country | Fixed 14 |
| **Notification** | Green=Easy, Blue=Moderate, Orange=Some hassle, Red=High hassle, Gray=No data | By easiness score |

## AirportMarkerView

Custom marker supporting variable color AND size:

```swift
struct AirportMarkerView: View {
    let airport: RZFlight.Airport
    let legendMode: LegendMode
    let isSelected: Bool
    let isBorderCrossing: Bool
    let notificationInfo: NotificationInfo?

    var body: some View {
        ZStack {
            Circle()
                .fill(markerColor.gradient)
                .frame(width: markerSize, height: markerSize)
                .shadow(color: markerColor.opacity(0.5), radius: isSelected ? 8 : 2)

            if isSelected {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: markerSize + 6, height: markerSize + 6)
            }
        }
    }

    private var markerSize: CGFloat {
        switch legendMode {
        case .airportType: return airportTypeSize
        case .runwayLength: return runwayLengthSize
        case .procedures: return procedureSize
        case .country: return 14
        case .notification: return notificationSize
        }
    }

    private var markerColor: Color {
        switch legendMode {
        case .airportType: return airportTypeColor
        case .runwayLength: return runwayLengthColor
        case .procedures: return procedureColor
        case .country: return countryColor
        case .notification: return notificationColor
        }
    }
}
```

### Notification Mode Colors

Based on `NotificationInfo.easinessScore`:

```swift
private var notificationColor: Color {
    guard let info = notificationInfo else { return .gray }
    return info.legendColor  // Computed from easinessScore
}

private var notificationSize: CGFloat {
    guard let info = notificationInfo else { return 8 }
    let score = info.easinessScore
    switch score {
    case 80...100: return 16  // Easy
    case 60..<80: return 14   // Moderate
    case 40..<60: return 12   // Some hassle
    default: return 10        // High hassle
    }
}
```

## Visualization from Chat

Chat responses can trigger map updates via `ChatVisualizationPayload`:

```swift
// In ChatDomain
var onVisualization: ((ChatVisualizationPayload) -> Void)?

// In AppState.setupCrossDomainWiring()
chat.onVisualization = { [weak self] payload in
    self?.airports.applyVisualization(payload)
}

// In AirportDomain
func applyVisualization(_ payload: ChatVisualizationPayload) {
    // Update highlights, route, zoom to results
    if let markers = payload.visualization?.markers {
        highlights = markers.reduce(into: [:]) { dict, marker in
            // Convert to MapHighlight
        }
    }

    if let route = payload.visualization?.route {
        activeRoute = RouteVisualization(/* ... */)
    }

    // Auto-zoom to results
    if let center = payload.visualization?.center {
        focusMap(on: center)
    }
}
```

## Offline Map Behavior

When offline mode is enabled:
1. Map switches to `OfflineMapView` (MKMapView-based)
2. Tiles served from `CachedTileOverlay`
3. Orange "Offline Map" banner shown at top
4. Notification legend mode shows gray (no data offline)

## Related Documents

- [IOS_APP_ARCHITECTURE.md](IOS_APP_ARCHITECTURE.md) - AppState, domains
- [IOS_APP_OFFLINE.md](IOS_APP_OFFLINE.md) - Tile caching details
- [IOS_APP_CHAT.md](IOS_APP_CHAT.md) - Chat visualization integration
