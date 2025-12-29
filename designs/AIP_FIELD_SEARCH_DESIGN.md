# AIP Field Search Design

## Overview

This document describes the design for enhanced AIP (Aeronautical Information Publication) field search capabilities, focusing on **structured search** using preprocessed/classified AIP data. The approach mirrors the existing pattern used for hospitality fields (hotel/restaurant), where raw AIP text is classified into structured values during the build phase.

## Design Philosophy

**Key Insight:** Free-form text search on AIP fields (e.g., "Maintenance contains 'available'") is unreliable because:
1. AIP text varies wildly across countries and sources
2. Substring matching produces inconsistent results
3. Users can't know what terms to search for

**Better Approach:** Preprocess AIP text into structured, searchable values:
- Parse and classify during build phase (like `aip_hotel_info`)
- Expose simple boolean/enum filters to users
- Let the preprocessing handle text variation

---

## Current State Analysis

### Existing Structured AIP Fields

**Raw Fields (from euro_aip extraction, classified during build):**
| Field | Type | Values | Source std_field_id |
|-------|------|--------|---------------------|
| `aip_ifr_available` | INTEGER | 0-4 (VFR only → ILS) | 207 |
| `aip_night_available` | INTEGER | 0-1 | - |
| `aip_hotel_info` | INTEGER | 0=none, 1=vicinity, 2=at_airport | 501 |
| `aip_restaurant_info` | INTEGER | 0=none, 1=vicinity, 2=at_airport | 502 |

**Computed Feature Scores:**
| Feature | Computation | Range |
|---------|-------------|-------|
| `aip_ops_ifr_score` | lookup_table on aip_ifr_available | [0.0, 1.0] |
| `aip_hospitality_score` | weighted_sum(hotel: 0.4, restaurant: 0.6) | [0.0, 1.0] |

**Text Classification Pattern (from `features.py`):**
```python
# Hospitality classification using regex patterns
"at_airport" (value=2): "yes", "at airport", "on site", "in terminal"
"vicinity" (value=1): "nearby", "within N km", "near the airport"
"none" (value=0): empty, "-", "no.", unrecognized
```

### Current Limitations

1. **Agent Tools Gap:** Aviation agent tools don't expose hospitality filtering
2. **UI Hidden:** AIP filter section is collapsed/hard to discover
3. **Only 2 Hospitality Fields:** Hotel and restaurant are classified, but other useful fields are not

---

## Requirements

### R1: Structured Hospitality Search
- Search by hotel/restaurant availability using structured values
- Example: "has hotel at airport" vs "has hotel nearby"
- Example: "has restaurant" (any location)
- Available from both UI and chatbot

### R2: Chatbot Tool Integration
- Agent should be able to filter airports by hospitality
- Should work with existing `search_airports`, `find_airports_near_location`, `find_airports_near_route` tools
- Natural language queries like "airports with hotels and restaurants"

### R3: UI Improvements
- Make hospitality filtering discoverable
- Add as first-class UI option alongside other filters

### R4: Extensibility
- Pattern should support adding more structured AIP fields in the future
- Example candidates: maintenance, de-icing, customs (already exists as `point_of_entry`)

---

## Proposed Design

### Phase 1: Hospitality Filters

#### 1.1 Enum Design

**Principle:** Use enums instead of multiple booleans. Each structured field has a single filter parameter with enum values.

**Enum Values:**
```python
class HospitalityFilter(str, Enum):
    ANY = "any"           # Has hotel/restaurant (onsite OR nearby)
    ONSITE = "onsite"     # Only at the airport (aip_*_info == 2)
    NEARBY = "nearby"     # Only in vicinity (aip_*_info == 1)
    # null/not set = no filter applied
```

**Mapping to existing data:**
| Filter Value | aip_hotel_info / aip_restaurant_info |
|--------------|--------------------------------------|
| `"any"` | >= 1 (either nearby or onsite) |
| `"onsite"` | == 2 |
| `"nearby"` | == 1 |
| null | no filter (include all) |

