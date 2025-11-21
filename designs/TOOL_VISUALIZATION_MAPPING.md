# Tool → Visualization Type Mapping

This document maps each tool to its expected visualization type and structure.

## Tool → Visualization Mapping

### 1. `search_airports`
**Tool Result:**
- `airports`: Array of airport summaries (limited to 20 for LLM)
- `visualization.type`: `"markers"`
- `visualization.data`: Array of ALL matching airports (for map display)

**UI Handler:** `_handleMarkers()` → `FilterManager.updateMapWithAirports()`

---

### 2. `find_airports_near_route` ⚠️ **FIXED**
**Tool Result:**
- `airports`: Array of airport summaries (limited to 20 for LLM)
- `visualization.type`: `"route_with_markers"`
- `visualization.route`: `{from: {icao, lat, lon}, to: {icao, lat, lon}}`
- `visualization.markers`: Array of ALL airports along route (for map display) ✅ **NOW INCLUDED**

**UI Handler:** `_handleRouteWithMarkers()` → `handleRouteWithChatbotAirports()` or `FilterManager.handleRouteSearch()`

**Expected Structure:**
```json
{
  "type": "route_with_markers",
  "route": {
    "from": {"icao": "EGTF", "lat": 51.348, "lon": -0.559},
    "to": {"icao": "LFMD", "lat": 43.548, "lon": 6.955}
  },
  "markers": [
    {"ident": "EGTF", "name": "...", "lat": 51.348, "lon": -0.559, ...},
    {"ident": "LFMD", "name": "...", "lat": 43.548, "lon": 6.955, ...},
    ...
  ]
}
```

---

### 3. `find_airports_near_location`
**Tool Result:**
- `airports`: Array of airport summaries (limited to 20 for LLM)
- `visualization.type`: `"point_with_markers"`
- `visualization.point`: `{label, lat, lon}`
- `visualization.markers`: Array of ALL airports within radius (for map display)

**UI Handler:** Currently not implemented in `chat-map-integration.js` (would need `_handlePointWithMarkers()`)

---

### 4. `get_airport_details`
**Tool Result:**
- `airport`: Single airport summary
- `visualization.type`: `"marker_with_details"`
- `visualization.marker`: `{ident, lat, lon, zoom}`

**UI Handler:** `_handleMarkerWithDetails()` → `FilterManager.handleSearch()`

---

### 5. `get_border_crossing_airports`
**Tool Result:**
- `airports`: Array of airport summaries (limited for LLM)
- `visualization.type`: `"markers"`
- `visualization.data`: Array of border crossing airports (for map display)
- `visualization.style`: `"customs"` (optional styling hint)

**UI Handler:** `_handleMarkers()` → `FilterManager.updateMapWithAirports()`

---

## UI Visualization Type Expectations

### `route_with_markers`
**Required Fields:**
- `type`: `"route_with_markers"`
- `route.from`: `{icao, lat, lon}` (or `latitude`, `longitude`, `latitude_deg`, `longitude_deg`)
- `route.to`: `{icao, lat, lon}` (or `latitude`, `longitude`, `latitude_deg`, `longitude_deg`)
- `markers`: Array of airport objects (each with `ident`, `lat`/`latitude_deg`, `lon`/`longitude_deg`, etc.)

**Handler:** `ChatMapIntegration._handleRouteWithMarkers()` → `handleRouteWithChatbotAirports()`

---

### `markers`
**Required Fields:**
- `type`: `"markers"`
- `data` OR `markers`: Array of airport objects

**Handler:** `ChatMapIntegration._handleMarkers()` → `FilterManager.updateMapWithAirports()`

---

### `marker_with_details`
**Required Fields:**
- `type`: `"marker_with_details"`
- `marker.ident` OR `marker.icao`: Airport ICAO code
- `marker.lat` OR `marker.latitude`: Latitude
- `marker.lon` OR `marker.longitude`: Longitude
- `marker.zoom`: Optional zoom level

**Handler:** `ChatMapIntegration._handleMarkerWithDetails()` → `FilterManager.handleSearch()`

---

### `point_with_markers`
**Required Fields:**
- `type`: `"point_with_markers"`
- `point.label`: Location label
- `point.lat`: Center point latitude
- `point.lon`: Center point longitude
- `markers`: Array of airport objects

**Handler:** Not yet implemented (would need `_handlePointWithMarkers()`)

---

## Notes

1. **Airport Arrays**: Tools return `airports` limited to 20 for LLM, but visualization should include ALL matching airports for map display.

2. **Coordinate Field Names**: UI handlers normalize coordinate fields:
   - `lat` / `latitude` / `latitude_deg` → all accepted
   - `lon` / `longitude` / `longitude_deg` → all accepted

3. **Route Visualization**: `route_with_markers` requires BOTH `route` AND `markers` - the route defines the line, markers show airports along it.

4. **Filter Integration**: All visualizations are delegated to `FilterManager` to ensure consistent behavior with UI filters.

