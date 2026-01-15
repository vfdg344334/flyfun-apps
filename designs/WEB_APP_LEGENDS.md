# Web App Legend System

> Legend modes, configuration, classification, and adding new legends.

## Quick Reference

| File | Purpose |
|------|---------|
| `ts/config/legend-configs.ts` | Legend configurations with match functions |
| `ts/utils/legend-classifier.ts` | Generic classification utilities |
| `ts/store/types.ts` | `LegendMode`, `LegendEntry`, `LegendConfig` types |
| `ts/engines/visualization-engine.ts` | Uses configs for marker colors |
| `ts/managers/ui-manager.ts` | Uses configs for legend panel display |

**Key Exports:**
- `NOTIFICATION_LEGEND_CONFIG`, `AIRPORT_TYPE_LEGEND_CONFIG`, etc.
- `classifyData()`, `getColorFromConfig()`, `getStyleFromConfig()`
- `LegendMode` type

**Prerequisites:** Read `WEB_APP_ARCHITECTURE.md` first.

---

## Architecture: Single Source of Truth

Legend display and marker coloring must always be in sync. Both read from shared configuration:

```
┌─────────────────────────────────────────────────────────────┐
│                  config/legend-configs.ts                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  NOTIFICATION_LEGEND_ENTRIES (with match functions)  │    │
│  │  NOTIFICATION_LEGEND_DISPLAY (simplified for UI)     │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
              │                              │
              ▼                              ▼
┌─────────────────────────┐    ┌─────────────────────────────┐
│  visualization-engine   │    │        ui-manager           │
│  getMarkerStyle()       │    │    updateLegendDisplay()    │
│  Uses: getColorFromConfig()  │    Uses: LEGEND_DISPLAY    │
└─────────────────────────┘    └─────────────────────────────┘
```

---

## Legend Entry Structure

Each legend entry defines how to classify and color an airport:

```typescript
interface LegendEntry<TData = Airport> {
  id: string;                        // Bucket ID (e.g., 'h24', 'moderate')
  label: string;                     // Human-readable label
  color: string;                     // Hex color code
  radiusMultiplier?: number;         // Optional marker size scaling
  match: (data: TData) => boolean;   // Classification function
}
```

**Order matters** — first match wins. Entries are evaluated in array order.

```typescript
// Example: First matching entry wins
const entries: LegendEntry[] = [
  { id: 'special', match: (a) => a.isSpecial, color: '#ff0000' },
  { id: 'normal', match: (a) => true, color: '#00ff00' },  // Fallback
];

classifyData(airport, entries); // Returns 'special' if isSpecial, else 'normal'
```

---

## Available Legend Modes

```typescript
type LegendMode =
  | 'airport-type'
  | 'notification'
  | 'runway-length'
  | 'country'
  | 'procedure-precision'
  | 'relevance';
```

---

## Legend Configurations

### Notification Legend

**File:** `config/legend-configs.ts` → `NOTIFICATION_LEGEND_CONFIG`

**Classification order** (first match wins):