**Note:** We don't expose "none" or "unknown" as filter values - users filter FOR availability, not against it.

#### 1.2 API Filter Parameters

**Add to filter parameters:**
```python
# Enum filters - single parameter per field
hotel: Optional[str] = None      # "any", "onsite", "nearby"
restaurant: Optional[str] = None # "any", "onsite", "nearby"
```

**Filter Logic:**
```python
def _matches_hospitality(airport: Airport, config: FilterConfig) -> bool:
    ga_data = getattr(airport, 'ga', None)

    # AIP filters require known data - exclude if no GA data
    if config.hotel is not None or config.restaurant is not None:
        if not ga_data:
            return False  # No data = exclude (AIP = known data only)

    if config.hotel is not None:
        hotel_info = ga_data.get('aip_hotel_info')
        if hotel_info is None:
            return False  # No hotel info = exclude
        if config.hotel == "any" and hotel_info < 1:
            return False
        if config.hotel == "onsite" and hotel_info != 2:
            return False
        if config.hotel == "nearby" and hotel_info != 1:
            return False

    if config.restaurant is not None:
        restaurant_info = ga_data.get('aip_restaurant_info')
        if restaurant_info is None:
            return False  # No restaurant info = exclude
        if config.restaurant == "any" and restaurant_info < 1:
            return False
        if config.restaurant == "onsite" and restaurant_info != 2:
            return False
        if config.restaurant == "nearby" and restaurant_info != 1:
            return False

    return True
```

#### 1.3 Tool Parameter Updates

**Update `shared/airport_tools.py` FILTER_PARAMS:**
```python
FILTER_PARAMS = {
    # ... existing ...
    "hotel": "enum (any|onsite|nearby) - Filter by hotel availability. 'any' = has hotel, 'onsite' = hotel at airport, 'nearby' = hotel in vicinity",
    "restaurant": "enum (any|onsite|nearby) - Filter by restaurant availability. 'any' = has restaurant, 'onsite' = at airport, 'nearby' = in vicinity",
}
```

#### 1.4 Planner Prompt Updates

**Add to planner filter extraction guidance:**
```
Hospitality Filters (enum values):
- hotel: "any" | "onsite" | "nearby" | null
- restaurant: "any" | "onsite" | "nearby" | null

Extraction rules:
- "airports with hotels" → hotel: "any"
- "hotel at the airport" / "hotel on site" → hotel: "onsite"
- "hotel nearby" / "hotel in the area" → hotel: "nearby"
- "lunch stop" / "place to eat" → restaurant: "any"
- "restaurant on the field" → restaurant: "onsite"
- "overnight with dining" → hotel: "any", restaurant: "any"
```

#### 1.5 UI Changes

**Add hospitality dropdowns to filter panel:**
```html
<div class="filter-group" id="hospitality-filters">
  <label class="filter-group-label">Hospitality</label>

  <div class="filter-row">
    <label for="hotel-filter">Hotel</label>
    <select id="hotel-filter">
      <option value="">Any</option>
      <option value="any">Available (any)</option>
      <option value="onsite">On-site only</option>
      <option value="nearby">Nearby only</option>
    </select>
  </div>

  <div class="filter-row">
    <label for="restaurant-filter">Restaurant</label>
    <select id="restaurant-filter">
      <option value="">Any</option>
      <option value="any">Available (any)</option>
      <option value="onsite">On-site only</option>
      <option value="nearby">Nearby only</option>
    </select>
  </div>
</div>
```

**Alternative: Checkbox group (simpler UX for common case):**
```html
<div class="filter-group" id="hospitality-filters">
  <label class="filter-group-label">Hospitality</label>
  <div class="filter-options">
    <label><input type="checkbox" id="has-hotel" value="any"> Hotel</label>
    <label><input type="checkbox" id="has-restaurant" value="any"> Restaurant</label>
  </div>
  <details class="advanced-options">
    <summary>Location options</summary>
    <div class="radio-group">
      <label><input type="radio" name="hotel-location" value="any" checked> Any</label>
      <label><input type="radio" name="hotel-location" value="onsite"> On-site</label>
      <label><input type="radio" name="hotel-location" value="nearby"> Nearby</label>
    </div>
  </details>
</div>
```

