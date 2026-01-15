# Web App Map Visualization

> VisualizationEngine, markers, routes, highlights, and map layer management.

## Quick Reference

| File | Purpose |
|------|---------|
| `ts/engines/visualization-engine.ts` | Leaflet map rendering and management |
| `ts/config/legend-configs.ts` | Legend configurations (see `WEB_APP_LEGENDS.md`) |
| `ts/utils/legend-classifier.ts` | Classification utilities |

**Key Exports:**
- `VisualizationEngine` - Main map management class
- `getColorFromConfig()`, `classifyData()` - Legend utilities

**Prerequisites:** Read `WEB_APP_ARCHITECTURE.md` and `WEB_APP_STATE.md` first.

**Related:** `WEB_APP_LEGENDS.md` for legend modes and configuration.

---

## VisualizationEngine Responsibilities

| Responsibility | Methods |
|----------------|---------|
| Map initialization | `initMap(containerId)` |
| Marker management | `updateMarkers(airports, legendMode)` |
| Route rendering | `displayRoute(routeState)`, `clearRoute()` |
| Highlight system | `updateHighlights(highlights)` |
| Procedure lines | `loadBulkProcedureLines()`, `clearProcedureLines()` |
| View control | `setView(lat, lng, zoom)`, `fitBounds()` |

---

## Layer Architecture

The map uses Leaflet layer groups to organize elements:

```
Map
├── Tile Layer (OpenStreetMap / custom tiles)
├── Airport Markers Layer
│   └── CircleMarker per airport
├── Route Layer
│   ├── Polyline (route line)
│   └── Markers (departure, destination)
├── Highlights Layer
│   ├── LLM highlights (blue circles)
│   ├── Route airport highlights
│   └── Locate center marker
└── Procedure Lines Layer
    └── Polylines for approach procedures
```

**Layer Cleanup Rule:** Always clear layer before adding new elements to prevent memory leaks.

```typescript
// Pattern: Clear before add
this.routeLayer.clearLayers();
this.routeLayer.addLayer(newPolyline);
```

---

## Markers

### Marker Creation

Airports are rendered as Leaflet `CircleMarker` with styling based on legend mode:

```typescript
const marker = L.circleMarker([airport.lat, airport.lon], {
  radius: 7,
  fillColor: color,      // From legend config
  color: '#000',         // Border
  weight: 1,
  opacity: 1,
  fillOpacity: 0.8,
});
```

### Marker Styling

Marker color is determined by legend mode. See `WEB_APP_LEGENDS.md` for all modes.

```typescript
getMarkerStyle(airport: Airport, legendMode: LegendMode): MarkerStyle {
  switch (legendMode) {
    case 'airport-type':
      return { color: getColorFromConfig(airport, AIRPORT_TYPE_LEGEND_CONFIG), radius: 7 };
    case 'notification':
      return { color: getColorFromConfig(airport, NOTIFICATION_LEGEND_CONFIG), radius: 7 };
    case 'relevance':
      return { color: this.getRelevanceColor(airport), radius: 7 };
    // ... other modes
  }
}
```

### Marker Interactions

```typescript
marker.on('click', () => {
  window.dispatchEvent(new CustomEvent('airport-click', {
    detail: { icao: airport.icao }
  }));
});

marker.bindTooltip(airport.icao, {
  permanent: false,
  direction: 'top'
});
```

---

## Routes

### Route State

```typescript
interface RouteState {
  departure: string;      // ICAO code
  destination: string;    // ICAO code
  departureCoords: [number, number];
  destinationCoords: [number, number];
  waypoints?: string[];   // Intermediate waypoints
}
```

### Displaying Routes

```typescript
displayRoute(routeState: RouteState): void {
  this.clearRoute();

  // Draw route line
  const line = L.polyline([
    routeState.departureCoords,
    routeState.destinationCoords
  ], {
    color: '#007bff',
    weight: 3,
    dashArray: '10, 5'
  });

  // Add endpoint markers
  const depMarker = L.marker(routeState.departureCoords, { icon: departureIcon });
  const destMarker = L.marker(routeState.destinationCoords, { icon: destinationIcon });

  this.routeLayer.addLayer(line);
  this.routeLayer.addLayer(depMarker);
  this.routeLayer.addLayer(destMarker);

  // Fit bounds to show entire route
  this.map.fitBounds(line.getBounds(), { padding: [50, 50] });
}
```

---

## Highlights

Highlights are temporary visual markers used to emphasize specific airports.

### Highlight Types

| Type | Use Case | Visual |
|------|----------|--------|
| LLM highlight | Airports mentioned in chatbot response | Blue circle, larger radius |
| Route highlight | Departure/destination airports | Special marker icon |
| Locate center | Center point of locate search | Pulsing circle |

### Highlight Structure

```typescript
interface Highlight {
  id: string;           // Unique ID (e.g., 'llm-EGTF')
  lat: number;
  lon: number;
  type: 'llm' | 'route' | 'locate';
  label?: string;
}
```

### Managing Highlights

```typescript
// Add highlight
store.getState().highlightPoint({
  id: `llm-${airport.icao}`,
  lat: airport.lat,
  lon: airport.lon,
  type: 'llm'
});

// Remove specific highlight
store.getState().removeHighlight('llm-EGTF');

// Clear all highlights
store.getState().clearHighlights();

// Clear only LLM highlights (pattern)
const highlights = store.getState().visualization.highlights;
highlights.forEach((_, id) => {
  if (id.startsWith('llm-')) {
    store.getState().removeHighlight(id);
  }
});
```