| Order | Condition | Color | ID |
|-------|-----------|-------|-----|
| 1 | No notification data | Gray (#95a5a6) | unknown |
| 2 | is_h24 === true | Green (#28a745) | h24 |
| 3 | type='not_available' | Red (#dc3545) | difficult |
| 4 | is_on_request === true | Yellow (#ffc107) | moderate |
| 5 | type='business_day' | Blue (#007bff) | hassle |
| 6 | hours null + type='hours' | Green (#28a745) | easy |
| 7 | hours null/undefined | Gray (#95a5a6) | unknown |
| 8 | hours ≤ 12 | Green (#28a745) | easy |
| 9 | hours 13-24 | Yellow (#ffc107) | moderate |
| 10 | hours 25-48 | Blue (#007bff) | hassle |
| 11 | hours > 48 | Red (#dc3545) | difficult |

**Display buckets** (simplified for legend panel):
- Green: "H24 / ≤12h notice"
- Yellow: "13-24h / On request"
- Blue: "25-48h / Business day"
- Red: ">48h / Not available"
- Gray: "Unknown"

**Color progression:** Green → Yellow → Blue → Red (easy to hard)

### Airport Type Legend

**File:** `config/legend-configs.ts` → `AIRPORT_TYPE_LEGEND_CONFIG`

| Order | Condition | Color | ID |
|-------|-----------|-------|-----|
| 1 | point_of_entry === true | Green (#28a745) | border-crossing |
| 2 | has_procedures === true | Yellow (#ffc107) | with-procedures |
| 3 | Default | Red (#dc3545) | without-procedures |

### Runway Length Legend

**File:** `config/legend-configs.ts` → `RUNWAY_LENGTH_LEGEND_CONFIG`

| Order | Condition | Color | ID |
|-------|-----------|-------|-----|
| 1 | No runway data | Gray (#6c757d) | unknown |
| 2 | > 8000 ft | Green (#28a745) | long |
| 3 | > 4000 ft | Yellow (#ffc107) | medium |
| 4 | Default (< 4000 ft) | Red (#dc3545) | short |

### Country Legend

**File:** `config/legend-configs.ts` → `COUNTRY_LEGEND_CONFIG`

| Order | Condition | Color | ID |
|-------|-----------|-------|-----|
| 1 | ICAO starts with 'LF' | Blue (#007bff) | france |
| 2 | ICAO starts with 'EG' | Red (#dc3545) | uk |
| 3 | ICAO starts with 'ED' | Green (#28a745) | germany |
| 4 | Default | Yellow (#ffc107) | other |

### Procedure Precision Legend

**File:** `config/legend-configs.ts` → `PROCEDURE_PRECISION_LEGEND_CONFIG`

**Special mode:** Airport markers are **transparent**, procedure **lines** are colored.

| Type | Line Color | ID |
|------|-----------|-----|
| ILS (Precision) | Yellow (#ffff00) | precision |
| RNP/RNAV | Blue (#0000ff) | rnp |
| VOR/NDB (Non-Precision) | White (#ffffff) | non-precision |

Configuration uses `useTransparentMarkers: true`.

### Relevance Legend

**File:** API-driven — uses `state.ga.config.relevance_buckets`

This mode loads bucket configuration from the backend API, allowing server-side customization. Falls back to defaults if API unavailable.

Quartile thresholds are computed dynamically based on visible airport scores.

---

## Classification Utilities

### classifyData()

Finds the first matching entry:

```typescript
import { classifyData } from '../utils/legend-classifier';

const entry = classifyData(airport, NOTIFICATION_LEGEND_ENTRIES);
// Returns LegendEntry or undefined
```

### getColorFromConfig()

Gets color directly from config:

```typescript
import { getColorFromConfig } from '../utils/legend-classifier';

const color = getColorFromConfig(airport, NOTIFICATION_LEGEND_CONFIG);
// Returns hex color string (e.g., '#28a745')
```

### getStyleFromConfig()

Gets both color and radius:

```typescript
import { getStyleFromConfig } from '../utils/legend-classifier';

const { color, radius } = getStyleFromConfig(airport, config, baseRadius);
```

---

## Adding a New Legend Mode

### Step 1: Define Types

Add bucket ID type to `store/types.ts`:

```typescript
export type MyNewBucketId = 'category-a' | 'category-b' | 'unknown';
```

### Step 2: Create Legend Config

Add to `config/legend-configs.ts`:

```typescript
export const MY_NEW_LEGEND_ENTRIES: LegendEntry<Airport>[] = [
  {
    id: 'category-a',
    label: 'Category A',
    color: '#28a745',
    match: (airport) => airport.someField === 'valueA',
  },
  {
    id: 'category-b',
    label: 'Category B',
    color: '#ffc107',
    match: (airport) => airport.someField === 'valueB',
  },
  {
    id: 'unknown',
    label: 'Unknown',
    color: '#95a5a6',
    match: () => true, // Default fallback (must be last)
  },
];

export const MY_NEW_LEGEND_DISPLAY: LegendDisplayBucket[] = [
  { id: 'category-a', label: 'Category A', color: '#28a745' },
  { id: 'category-b', label: 'Category B', color: '#ffc107' },
  { id: 'unknown', label: 'Unknown', color: '#95a5a6' },
];

export const MY_NEW_LEGEND_CONFIG: LegendConfig<Airport> = {
  mode: 'my-new-mode',
  displayType: 'color',
  entries: MY_NEW_LEGEND_ENTRIES,
};
```

### Step 3: Add LegendMode Type

Update `store/types.ts`:

```typescript
export type LegendMode =
  | 'airport-type'
  | 'notification'
  // ... existing modes
  | 'my-new-mode'; // Add new mode
```

### Step 4: Update VisualizationEngine

In `visualization-engine.ts`, update `getMarkerStyle()`:

```typescript
import { MY_NEW_LEGEND_CONFIG } from '../config/legend-configs';

case 'my-new-mode':
  color = getColorFromConfig(airport, MY_NEW_LEGEND_CONFIG);
  radius = 7;
  break;
```

### Step 5: Update UIManager

In `ui-manager.ts`, update `updateLegendDisplay()`:

```typescript
import { MY_NEW_LEGEND_DISPLAY } from '../config/legend-configs';

case 'my-new-mode':
  html = MY_NEW_LEGEND_DISPLAY.map(bucket => `
    <div class="legend-item">
      <div class="legend-color" style="background-color: ${bucket.color};"></div>
      <span>${bucket.label}</span>
    </div>
  `).join('');
  break;
```

### Step 6: Add UI Control

Add the new mode to the legend selector dropdown in HTML:

```html
<select id="legend-mode">
  <!-- existing options -->
  <option value="my-new-mode">My New Mode</option>
</select>
```

---

## LLM Legend Switching

The chatbot can automatically switch legends based on query context.

### Tool-to-Legend Mapping

| Tool | Suggested Legend |
|------|-----------------|
| `get_notification_for_airport` | `notification` |
| `get_airport_details` | `airport-type` |
| `find_airports_near_route` | `airport-type` |
| `find_airports_near_location` | `airport-type` |
| `search_airports` | `airport-type` |

### Filter-Based Overrides

Filters take precedence over tool-based mapping:

| Filter | Legend Override | Priority |
|--------|----------------|----------|
| `max_hours_notice` (any value) | `notification` | 110 |
| `point_of_entry: true` | `airport-type` | 100 |
| `has_procedures: true` | `procedure-precision` | 90 |

### Implementation

In `llm-integration.ts`:

```typescript
const TOOL_TO_LEGEND_MAP: Record<string, LegendMode> = {
  'get_notification_for_airport': 'notification',
  'get_airport_details': 'airport-type',
  // ...
};

const FILTER_LEGEND_OVERRIDES = [
  { condition: (f) => f.max_hours_notice != null, legend: 'notification', priority: 110 },
  { condition: (f) => f.point_of_entry === true, legend: 'airport-type', priority: 100 },
  { condition: (f) => f.has_procedures === true, legend: 'procedure-precision', priority: 90 },
];

function applySuggestedLegend(tool: string, filters: FilterConfig): void {
  // Check filter overrides first (higher priority)
  const override = FILTER_LEGEND_OVERRIDES
    .filter(o => o.condition(filters))
    .sort((a, b) => b.priority - a.priority)[0];

  if (override) {
    store.getState().setLegendMode(override.legend);
    return;
  }

  // Fall back to tool-based mapping
  const legend = TOOL_TO_LEGEND_MAP[tool];
  if (legend) {
    store.getState().setLegendMode(legend);
  }
}
```

### Extending Legend Mapping

**Add tool-based mapping:**
```typescript
const TOOL_TO_LEGEND_MAP = {
  'my_new_tool': 'relevant-legend',
  // ...
};
```

**Add filter-based override:**
```typescript
const FILTER_LEGEND_OVERRIDES = [
  { condition: (f) => f.my_filter === true, legend: 'relevant-legend', priority: 85 },
  // ...
];
```

---

## Special Cases

### Transparent Markers (Procedure Precision)

For procedure-precision mode, airport markers are transparent and procedure lines are colored:

```typescript
if (config.useTransparentMarkers) {
  return {
    color: 'rgba(128, 128, 128, 0.3)',
    radius: 5
  };
}
```

### API-Driven Configuration (Relevance)

The relevance legend loads bucket configs from the backend:

```typescript
const buckets = state.ga?.config?.relevance_buckets || DEFAULT_BUCKETS;
```

This pattern can be extended to other legends if server-side configuration is needed.

---

## File Reference Table

| Legend Mode | Config Constant | Display Constant | Where Used |
|-------------|-----------------|------------------|------------|
| `notification` | `NOTIFICATION_LEGEND_CONFIG` | `NOTIFICATION_LEGEND_DISPLAY` | Marker colors, legend panel |
| `airport-type` | `AIRPORT_TYPE_LEGEND_CONFIG` | `AIRPORT_TYPE_LEGEND_DISPLAY` | Marker colors, legend panel |
| `runway-length` | `RUNWAY_LENGTH_LEGEND_CONFIG` | `RUNWAY_LENGTH_LEGEND_DISPLAY` | Marker colors, legend panel |
| `country` | `COUNTRY_LEGEND_CONFIG` | `COUNTRY_LEGEND_DISPLAY` | Marker colors, legend panel |
| `procedure-precision` | `PROCEDURE_PRECISION_LEGEND_CONFIG` | `PROCEDURE_PRECISION_LEGEND_DISPLAY` | Line colors (not markers), legend panel |
| `relevance` | API-driven | API-driven | Marker colors, legend panel |

---

## Testing

To verify legend/marker consistency:

1. Open the app and load airports
2. Select each legend mode from the dropdown
3. Verify legend panel colors match marker colors on the map
4. For notification mode specifically:
   - "On request" airports should be **yellow**
   - "13-24h notice" airports should be **yellow**
   - "25-48h / Business day" should be **blue**

**Historical Note (Bug Fix Context):**
Previously, legend colors were hardcoded separately in two places (legend display and marker coloring), leading to sync issues. The shared configuration pattern was introduced to ensure they always match. If you see a color mismatch between legend and markers, check that both are reading from the same config constant.

---

## Future Improvements

1. **API-driven configs** — Allow server to provide legend configurations (like relevance already does)
2. **Unit tests** — Add tests for classification functions to catch regressions
3. **Unify relevance legend** — Move relevance default buckets to `legend-configs.ts` for consistency

---

## Debugging

```javascript
// Browser console - classify an airport
const airport = store.getState().airports[0];
classifyData(airport, NOTIFICATION_LEGEND_ENTRIES);

// Get color for airport
getColorFromConfig(airport, NOTIFICATION_LEGEND_CONFIG);
```