**Placement:** Add to main filter panel, after fuel filters (logical grouping for trip planning).

---

### Phase 2: Additional Structured Fields (Future)

Following the same enum pattern, we could add more structured AIP fields. Candidates:

| Candidate Field | std_field_id | Enum Values | Use Case |
|-----------------|--------------|-------------|----------|
| Maintenance | ? | `none`, `minor`, `full` | Aircraft servicing |
| De-icing | ? | `none`, `available` | Winter operations |
| Hangar | ? | `none`, `available` | Overnight parking |
| Night ops | (already have) | `none`, `available` | Night flying |

**Example: Maintenance filter**
```python
# Enum values
maintenance: "any" | "minor" | "full" | null

# Mapping
"any" → aip_maintenance_info >= 1
"minor" → aip_maintenance_info >= 1 (minor or better)
"full" → aip_maintenance_info == 2 (full service only)
```

**Implementation pattern:**
1. Add text classification logic to `features.py` (regex patterns)
2. Add integer field to `ga_airfield_stats` table (e.g., `aip_maintenance_info`)
3. Extract and classify during build phase
4. Add enum filter parameter to API/tools
5. Add UI dropdown/toggle

---

## Chatbot Integration Details

### Natural Language Query Examples

| User Query | Extracted Filters |
|------------|-------------------|
| "Airports with hotels" | `hotel: "any"` |
| "Airports with hotel at the airport" | `hotel: "onsite"` |
| "Airports with restaurants and hotels" | `hotel: "any", restaurant: "any"` |
| "Good lunch stop near Paris" | `restaurant: "any"` (+ location) |
| "Overnight stop with dining on site" | `hotel: "onsite", restaurant: "onsite"` |
| "Hotel nearby is fine" | `hotel: "nearby"` |

### Example Plan

```json
{
  "selected_tool": "find_airports_near_location",
  "arguments": {
    "location_query": "Paris",
    "radius_nm": 50,
    "filters": {
      "restaurant": "any",
      "hotel": "any"
    }
  }
}
```

### Visualization with Hospitality Info

**Airport data in response should include hospitality info for display:**
```json
{
  "icao": "LFAT",
  "name": "Le Touquet",
  "ga": {
    "aip_hotel_info": 2,
    "aip_restaurant_info": 2,
    "aip_hospitality_score": 1.0
  }
}
```

**UI can display badges:** "Hotel on-site", "Restaurant on-site"

---

## Implementation Plan

### Step 1: Add Hospitality Filter Parameters
- Update `FilterConfig` in `shared/filtering/filter_engine.py`
- Add filter logic
- Update API endpoints to accept new parameters

### Step 2: Update Agent Tools
- Add hospitality filters to `FILTER_PARAMS` in `shared/airport_tools.py`
- Update tool descriptions
- Test with agent

### Step 3: Update Planner
- Add hospitality extraction examples to planner prompt
- Test natural language → filter extraction

### Step 4: Update UI
- Add hospitality filter checkboxes to filter panel
- Wire up to store
- Ensure filters work with route/locate searches

### Step 5: Ensure GA Data Inclusion
- Hospitality filters require `include_ga=true` in API calls
- Update default behavior or ensure it's always included when hospitality filters are set

---

## Data Dependencies

1. **GA Stats Database:** Hospitality info comes from `ga_airfield_stats` table
2. **Build Phase:** `aip_hotel_info` and `aip_restaurant_info` are classified during GA stats build
3. **API Include Flag:** Need `include_ga=true` to get hospitality data

---

## Architecture Considerations

### Current Filter Architecture Analysis

**Single Source of Truth (Current State):**
```
shared/filtering/filter_engine.py + shared/filtering/filters/*.py
```

