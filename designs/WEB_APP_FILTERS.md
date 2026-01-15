# Web App Filter System

> Filter architecture, FilterEngine, AIP filtering, and adding new filters.

## Quick Reference

| File | Purpose |
|------|---------|
| `shared/filtering/filter_engine.py` | Backend filter engine (single source of truth) |
| `shared/filtering/filters/` | Individual filter implementations |
| `shared/airport_tools.py` | Filter profile building |
| `ts/store/types.ts` | `FilterConfig` type definition |
| `ts/adapters/api-adapter.ts` | Filter params transformation |
| `ts/adapters/llm-integration.ts` | Filter profile application |
| `ts/managers/ui-manager.ts` | Filter UI controls |

**Key Exports:**
- `FilterEngine` - Backend filter engine
- `FilterConfig` - Frontend filter type
- `applyFilterProfile()` - LLM filter application

**Prerequisites:** Read `WEB_APP_ARCHITECTURE.md` and `WEB_APP_STATE.md` first.

---

## Architecture: Single Source of Truth

All airport filtering uses `FilterEngine` as the single source of truth. Both REST API and LangGraph tools use the same engine.

```
┌──────────────────────────────────────────────────────────────────┐
│                    FilterEngine (Backend)                         │
│                 shared/filtering/filter_engine.py                 │
└──────────────────────────────────────────────────────────────────┘
                    │                           │
                    ▼                           ▼
        ┌───────────────────┐       ┌───────────────────────────┐
        │   REST API        │       │   LangGraph Tools         │
        │   /api/airports   │       │   search_airports, etc.   │
        └───────────────────┘       └───────────────────────────┘
                    │                           │
                    └───────────┬───────────────┘
                                ▼
                    ┌───────────────────────┐
                    │   Frontend Store      │
                    │   FilterConfig        │
                    └───────────────────────┘
```

---

## FilterConfig (Frontend)

```typescript
interface FilterConfig {
  // Location/distance
  country?: string;                    // ISO-2 country code
  search_radius_nm?: number;           // Default: 50
  enroute_distance_max_nm?: number;

  // Capabilities
  has_procedures?: boolean;
  has_aip_data?: boolean;
  has_hard_runway?: boolean;
  point_of_entry?: boolean;            // Border crossing capability

  // Fuel
  fuel_type?: 'avgas' | 'jet_a';       // Preferred (UI dropdown)
  has_avgas?: boolean;                 // Legacy boolean
  has_jet_a?: boolean;                 // Legacy boolean

  // Amenities (integer encoding)
  hotel?: number;                      // -1=unknown, 0=none, 1=vicinity, 2=at_airport
  restaurant?: number;

  // Runway constraints
  min_runway_length_ft?: number;
  max_runway_length_ft?: number;

  // Other
  max_landing_fee?: number;
  trip_distance?: number;
  exclude_large_airports?: boolean;

  // Notification
  max_hours_notice?: number;
}
```

---

## Backend vs Client-Side Filtering

### Backend Filtering (Authoritative)

The `FilterEngine` applies all filters on the server. Results are consistent whether from REST API or LangGraph tools.

### Client-Side Filtering (Display Only)

The `filterAirports()` function in `store.ts` provides immediate UI feedback for basic filters. **This is NOT authoritative.**

```typescript
// store.ts - Client-side filtering
function filterAirports(airports: Airport[], filters: FilterConfig): Airport[] {
  return airports.filter(airport => {
    if (filters.country && airport.country !== filters.country) return false;
    if (filters.has_procedures && !airport.has_procedures) return false;
    if (filters.has_aip_data && !airport.has_aip_data) return false;
    if (filters.has_hard_runway && !airport.has_hard_runway) return false;
    if (filters.point_of_entry && !airport.point_of_entry) return false;
    return true;
  });
}
```

### Backend-Only Filters

These filters require API calls (not available client-side):
- `fuel_type`, `has_avgas`, `has_jet_a`
- `hotel`, `restaurant`
- `min_runway_length_ft`, `max_runway_length_ft`
- `max_landing_fee`
- `trip_distance`, `exclude_large_airports`
- `max_hours_notice`
- AIP field filters

---

## Adding a New Filter

### Step 1: Create Filter Class (Backend)

In `shared/filtering/filters/`, create a new filter:

```python
# shared/filtering/filters/my_new_filter.py
from shared.filtering.base import Filter

class MyNewFilter(Filter):
    name = "my_filter"
    description = "Filter by something"

    def apply(self, airport: dict, value: Any, context: dict) -> bool:
        """Return True if airport passes the filter."""
        return airport.get("some_field") == value
```

### Step 2: Register in FilterEngine

```python
# shared/filtering/filter_engine.py
from shared.filtering.filters.my_new_filter import MyNewFilter

FilterRegistry.register(MyNewFilter())
```

### Step 3: Add to Filter Profile Builder