### Highlight Rendering

```typescript
updateHighlights(highlights: Map<string, Highlight>): void {
  this.highlightLayer.clearLayers();

  highlights.forEach((highlight) => {
    const marker = L.circleMarker([highlight.lat, highlight.lon], {
      radius: 12,
      fillColor: '#007bff',
      color: '#0056b3',
      weight: 2,
      fillOpacity: 0.3
    });

    if (highlight.label) {
      marker.bindTooltip(highlight.label, { permanent: true });
    }

    this.highlightLayer.addLayer(marker);
  });
}
```

---

## Procedure Lines

Procedure lines show approach paths for airports with IFR procedures.

### Loading Procedure Lines

```typescript
async loadBulkProcedureLines(airports: Airport[], apiAdapter: APIAdapter): Promise<void> {
  // Get airports with procedures
  const airportsWithProcedures = airports.filter(a => a.has_procedures);

  if (airportsWithProcedures.length === 0) return;

  // Fetch procedure lines from API
  const icaos = airportsWithProcedures.map(a => a.icao);
  const procedureLines = await apiAdapter.getBulkProcedureLines(icaos, 25); // 25nm max

  // Render lines
  this.clearProcedureLines();
  procedureLines.forEach(line => {
    const polyline = L.polyline(line.coordinates, {
      color: this.getProcedureLineColor(line.type),
      weight: 2,
      opacity: 0.7
    });
    this.procedureLinesLayer.addLayer(polyline);
  });
}
```

### Procedure Line Colors

| Procedure Type | Color |
|----------------|-------|
| ILS (Precision) | Yellow (#ffff00) |
| RNP/RNAV | Blue (#0000ff) |
| VOR/NDB (Non-Precision) | White (#ffffff) |

See `WEB_APP_LEGENDS.md` → "Procedure Precision Legend" for details.

---

## View Management

### Setting View

```typescript
setView(lat: number, lng: number, zoom: number): void {
  this.map.setView([lat, lng], zoom);
}
```

### Fit to Airports

```typescript
fitBounds(airports?: Airport[]): void {
  const points = (airports || store.getState().filteredAirports)
    .map(a => [a.lat, a.lon] as [number, number]);

  if (points.length === 0) return;

  const bounds = L.latLngBounds(points);
  this.map.fitBounds(bounds, { padding: [50, 50] });
}
```

### Fit to Route

```typescript
fitToRoute(routeState: RouteState): void {
  const bounds = L.latLngBounds([
    routeState.departureCoords,
    routeState.destinationCoords
  ]);
  this.map.fitBounds(bounds, { padding: [50, 50] });
}
```

---

## Update Flow

When store state changes, the map updates via subscriptions:

```typescript
// main.ts subscription
store.subscribe((state, prevState) => {
  // Airports changed → update markers
  if (state.filteredAirports !== prevState.filteredAirports) {
    visualizationEngine.updateMarkers(
      state.filteredAirports,
      state.visualization.legendMode
    );
  }

  // Legend mode changed → re-style markers
  if (state.visualization.legendMode !== prevState.visualization.legendMode) {
    visualizationEngine.updateMarkers(
      state.filteredAirports,
      state.visualization.legendMode
    );
  }

  // Highlights changed → update highlight layer
  if (state.visualization.highlights !== prevState.visualization.highlights) {
    visualizationEngine.updateHighlights(state.visualization.highlights);
  }

  // Route changed → display/clear route
  if (state.route !== prevState.route) {
    if (state.route) {
      visualizationEngine.displayRoute(state.route);
    } else {
      visualizationEngine.clearRoute();
    }
  }
});
```

---

## Performance Considerations

### Marker Clustering

For large airport sets, consider clustering:

```typescript
// Not currently implemented, but pattern:
const markers = L.markerClusterGroup();
airports.forEach(airport => {
  markers.addLayer(L.circleMarker([airport.lat, airport.lon], style));
});
this.map.addLayer(markers);
```

### Viewport-Based Loading

Only load airports visible in current viewport:

```typescript
const bounds = this.map.getBounds();
const visibleAirports = airports.filter(a =>
  bounds.contains([a.lat, a.lon])
);
```

### Debounced Updates

Updates are debounced at 50ms to prevent rapid re-renders during filter changes.

---

## Key Methods Reference

| Method | Purpose |
|--------|---------|
| `initMap(containerId)` | Initialize Leaflet map in DOM element |
| `updateMarkers(airports, legendMode)` | Render airport markers with legend styling |
| `displayRoute(routeState)` | Draw route line with endpoints |
| `clearRoute()` | Remove route visualization |
| `updateHighlights(highlights)` | Render highlight markers |
| `setView(lat, lng, zoom)` | Set map center and zoom |
| `fitBounds(airports?)` | Fit map to show all airports |
| `getMap()` | Get Leaflet map instance |
| `loadBulkProcedureLines(airports, api)` | Load and render procedure lines |
| `clearProcedureLines()` | Remove procedure lines |

---

## Debugging

```javascript
// Browser console
visualizationEngine.getMap()              // Leaflet map instance
visualizationEngine.getMap().getZoom()    // Current zoom
visualizationEngine.getMap().getBounds()  // Current viewport bounds
```