**Problem: Filter Definitions Are Duplicated in 4 Places:**
| Location | What's Duplicated |
|----------|-------------------|
| `shared/filtering/filters/*.py` | Filter implementation & name |
| `web/client/ts/store/types.ts` | FilterConfig interface (TypeScript) |
| `web/client/ts/adapters/llm-integration.ts` | `meaningfulFilterKeys` hardcoded list |
| `configs/aviation_agent/prompts/planner_v1.md` | Filter list in LLM prompt |

**Risk:** These 4 places can drift apart. Adding `hotel` filter requires updates in all 4.

### Raw Data vs Computed Scores

**Important Distinction:**
- **Raw fields:** `aip_hotel_info` (0, 1, 2), `aip_restaurant_info` (0, 1, 2)
- **Computed score:** `ga_hospitality_score` (0.0-1.0 weighted sum)

**For filtering, use RAW fields:**
- "has hotel onsite" → `aip_hotel_info == 2` ✅ (precise)
- "has hotel" → `aip_hotel_info >= 1` ✅ (precise)
- "hospitality_score > 0.5" ❌ (what does 0.5 mean to user?)

The computed score is useful for **ranking**, not filtering.

### Data Flow for Hospitality Filtering

**Current GA data flow:**
```
API Request
    ↓
Query euro_aip DB (airports)
    ↓
Get list of ICAOs
    ↓
Batch fetch GA data: ga_service.get_summaries_batch(icaos)
    ↓
Enrich response
```

**Problem:** Filtering happens BEFORE GA data is fetched. We can't filter by hospitality efficiently.

**Options:**

**Option A: Post-fetch filtering (simple, inefficient)**
```
Fetch airports → Fetch GA data → Filter by hospitality → Return
```
- Simple to implement
- Works with current architecture
- Inefficient for large result sets (fetch all, then filter)
- May hit GA service unnecessarily

**Option B: Push filter to GA database query (efficient, more complex)**
```
Query GA DB with hospitality filter → Get ICAOs → Query airports by ICAOs
```
- Efficient (filter at source)
- Requires GA service to expose filter API
- Changes data flow direction

**Option C: Denormalize hospitality to euro_aip (efficient, more work)**
```
Build phase: Copy aip_hotel_info to euro_aip airport record
Filter: Query euro_aip with hospitality filter
```
- Most efficient (single DB query)
- Requires schema change + rebuild
- Data duplication (but acceptable for performance)

**Recommendation: Start with Option A**, measure performance. If too slow, consider Option C.

### Filter Implementation Location

**Location:** `shared/filtering/filters/hospitality.py` (new file, follows existing pattern)

**Pattern already established in `pricing_filters.py`:**
```python
class HotelFilter(Filter):
    """Filter airports by hotel availability."""
    name = "hotel"
    description = "Filter by hotel availability (any|onsite|nearby)"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None:
            return True  # Not filtering by hotel

        if not context or not context.ga_friendliness_service:
            return False  # No GA service - exclude (AIP = known data only)

        try:
            summary = context.ga_friendliness_service.get_summary(airport.ident)
            if not summary or not summary.features:
                return False  # No data - exclude (AIP = known data only)

            hotel_info = summary.features.get('aip_hotel_info')
            if hotel_info is None:
                return False  # No hotel info - exclude

            if value == "any":
                return hotel_info >= 1
            elif value == "onsite":
                return hotel_info == 2
            elif value == "nearby":
                return hotel_info == 1
            else:
                return True  # Unknown filter value - don't filter
        except Exception:
            return False  # Error - exclude (fail closed for AIP filters)
```

**Key design choice: Exclude when no data**
- AIP filters = "show me what we *know*" → exclude unknown
- Different from scoring (fuzzy) - this is exact data
- If GA service unavailable, exclude (fail closed)

### Keeping Definitions in Sync

**Current problem:** 4 places must stay synchronized manually.

**Potential solutions:**

**Solution A: Code generation**
- Define filters in single YAML/JSON file
- Generate Python filters, TypeScript types, prompt text
- Build step ensures consistency

**Solution B: Runtime metadata export**
- FilterRegistry exports metadata (name, type, description)
- TypeScript fetches from API endpoint `/api/filters/metadata`
- Planner prompt built from same metadata