```python
# shared/airport_tools.py - _build_filter_profile()

# For string/number values:
for key in ["country", "fuel_type", ..., "my_filter"]:
    if key in filters:
        profile[key] = filters[key]

# For boolean values:
for key in ["has_procedures", "has_hard_runway", ..., "my_bool_filter"]:
    if filters.get(key):
        profile[key] = True
```

### Step 4: Add REST API Query Parameter

```python
# web/server/api/airports.py

@router.get("/")
async def get_airports(
    # ... existing params
    my_filter: Optional[str] = Query(None, description="Filter by something"),
):
    filters = {}
    # ... existing filter mapping
    if my_filter:
        filters["my_filter"] = my_filter

    airports = filter_engine.apply(all_airports, filters)
    return {"airports": airports}
```

### Step 5: Add Frontend Type

```typescript
// ts/store/types.ts
interface FilterConfig {
  // ... existing fields
  my_filter?: string;
}
```

### Step 6: Add API Parameter Transformation

```typescript
// ts/adapters/api-adapter.ts
function transformFiltersToParams(filters: FilterConfig): URLSearchParams {
  const params = new URLSearchParams();
  // ... existing transformations
  if (filters.my_filter) params.set('my_filter', filters.my_filter);
  return params;
}
```

### Step 7: Add Filter Profile Application (LLM)

```typescript
// ts/adapters/llm-integration.ts
function applyFilterProfile(profile: FilterConfig): void {
  const filters: Partial<FilterConfig> = {};
  // ... existing mappings
  if (profile.my_filter != null) filters.my_filter = profile.my_filter;

  store.getState().setFilters(filters);
  uiManager.syncFiltersToUI(filters);
}
```

### Step 8: Add UI Control (Optional)

```typescript
// ts/managers/ui-manager.ts

// In init()
const myFilterSelect = document.getElementById('my-filter-select');
myFilterSelect?.addEventListener('change', (e) => {
  const value = (e.target as HTMLSelectElement).value;
  this.handleFilterChange({ my_filter: value || undefined });
});

// In syncFiltersToUI()
const myFilterSelect = document.getElementById('my-filter-select') as HTMLSelectElement;
if (myFilterSelect) {
  myFilterSelect.value = filters.my_filter || '';
}
```

---

## AIP Field Filtering

AIP (Aeronautical Information Publication) filtering allows filtering by specific AIP field values.

### AIP Filter Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `aip_field` | string | Field name to filter on |
| `aip_operator` | string | Operator: `contains`, `equals`, `not_empty`, `starts_with`, `ends_with` |
| `aip_value` | string | Value to match (not needed for `not_empty`) |

### Implementation

AIP filtering uses `_matches_aip_field()` helper, not the standard FilterEngine:

```python
# shared/airport_tools.py
def _matches_aip_field(airport: dict, field: str, operator: str, value: str) -> bool:
    aip_value = airport.get("aip", {}).get(field, "")

    if operator == "not_empty":
        return bool(aip_value)
    elif operator == "contains":
        return value.lower() in aip_value.lower()
    elif operator == "equals":
        return aip_value.lower() == value.lower()
    elif operator == "starts_with":
        return aip_value.lower().startswith(value.lower())
    elif operator == "ends_with":
        return aip_value.lower().endswith(value.lower())
    return False
```

### AIP Filter Presets

Pre-defined common AIP filters:

```typescript
interface AIPPreset {
  name: string;
  field: string;
  operator: string;
  value: string;
}

// Examples:
{ name: "Has Customs", field: "cust", operator: "not_empty", value: "" }
{ name: "Has Fuel", field: "fuel", operator: "not_empty", value: "" }
{ name: "Has JET A1", field: "fuel", operator: "contains", value: "JET A1" }
```

### UI Manager AIP Methods

```typescript
// Load metadata from API
loadAIPFilters(): Promise<void>

// Wire up event listeners
wireUpAIPFilters(): void

// Handle field/operator/value changes
handleAIPFieldChange(): void

// Apply preset
applyAIPPreset(preset: AIPPreset): void

// Clear filter
clearAIPFilter(): void

// Update active filter display
updateActiveAIPFilter(field: string, operator: string, value: string): void
```

---

## UIManager Filter Methods

The UIManager handles all filter-related DOM interactions.

### Core Filter Methods

```typescript
// Handle any filter change - updates store and triggers re-filter
handleFilterChange(changes: Partial<FilterConfig>): void

// Sync UI controls to match store state (for LLM integration)
syncFiltersToUI(filters: FilterConfig): void

// Apply filters - triggers API call with current store filters
applyFilters(): Promise<void>

// Clear all filters - resets store and UI to defaults
clearFilters(): void
```

### Route/Locate Filter Methods

```typescript
// Re-run route search with current filters
applyRouteSearch(route: RouteState): Promise<void>

// Re-run locate search with cached center and current filters
applyLocateWithCenter(locate: LocateState): Promise<void>
```

