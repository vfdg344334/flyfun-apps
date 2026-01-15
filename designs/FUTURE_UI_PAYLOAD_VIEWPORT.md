# Future: Viewport-Based Airport Loading

## Overview

This document describes the design for loading airports based on the current map viewport (bounding box). This enables showing "all airports in view" rather than just query results.

**Status:** Future enhancement (not yet implemented)

**Motivation:** When the LLM returns a list of airports without filters (e.g., "show me LFPG, LFPO, and LFOB"), we want to:
1. Zoom to fit those airports
2. Show ALL airports visible in that viewport
3. Highlight the mentioned airports in blue

---

## Current State (Option A - Implemented)

For no-filters case:
- Show only the returned airports
- Fit bounds to them
- Highlight them in blue
- Don't load additional airports

This is simpler but doesn't show context (nearby airports).

---

## Target State (Option C)

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Data Flow                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  Tool Result                                                         │
│      │                                                               │
│      ▼                                                               │
│  LLMIntegration.handleMarkers()                                      │
│      │                                                               │
│      ├── Has filters? ──Yes──► Apply filters + trigger-filter-refresh│
│      │                                                               │
│      └── No filters? ──────► Compute bounding box                    │
│                                    │                                 │
│                                    ▼                                 │
│                              Store.setViewport(bounds)               │
│                                    │                                 │
│                                    ▼                                 │
│                         trigger-viewport-load event                  │
│                                    │                                 │
│                                    ▼                                 │
│                    API: GET /airports?bbox=N,S,E,W                   │
│                                    │                                 │
│                                    ▼                                 │
│                          Store.setAirports(all)                      │
│                                    │                                 │
│                                    ▼                                 │
│                     Store.highlightPoints(mentioned)                 │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### Components to Modify/Add

#### 1. Store Changes (`store.ts`)

Add viewport state:

```typescript
interface VisualizationState {
  // ... existing fields
  viewport: {
    bounds: {north: number; south: number; east: number; west: number} | null;
    zoom: number | null;
    center: {lat: number; lng: number} | null;
  };
}

// Actions
setViewport(bounds, zoom?, center?): void;
clearViewport(): void;
```

**Design consideration:** Viewport state should be in store (single source of truth), not derived from map component.

#### 2. API Endpoint

Add bounding box support to airport search:

```
GET /api/airports?bbox=north,south,east,west&limit=500
```

Or extend existing endpoint:

```python
@router.get("/airports")
async def get_airports(
    bbox: Optional[str] = None,  # "north,south,east,west"
    # ... existing params
):
    if bbox:
        north, south, east, west = map(float, bbox.split(","))
        # Filter airports within bounds
```

#### 3. LLMIntegration Changes

```typescript
private handleMarkers(viz: Visualization): boolean {
  const airports = viz.markers || viz.data || [];
  const filterProfile = viz.filter_profile;

  // Clear old highlights
  this.clearLLMHighlights();

  // Case 1: Has meaningful filters
  if (this.hasFilters(filterProfile)) {
    this.applyFilterProfile(filterProfile);
    window.dispatchEvent(new CustomEvent('trigger-filter-refresh'));
    this.highlightAirports(airports);
    return true;
  }

  // Case 2: No filters - viewport-based loading (FUTURE)
  const bounds = this.computeBoundingBox(airports);
  this.store.getState().setViewport(bounds);
  window.dispatchEvent(new CustomEvent('trigger-viewport-load', {
    detail: { bounds, highlightIcaos: airports.map(a => a.ident) }
  }));
  return true;
}

private computeBoundingBox(airports: Airport[]): BoundingBox {
  // Compute from airport coordinates
  // Add padding (e.g., 10% on each side)
  // Return {north, south, east, west}
}
```

**Note:** `computeBoundingBox` is a pure function - can be in a utility module, not in LLMIntegration.

#### 4. Event Handler

New handler for `trigger-viewport-load`:

```typescript
// In UIManager or dedicated ViewportManager
window.addEventListener('trigger-viewport-load', async (e) => {
  const { bounds, highlightIcaos } = e.detail;

  // 1. Zoom map to bounds
  visualizationEngine.fitToBounds(bounds);

  // 2. Load airports in viewport
  const response = await apiAdapter.getAirports({ bbox: bounds });
  store.getState().setAirports(response.data);

  // 3. Add highlights
  highlightIcaos.forEach(icao => {
    const airport = response.data.find(a => a.ident === icao);
    if (airport) {
      store.getState().highlightPoint({
        id: `llm-airport-${icao}`,
        // ... highlight config
      });
    }
  });
});
```

#### 5. Optional: Debounced Viewport Loading on Pan/Zoom

For dynamic loading as user pans/zooms:

```typescript
// In VisualizationEngine or MapManager
map.on('moveend', debounce(() => {
  const bounds = map.getBounds();
  window.dispatchEvent(new CustomEvent('viewport-changed', {
    detail: { bounds: boundsToObject(bounds) }
  }));
}, 300));
```

This is optional and adds complexity. Consider if needed.

---

## Migration Path

### Phase 1 (Current - Option A)
- `handleMarkers` fits bounds to returned airports
- Highlights mentioned airports
- No viewport-based loading

### Phase 2 (Option C)
1. Add viewport state to store
2. Add bbox API endpoint
3. Add `trigger-viewport-load` event + handler
4. Update `handleMarkers` to use viewport loading for no-filters case

### Phase 3 (Optional - Dynamic Loading)
- Add debounced viewport-changed event
- Load airports on pan/zoom
- Consider caching to avoid redundant API calls

---

## Separation of Concerns

| Component | Responsibility |
|-----------|----------------|
| Tool/Backend | Returns airports, filter_profile, can optionally compute bounding_box |
| Store | Holds viewport state, airports, highlights |
| LLMIntegration | Translates tool results → store actions + events |
| Event Handlers | Orchestrate API calls + store updates |
| VisualizationEngine | Map rendering, zoom/pan, bounds fitting |
| API | Supports bbox parameter for efficient queries |

**Key principle:** Bounding box computation can live in:
- Backend (tool returns `visualization.bounding_box`) - Preferred for complex logic
- Utility function (called by LLMIntegration) - OK for simple padding logic
- NOT in map component (separation of concerns)

---

## API Design Considerations

### Option A: Query Parameter
```
GET /api/airports?bbox=48.5,47.5,3.0,1.5
```
Simple, stateless, cacheable.

### Option B: Dedicated Endpoint
```
GET /api/airports/viewport?north=48.5&south=47.5&east=3.0&west=1.5
```
More explicit, easier to extend.

### Recommendation
Use query parameter (Option A) - simpler, follows REST conventions.

---

## Performance Considerations

1. **Limit results** - Cap at 500-1000 airports per viewport
2. **Clustering** - Consider marker clustering for dense areas
3. **Caching** - Cache viewport queries (same bbox = same results)
4. **Debouncing** - Don't reload on every pixel of pan/zoom

---

## Open Questions

1. Should backend compute bounding box and return in visualization?
   - Pro: Backend has full data, can make smart decisions
   - Con: Couples tool to viewport concept

2. How much padding around airports for bounding box?
   - Suggestion: 20% on each side, minimum 10nm

3. Should we support dynamic loading on pan/zoom?
   - Adds complexity, may not be needed initially

4. How to handle overlapping highlights from multiple queries?
   - Current: Clear old highlights before adding new
   - Could add "highlight groups" for more control