**Solution C: Accept duplication, add tests**
- Keep current architecture
- Add integration test that verifies all 4 places are in sync
- Fail CI if they drift

**Recommendation for this feature:** Option C for now (pragmatic). Consider Option B for future.

### Checklist for Adding Hospitality Filters

To maintain consistency, adding `hotel` and `restaurant` filters requires:

1. **Python Filter Class** (`shared/filtering/filters/hospitality.py`)
   - Create `HotelFilter` and `RestaurantFilter`
   - Register in FilterRegistry
   - Uses existing `context.ga_friendliness_service` (already available)

2. **TypeScript FilterConfig** (`web/client/ts/store/types.ts`)
   - Add `hotel: 'any' | 'onsite' | 'nearby' | null`
   - Add `restaurant: 'any' | 'onsite' | 'nearby' | null`

3. **LLMIntegration meaningfulFilterKeys** (`web/client/ts/adapters/llm-integration.ts`)
   - Add `'hotel'`, `'restaurant'` to the list

4. **Planner Prompt** (`configs/aviation_agent/prompts/planner_v1.md`)
   - Add filter descriptions and examples

5. **API Endpoint** (`web/server/api/airports.py`)
   - Add query parameters
   - Ensure filters are passed to FilterEngine

6. **UI Components** (`web/client/`)
   - Add filter controls
   - Wire to store

7. **Tests**
   - Filter unit tests
   - Integration test for sync verification (ensure all 4 places stay in sync)

---

## Decided

- **Missing Data Handling:** Exclude airports with no GA data when hospitality filter is set.
  - **Rationale:** AIP filters represent *known* data. Users expect exact results.
  - Scores/personas are for fuzzy matching when data is uncertain.
  - AIP filters = "show me what we know" → exclude unknown
  - Persona scores = "best guess" → can include with uncertainty
- **Data Flow:** Option A (post-fetch filtering) - simple, measure first
- **Filter Sync Strategy:** Solution C (tests) - pragmatic for now
- **FilterContext GA Access:** Already solved - `ToolContext.ga_friendliness_service` exists
- **UI Approach:** Dropdown for enum values (any/onsite/nearby)
- **Presets:** No dedicated presets - use manual selection or chatbot for complex filter combinations
- **Display Labels:** Text labels first ("Hotel on-site", "Restaurant nearby"), icons can come later

---

## Appendix: Deferred - Free-Form AIP Field Search

**Status:** Not implementing unless a compelling use case is found.

### What Was Considered

A free-form filter allowing search on any AIP field:
```python
aip_field_filter: {
    "field": "Maintenance",
    "operator": "contains",
    "value": "available"
}
```

### Why Deferred

1. **Unreliable Results:** AIP text varies wildly across countries and sources
   - France: "Maintenance available on request"
   - UK: "Aircraft maintenance: contact operator"
   - Germany: "Wartung nach Vereinbarung"

2. **User Doesn't Know What to Search:** What terms would a user enter for "Maintenance contains '???'"?

3. **Better Pattern Exists:** Preprocess into structured values (like hotel/restaurant), then expose simple boolean filters.

4. **Existing UI Already Has This:** The current AIP filter section provides this functionality for power users who want to explore.

### If Needed Later

If a use case emerges, the implementation would be:
1. Extend `FilterConfig` with `aip_field`, `aip_operator`, `aip_value`
2. Add to agent tool filter parameters
3. Use existing `_matches_aip_field()` logic from `airports.py`

### Candidate Fields for Future Structuring

If specific AIP fields prove useful, classify them like hotel/restaurant:

| Field | Potential Classification |
|-------|-------------------------|
| Maintenance | 0=none, 1=minor repairs, 2=full maintenance |
| De-icing | 0=none, 1=available |
| Customs | Already structured via `point_of_entry` + notification |
| Fuel types | Already structured via `has_avgas`, `has_jet_a` |

The pattern: **classify during build, filter on structured values**.

