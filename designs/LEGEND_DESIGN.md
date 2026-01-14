# Legend Configuration Design

## Overview

This document describes the architecture for map legend configuration in the FlyFun Airport Explorer. The system ensures legend display and marker coloring are always in sync by using a shared configuration that both components read from.

## Problem Solved

Previously, legend colors were hardcoded separately in two places:
- **Legend display**: `ui-manager.ts` → `updateLegendDisplay()`
- **Marker coloring**: `visualization-engine.ts` → `getMarkerStyle()` and mode-specific methods

This led to sync issues where the legend showed one color but markers used another.

## Architecture

### Single Source of Truth

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
│  getNotificationColor() │    │    updateLegendDisplay()    │
│                         │    │                             │
│  Uses: getColorFromConfig()  │    Uses: NOTIFICATION_LEGEND_DISPLAY │
└─────────────────────────┘    └─────────────────────────────┘
```

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| Type definitions | `store/types.ts` | `LegendEntry`, `LegendConfig`, `LegendDisplayBucket` |
| Legend configs | `config/legend-configs.ts` | Classification entries with match functions |
| Classifier utility | `utils/legend-classifier.ts` | Generic `classifyData()`, `getColorFromConfig()` |
| Visualization | `engines/visualization-engine.ts` | Uses shared config for marker colors |
| UI Manager | `managers/ui-manager.ts` | Uses shared display buckets for legend panel |

## Legend Entry Structure

Each legend entry defines:

```typescript
interface LegendEntry<TData = Airport> {
  id: string;              // Bucket identifier (e.g., 'h24', 'moderate')
  label: string;           // Human-readable label
  color: string;           // Hex color code
  radiusMultiplier?: number; // Optional marker size scaling
  match: (data: TData) => boolean; // Classification function
}
```

**Order matters** - first match wins. Entries are evaluated in array order.

## Current Legend Modes

### Notification Legend

**File**: `config/legend-configs.ts`

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

**Color progression**: Green → Yellow → Blue → Red (easy to hard)

### Airport Type Legend

**File**: `config/legend-configs.ts` - `AIRPORT_TYPE_LEGEND_CONFIG`

| Order | Condition | Color | ID |
|-------|-----------|-------|-----|
| 1 | point_of_entry === true | Green (#28a745) | border-crossing |
| 2 | has_procedures === true | Yellow (#ffc107) | with-procedures |
| 3 | Default | Red (#dc3545) | without-procedures |

### Runway Length Legend

**File**: `config/legend-configs.ts` - `RUNWAY_LENGTH_LEGEND_CONFIG`

| Order | Condition | Color | ID |
|-------|-----------|-------|-----|
| 1 | No runway data | Gray (#6c757d) | unknown |
| 2 | > 8000 ft | Green (#28a745) | long |
| 3 | > 4000 ft | Yellow (#ffc107) | medium |
| 4 | Default (< 4000 ft) | Red (#dc3545) | short |

### Country Legend

**File**: `config/legend-configs.ts` - `COUNTRY_LEGEND_CONFIG`

| Order | Condition | Color | ID |
|-------|-----------|-------|-----|
| 1 | ICAO starts with 'LF' | Blue (#007bff) | france |
| 2 | ICAO starts with 'EG' | Red (#dc3545) | uk |
| 3 | ICAO starts with 'ED' | Green (#28a745) | germany |
| 4 | Default | Yellow (#ffc107) | other |

### Procedure Precision Legend

**File**: `config/legend-configs.ts` - `PROCEDURE_PRECISION_LEGEND_CONFIG`

This mode is special - airport markers are **transparent**, and procedure **lines** are colored.

| Type | Line Color | ID |
|------|-----------|-----|
| ILS (Precision) | Yellow (#ffff00) | precision |
| RNP/RNAV | Blue (#0000ff) | rnp |
| VOR/NDB (Non-Precision) | White (#ffffff) | non-precision |

Configuration uses `useTransparentMarkers: true`.

### Relevance Legend

**File**: API-driven - uses `state.ga.config.relevance_buckets`

This mode loads bucket configuration from the backend API, allowing server-side customization.
Falls back to defaults if API is unavailable.

## Adding a New Legend Mode

### Step 1: Define Types (if needed)

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
    match: () => true, // Default fallback
  },
];

export const MY_NEW_LEGEND_DISPLAY: LegendDisplayBucket[] = [
  { id: 'category-a', label: 'Category A', color: '#28a745' },
  { id: 'category-b', label: 'Category B', color: '#ffc107' },
  { id: 'unknown', label: 'Unknown', color: '#95a5a6' },
];

export const MY_NEW_LEGEND_CONFIG: LegendConfig<Airport> = {
  mode: 'my-new-mode', // Must match LegendMode type
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

### Step 4: Update Visualization Engine

In `visualization-engine.ts`, update `getMarkerStyle()`:

```typescript
import { MY_NEW_LEGEND_CONFIG } from '../config/legend-configs';

case 'my-new-mode':
  color = getColorFromConfig(airport, MY_NEW_LEGEND_CONFIG);
  radius = 7;
  break;
```

### Step 5: Update UI Manager

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

### Step 6: Add UI Controls

Add the new mode to the legend selector dropdown in the HTML.

## Special Cases

### Procedure-Precision Mode

This mode is special because:
- Airport markers are transparent (`rgba(128, 128, 128, 0.3)`)
- Procedure **lines** are colored (not markers)
- Legend shows line samples, not circle samples

Configuration uses `useTransparentMarkers: true`.

### API-Driven Configuration (Relevance)

The relevance legend loads bucket configs from the backend API:

```typescript
const buckets = state.ga?.config?.relevance_buckets || DEFAULT_BUCKETS;
```

This pattern can be extended to other legends if server-side configuration is needed.

## Utilities

### classifyData()

Finds the first matching entry:

```typescript
const entry = classifyData(airport, NOTIFICATION_LEGEND_ENTRIES);
// Returns LegendEntry or undefined
```

### getColorFromConfig()

Gets color directly from config:

```typescript
const color = getColorFromConfig(airport, NOTIFICATION_LEGEND_CONFIG);
// Returns hex color string
```

### getStyleFromConfig()

Gets both color and radius:

```typescript
const { color, radius } = getStyleFromConfig(airport, config, baseRadius);
```

## Testing

To verify legend/marker consistency:

1. Open the app and load airports
2. Select each legend mode from the dropdown
3. Verify legend panel colors match marker colors on the map
4. For notification mode specifically:
   - "On request" airports should be **blue** (not gray)
   - "13-24h notice" airports should be **blue**

## File References

| File | Purpose |
|------|---------|
| `web/client/ts/store/types.ts` | Type definitions |
| `web/client/ts/config/legend-configs.ts` | Legend configurations |
| `web/client/ts/utils/legend-classifier.ts` | Classification utilities |
| `web/client/ts/engines/visualization-engine.ts` | Marker rendering |
| `web/client/ts/managers/ui-manager.ts` | Legend panel rendering |

## Future Improvements

1. **API-driven configs** - Allow server to provide legend configurations (like relevance already does)
2. **Unit tests** - Add tests for classification functions
3. **Unify relevance legend** - Move relevance default buckets to `legend-configs.ts` for consistency
