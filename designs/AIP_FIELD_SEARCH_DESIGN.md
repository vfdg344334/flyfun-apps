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
| `aip_hotel_info` | INTEGER | -1=unknown, 0=none, 1=vicinity, 2=at_airport | 501 |
| `aip_restaurant_info` | INTEGER | -1=unknown, 0=none, 1=vicinity, 2=at_airport | 502 |

**Integer Encoding Convention (IMPORTANT):**
| Integer | String | Meaning |
|---------|--------|---------|
| -1 | `"unknown"` | No data or unrecognized text |
| 0 | `"none"` | Explicit "no" in AIP (e.g., "No hotel", "Nil", "-") |
| 1 | `"vicinity"` | Facility nearby (not on-site) |
| 2 | `"at_airport"` | Facility on-site at the airport |

**Rationale:** All known values are non-negative (`>= 0`). This makes filtering simpler:
- `>= 0` = "we have data for this airport"
- `>= 1` = "has facility (any location)"
- Values are ordinal: 0=none < 1=vicinity < 2=at_airport

**Consistency Requirement:** These names (`unknown`, `none`, `vicinity`, `at_airport`) MUST be used consistently across:
- Database integer encoding
- `features.py` classification functions
- `service.py` return values (decoded strings)
- Filter enum values
- TypeScript types
- UI display labels

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
"none" (value=0): "-", "nil", "no.", explicit negatives
"unknown" (value=-1): empty, unrecognized text (default)
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

**IMPORTANT - Naming Consistency:** Filter enum values MUST match the internal encoding names exactly. This ensures consistency across:
- Database integer encoding
- Service return values
- Filter parameter values
- UI display labels

**Enum Values:**
```python
# Filter values (not a formal enum class, just string values)
"at_airport"  # Most restrictive: only at the airport (aip_*_info == 2)
"vicinity"    # Less restrictive: nearby OR at airport (aip_*_info >= 1)
null          # No filter applied
```

**Key Semantic: "vicinity" includes "at_airport"**
- If a hotel is AT the airport, it's definitely IN the vicinity
- "vicinity" is the less restrictive option (use for "airports with hotels")
- "at_airport" is more restrictive (use for "hotel on-site")

**Mapping to existing data:**
| Filter Value | aip_hotel_info / aip_restaurant_info |
|--------------|--------------------------------------|
| `"vicinity"` | >= 1 (either vicinity or at_airport) |
| `"at_airport"` | == 2 (at_airport only) |
| null | no filter (include all) |

**Note:** We don't expose "none" or "unknown" as filter values - users filter FOR availability, not against it.

#### 1.2 API Filter Parameters

**Add to filter parameters:**
```python
# Enum filters - single parameter per field
hotel: Optional[str] = None      # "at_airport", "vicinity"
restaurant: Optional[str] = None # "at_airport", "vicinity"
```

**Filter Logic (uses GA service, not storage directly):**
```python
def _matches_hospitality(airport: Airport, config: FilterConfig) -> bool:
    # Use GA service for data access (not storage directly)
    # This ensures consistent data access patterns

    if config.hotel is not None:
        hotel_info = get_hospitality_from_service(airport.ident, "hotel")
        if hotel_info is None:
            return False  # No hotel info = exclude (AIP = known data only)
        if config.hotel == "at_airport" and hotel_info != "at_airport":
            return False  # Most restrictive: only at_airport
        if config.hotel == "vicinity" and hotel_info not in ("at_airport", "vicinity"):
            return False  # Less restrictive: vicinity includes at_airport

    if config.restaurant is not None:
        restaurant_info = get_hospitality_from_service(airport.ident, "restaurant")
        if restaurant_info is None:
            return False  # No restaurant info = exclude
        if config.restaurant == "at_airport" and restaurant_info != "at_airport":
            return False  # Most restrictive: only at_airport
        if config.restaurant == "vicinity" and restaurant_info not in ("at_airport", "vicinity"):
            return False  # Less restrictive: vicinity includes at_airport

    return True
```

#### 1.3 Tool Parameter Updates