### Persona/GA Methods

```typescript
// Populate persona selector from GA config
populatePersonaSelector(): void

// Update persona selector visibility (now always visible)
updatePersonaSelectorVisibility(legendMode: LegendMode): void

// Trigger GA scores load for visible airports
triggerGAScoresLoad(): void
```

### Internal Methods

```typescript
// Update filter controls to match state (private)
updateFilterControls(filters: FilterConfig): void

// Wire up all filter control event listeners (private)
wireUpFilterControls(): void
```

---

## Filter Profile from LLM

When the chatbot returns `filter_profile` in `ui_payload`:

```typescript
// ui_payload structure
{
  kind: 'route',
  filters: {                    // Flattened from tool_result.filter_profile
    country: 'FR',
    has_avgas: true,
    point_of_entry: true
  },
  // ...
}
```

**Application flow:**
```
ui_payload received
    ↓
LLMIntegration.applyFilterProfile(ui_payload.filters)
    ↓
store.setFilters(mappedFilters)
    ↓
uiManager.syncFiltersToUI(mappedFilters)
    ↓
Store subscription fires
    ↓
Map markers update with new filters
UI controls update to match
```

---

## Filter Validation

### Frontend Validation

```typescript
function validateFilterValue(key: string, value: any): boolean {
  switch (key) {
    case 'min_runway_length_ft':
    case 'max_runway_length_ft':
      return typeof value === 'number' && value >= 0;
    case 'fuel_type':
      return ['avgas', 'jet_a', undefined].includes(value);
    case 'has_procedures':
    case 'has_aip_data':
      return typeof value === 'boolean' || value === undefined;
    // ... etc
    default:
      return true;
  }
}
```

### Backend Validation

The FilterEngine validates filter values and ignores invalid ones:

```python
class Filter:
    def validate(self, value: Any) -> bool:
        """Return True if value is valid for this filter."""
        return True  # Override in subclass

    def apply(self, airport: dict, value: Any, context: dict) -> bool:
        if not self.validate(value):
            return True  # Skip invalid filter (pass all)
        # ... actual filtering logic
```

---

## Filter with Active Route/Locate

When filters change while a route or locate search is active:

```
Filter checkbox toggled
    ↓
handleFilterChange() updates store filters
    ↓
Detects active route (route exists, not chatbot selection)
    ↓
Calls applyFilters()
    ↓
If route: applyRouteSearch() re-runs API with new filters
If locate: applyLocateWithCenter() re-runs API with new filters
    ↓
Store updates → Map updates reactively
```

**Key:** Route/locate searches are re-run with new filters to maintain consistency.

---

## Hospitality Filter Encoding

Hotel and restaurant filters use integer encoding:

| Value | Meaning |
|-------|---------|
| -1 | Unknown |
| 0 | None |
| 1 | In vicinity |
| 2 | At airport |

**Filter semantics:** "In vicinity" (1) includes "at airport" (2). So filtering for `hotel >= 1` means "has hotel nearby or at airport".

---

## Supported Filters Summary

| Filter | Type | Backend | Client-Side | UI Control |
|--------|------|---------|-------------|------------|
| `country` | string | ✅ | ✅ | Select |
| `has_procedures` | boolean | ✅ | ✅ | Checkbox |
| `has_aip_data` | boolean | ✅ | ✅ | Checkbox |
| `has_hard_runway` | boolean | ✅ | ✅ | Checkbox |
| `point_of_entry` | boolean | ✅ | ✅ | Checkbox |
| `fuel_type` | string | ✅ | ❌ | Select |
| `has_avgas` | boolean | ✅ | ❌ | Legacy |
| `has_jet_a` | boolean | ✅ | ❌ | Legacy |
| `hotel` | number | ✅ | ❌ | Select |
| `restaurant` | number | ✅ | ❌ | Select |
| `min_runway_length_ft` | number | ✅ | ❌ | Input |
| `max_runway_length_ft` | number | ✅ | ❌ | Input |
| `max_landing_fee` | number | ✅ | ❌ | Input |
| `trip_distance` | number | ✅ | ❌ | — |
| `exclude_large_airports` | boolean | ✅ | ❌ | Checkbox |
| `max_hours_notice` | number | ✅ | ❌ | Input |
| `search_radius_nm` | number | ✅ | ❌ | Input |
| `enroute_distance_max_nm` | number | ✅ | ❌ | Input |

---

## Debugging

```javascript
// Browser console

// Current filters
store.getState().filters

// Apply filters manually
store.getState().setFilters({ country: 'FR', has_procedures: true })

// Check filtered airports
store.getState().filteredAirports.length
```

```python
# Backend - test filter
from shared.filtering.filter_engine import FilterEngine

engine = FilterEngine()
result = engine.apply(airports, {"country": "FR", "has_procedures": True})
```