**Update `shared/airport_tools.py` FILTER_PARAMS:**
```python
FILTER_PARAMS = {
    # ... existing ...
    "hotel": "enum (at_airport|vicinity) - Filter by hotel availability. 'vicinity' = has hotel (nearby or at airport), 'at_airport' = hotel on-site only",
    "restaurant": "enum (at_airport|vicinity) - Filter by restaurant. 'vicinity' = has restaurant (nearby or at airport), 'at_airport' = on-site only",
}
```

#### 1.4 Planner Prompt Updates

**Add to planner filter extraction guidance:**
```
Hospitality Filters (enum values):
- hotel: "at_airport" | "vicinity" | null
- restaurant: "at_airport" | "vicinity" | null

Semantics:
- "vicinity" = has facility (nearby OR at airport) - less restrictive, use for general queries
- "at_airport" = facility on-site only - more restrictive

Extraction rules:
- "airports with hotels" → hotel: "vicinity"
- "hotel at the airport" / "hotel on site" → hotel: "at_airport"
- "hotel nearby" / "hotel in the area" → hotel: "vicinity"
- "lunch stop" / "place to eat" → restaurant: "vicinity"
- "restaurant on the field" → restaurant: "at_airport"
- "overnight with dining" → hotel: "vicinity", restaurant: "vicinity"
```

#### 1.5 UI Changes

**Implemented: Hospitality dropdowns in filter panel (after quick filters row):**
```html
<!-- Hospitality Filters Row -->
<div class="filters-row">
    <div class="filter-field">
        <label for="hotel-filter"><i class="fas fa-bed"></i> Hotel</label>
        <select class="form-select form-select-sm" id="hotel-filter">
            <option value="">Any</option>
            <option value="at_airport">At Airport</option>
            <option value="vicinity">In Vicinity</option>
        </select>
    </div>
    <div class="filter-field">
        <label for="restaurant-filter"><i class="fas fa-utensils"></i> Restaurant</label>
        <select class="form-select form-select-sm" id="restaurant-filter">
            <option value="">Any</option>
            <option value="at_airport">At Airport</option>
            <option value="vicinity">In Vicinity</option>
        </select>
    </div>
</div>
```

**Note:** UI "Any" means no filter (show all airports). Users select "At Airport" or "In Vicinity" to filter. The chatbot uses "vicinity" for general "has hotel" queries.

**Placement:** Added to filters panel in `index.html`, after the quick filters row.

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
| "Airports with hotels" | `hotel: "vicinity"` |
| "Airports with hotel at the airport" | `hotel: "at_airport"` |
| "Airports with restaurants and hotels" | `hotel: "vicinity", restaurant: "vicinity"` |
| "Good lunch stop near Paris" | `restaurant: "vicinity"` (+ location) |
| "Overnight stop with dining on site" | `hotel: "at_airport", restaurant: "at_airport"` |
| "Hotel nearby is fine" | `hotel: "vicinity"` |

### Example Plan

```json
{
  "selected_tool": "find_airports_near_location",
  "arguments": {
    "location_query": "Paris",
    "radius_nm": 50,
    "filters": {
      "restaurant": "vicinity",
      "hotel": "vicinity"
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

**Location:** `shared/filtering/filters/hospitality_filters.py` (follows existing pattern)

**Pattern already established in `pricing_filters.py`:**
```python
class HotelFilter(Filter):
    """Filter airports by hotel availability."""
    name = "hotel"
    description = "Filter by hotel availability (at_airport|vicinity)"

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
            # Use service method (not storage directly) for consistent access
            summary = context.ga_friendliness_service.get_summary_dict(airport.ident)
            if not summary or not summary.get("has_data"):
                return False  # No data - exclude (AIP = known data only)

            # hotel_info is a string: "at_airport", "vicinity", "none", "unknown", or None
            hotel_info = summary.get('hotel_info')
            if hotel_info is None or hotel_info == "unknown":
                return False  # No data - exclude

            if value == "at_airport":
                # Most restrictive: only at_airport
                return hotel_info == "at_airport"
            elif value == "vicinity":
                # Less restrictive: vicinity includes at_airport
                return hotel_info in ("at_airport", "vicinity")
            else:
                return True  # Unknown filter value - don't filter
        except Exception as e:
            logger.warning(f"Error applying hotel filter to {airport.ident}: {e}")
            return False  # Error - exclude (fail closed for AIP filters)
```

**Key design choice: Exclude when no data**
- AIP filters = "show me what we *know*" → exclude unknown
- Different from scoring (fuzzy) - this is exact data
- If GA service unavailable, exclude (fail closed)
- **Use service, not storage directly** - ensures consistent data access patterns

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

1. **Python Filter Class** (`shared/filtering/filters/hospitality_filters.py`) ✅
   - Create `HotelFilter` and `RestaurantFilter`
   - Register in FilterRegistry (`filter_engine.py`)
   - Uses existing `context.ga_friendliness_service` (already available)

2. **TypeScript FilterConfig** (`web/client/ts/store/types.ts`) ✅
   - Add `hotel: 'at_airport' | 'vicinity' | null`
   - Add `restaurant: 'at_airport' | 'vicinity' | null`

3. **LLMIntegration meaningfulFilterKeys** (`web/client/ts/adapters/llm-integration.ts`) ✅
   - Add `'hotel'`, `'restaurant'` to the list

4. **Planner Prompt** (`configs/aviation_agent/prompts/planner_v1.md`) ✅
   - Add filter descriptions and examples

5. **API Endpoint** (`web/server/api/airports.py`) ✅
   - Add explicit `hotel` and `restaurant` query parameters
   - Use `get_icaos_by_hospitality()` for efficient SQL-based filtering

6. **GA Service/Storage** (`shared/ga_friendliness/`) ✅
   - Add `get_icaos_by_hospitality()` to storage and service
   - Enables efficient SQL query for matching ICAOs

7. **UI Components** (`web/client/`) ✅
   - Add filter dropdowns to `index.html`
   - Add event listeners in `ui-manager.ts`
   - Add params to `api-adapter.ts`

8. **Tests**
   - Filter unit tests
   - Integration test for sync verification (ensure all 4 places stay in sync)

---

## Decided

- **Missing Data Handling:** Exclude airports with no GA data when hospitality filter is set.
  - **Rationale:** AIP filters represent *known* data. Users expect exact results.
  - Scores/personas are for fuzzy matching when data is uncertain.
  - AIP filters = "show me what we know" → exclude unknown
  - Persona scores = "best guess" → can include with uncertainty
- **Data Flow:** Option B for web API (efficient SQL query), Option A for filter engine (chatbot)
  - Web API uses `get_icaos_by_hospitality()` for efficient pre-filtering via SQL
  - Filter engine (chatbot path) uses per-airport service calls (less critical for smaller result sets)
- **Filter Sync Strategy:** Solution C (tests) - pragmatic for now
- **FilterContext GA Access:** Already solved - `ToolContext.ga_friendliness_service` exists
- **UI Approach:** Dropdown for enum values (at_airport/vicinity), with empty = no filter
- **Presets:** No dedicated presets - use manual selection or chatbot for complex filter combinations
- **Display Labels:** Text labels first ("Hotel at airport", "Restaurant nearby"), icons can come later
- **Naming Consistency:** Use consistent names across all layers: `at_airport`, `vicinity`, `none`, `unknown`
  - Filter enum values match database encoding names exactly
  - Service returns decoded strings matching these names
  - No translation layer needed between filter values and stored data
- **Unknown vs None Distinction:**
  - `unknown` (-1) = No data or unrecognized text
  - `none` (0) = Explicit "no" in AIP (e.g., "No hotel", "Nil")
  - All known values are non-negative (`>= 0`), making filtering simpler
  - This distinction is important for data quality tracking (how many airports have explicit info vs missing)
- **Service Access:** Filters use `ga_friendliness_service` methods (not storage directly)
  - Ensures consistent data access patterns
  - Service handles decoding and data availability checks
- **API Parameters:** Explicit `hotel` and `restaurant` query parameters added to API endpoints
  - Simpler than generic filters dict for these specific filters
  - FilterEngine still used for chatbot/filter engine path

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
| Maintenance | -1=unknown, 0=none, 1=minor repairs, 2=full maintenance |
| De-icing | -1=unknown, 0=none, 1=available |
| Customs | Already structured via `point_of_entry` + notification |
| Fuel types | Already structured via `has_avgas`, `has_jet_a` |

The pattern: **classify during build, filter on structured values**.

**Implementation Note:** All new AIP fields should follow the same integer encoding convention:
- `-1` = unknown / no data
- `0` = none / explicit "no"
- `1+` = positive values with increasing specificity (ordinal)

