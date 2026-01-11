# Aviation Agent - Next Implementation Plan

## Overview

This document tracks planned enhancements to the aviation agent, focusing on flight time/distance calculations and multi-tool architecture.

---

## Phase 1: Flight Distance & Time Tool

### New Tool: `calculate_flight_distance`

**Purpose**: Calculate distance and flight time between two airports.

**Parameters**:
```python
{
    "from_location": str,        # Required - ICAO or location query
    "to_location": str,          # Required - ICAO or location query
    "cruise_speed_kts": float,   # Optional - explicit cruise speed
    "aircraft_type": str,        # Optional - e.g., "c172", "sr22"
}
```

**Returns**:
```python
{
    "from": {"icao": "EGTF", "name": "Fairoaks", "lat": 51.348, "lon": -0.559},
    "to": {"icao": "LFMD", "name": "Cannes-Mandelieu", "lat": 43.542, "lon": 6.953},
    "distance_nm": 596.4,
    "cruise_speed_kts": 120,           # null if not provided/resolved
    "cruise_speed_source": "typical Cessna 172 cruise",  # or "provided", null
    "estimated_time_hours": 4.97,      # null if no speed
    "estimated_time_formatted": "4h 58m",  # null if no speed
    "needs_speed_input": false,        # true if time requested but no speed
    "visualization": {
        "type": "route",
        "route": {"from": {...}, "to": {...}}
    }
}
```

### Aircraft Speed Lookup Table

Small curated list of common GA aircraft with typical cruise speeds:

```python
AIRCRAFT_CRUISE_SPEEDS = {
    "c150": {"name": "Cessna 150", "cruise_kts": 105, "range": "100-110"},
    "c152": {"name": "Cessna 152", "cruise_kts": 110, "range": "105-115"},
    "c172": {"name": "Cessna 172", "cruise_kts": 120, "range": "110-130"},
    "c182": {"name": "Cessna 182", "cruise_kts": 145, "range": "140-155"},
    "c206": {"name": "Cessna 206", "cruise_kts": 150, "range": "145-160"},
    "pa28": {"name": "Piper PA-28 Cherokee", "cruise_kts": 125, "range": "115-135"},
    "pa32": {"name": "Piper PA-32 Cherokee Six", "cruise_kts": 150, "range": "140-160"},
    "pa34": {"name": "Piper PA-34 Seneca", "cruise_kts": 180, "range": "170-190"},
    "sr20": {"name": "Cirrus SR20", "cruise_kts": 155, "range": "150-165"},
    "sr22": {"name": "Cirrus SR22", "cruise_kts": 170, "range": "170-190"},
    "s22t": {"name": "Cirrus SR22T", "cruise_kts": 180, "range": "170-190"},
    "da40": {"name": "Diamond DA40", "cruise_kts": 130, "range": "125-140"},
    "da42": {"name": "Diamond DA42", "cruise_kts": 170, "range": "165-180"},
    "tb10": {"name": "Socata TB10 Tobago", "cruise_kts": 130, "range": "125-140"},
    "tb20": {"name": "Socata TB20 Trinidad", "cruise_kts": 155, "range": "150-165"},
    "dr400": {"name": "Robin DR400", "cruise_kts": 125, "range": "120-135"},
}
```

### Speed Resolution Logic

```python
def resolve_cruise_speed(
    cruise_speed_kts: float | None,
    aircraft_type: str | None
) -> tuple[float | None, str | None]:
    """Returns (speed, source_description) or (None, None)."""
    if cruise_speed_kts:
        return cruise_speed_kts, "provided"
    if aircraft_type:
        normalized = normalize_aircraft_type(aircraft_type)  # "Cessna 172" -> "c172"
        data = AIRCRAFT_CRUISE_SPEEDS.get(normalized)
        if data:
            return data["cruise_kts"], f"typical {data['name']} cruise"
    return None, None
```

### Conversation Examples

| User Query | Tool Response | Formatter Output |
|------------|---------------|------------------|
| "How far is EGTF from LFMD" | `distance_nm: 596, needs_speed_input: false` | "The distance is 596 nm." |
| "How long to fly EGTF to LFMD" | `needs_speed_input: true` | "The distance is 596 nm. To estimate flight time, what's your cruise speed or aircraft type?" |
| "How long with a C172" | `cruise_speed_kts: 120, estimated_time: "4h 58m"` | "At typical C172 cruise (~120 kts), estimated flight time is ~5 hours." |
| Follow-up: "140 knots" | `cruise_speed_kts: 140, estimated_time: "4h 16m"` | "At 140 kts, estimated flight time is 4h 16m." |

---

## Phase 2: Time-Constrained Airport Search

### Enhancement to `find_airports_near_route`

**New Optional Parameters**:
```python
{
    "max_leg_time_hours": float,  # Filter airports within this flight time from departure
    "cruise_speed_kts": float,    # Required if max_leg_time_hours provided
    "aircraft_type": str,         # Alternative to cruise_speed_kts
}
```

**Logic**:
- If `max_leg_time_hours` provided, compute `max_distance_nm = max_leg_time_hours * cruise_speed_kts`
- Filter airports where `enroute_distance_nm <= max_distance_nm`

### Example

**Query**: "Where can I stop within 3h flight from EGTF on the way to LFMD with my SR22"

**Planner extracts**:
```python
{
    "tool": "find_airports_near_route",
    "arguments": {
        "from_location": "EGTF",
        "to_location": "LFMD",
        "max_leg_time_hours": 3,
        "aircraft_type": "sr22"
    }
}
```

**Tool computes**: 3h × 180kts = 540nm max, filters airports

---

## Architecture Decision: Single Tool + Conversational Follow-ups

### Decision

**Keep single-tool architecture.** Handle complex queries through natural conversation flow rather than multi-tool execution.

### Rationale

1. **Users naturally use follow-ups**: "How long to fly?" → "At what speed?" → "140 knots" is natural
2. **Simpler architecture**: No multi-tool orchestration, merging, or error multiplication
3. **Lower latency**: Single tool call per turn
4. **Clearer UX**: User understands what info is missing and why

### Implementation Pattern: "Missing Info" Signals

**Generic, reusable pattern** - any tool can return `missing_info` when it needs clarification.

#### Schema

```python
class MissingInfoItem(TypedDict):
    key: str          # Machine-readable identifier
    reason: str       # Why this info is needed
    prompt: str       # Suggested question for user
    examples: list[str]  # Help user understand what to provide

# Tool response includes
{
    # ... partial results ...
    "missing_info": [MissingInfoItem, ...]  # Empty list if nothing missing
}
```

#### Example: Flight Distance Tool

```python
{
    "distance_nm": 596.4,
    "estimated_time_formatted": null,
    "missing_info": [{
        "key": "cruise_speed",
        "reason": "Required to calculate flight time",
        "prompt": "What's your cruise speed or aircraft type?",
        "examples": ["120 knots", "Cessna 172", "SR22"]
    }]
}
```

#### Example: Ambiguous Location

```python
{
    "candidates": [
        {"icao": "LFPG", "name": "Paris Charles de Gaulle"},
        {"icao": "LFPO", "name": "Paris Orly"},
        {"icao": "LFPB", "name": "Paris Le Bourget"}
    ],
    "missing_info": [{
        "key": "location_clarification",
        "reason": "Multiple airports match 'Paris'",
        "prompt": "Which Paris airport did you mean?",
        "examples": ["Le Bourget", "LFPB", "the GA-friendly one"]
    }]
}
```

#### Example: Country Not Specified (Rules)

```python
{
    "missing_info": [{
        "key": "country",
        "reason": "Rules vary by country",
        "prompt": "Which country are you asking about?",
        "examples": ["France", "UK", "Germany"]
    }]
}
```

#### Example: Time Constraint Without Speed

```python
{
    "airports": [...],  # All airports along route (unfiltered)
    "missing_info": [{
        "key": "cruise_speed",
        "reason": "Required to filter airports within 3h flight time",
        "prompt": "What's your cruise speed to calculate the 3-hour range?",
        "examples": ["120 knots", "Cessna 172"]
    }]
}
```

Formatter sees `missing_info` and asks the follow-up question naturally, incorporating any partial results already available.

### Conversational Flow Example

```
Turn 1:
  User: "How long to fly from EGTF to LFMD"
  Tool: calculate_flight_distance → {distance: 596, missing_info: {cruise_speed: ...}}
  Answer: "The distance is 596 nm. To estimate flight time, what's your cruise speed or aircraft type?"

Turn 2:
  User: "140 knots"
  Planner: Sees conversation history, extracts speed=140, same route context
  Tool: calculate_flight_distance → {distance: 596, cruise_speed: 140, time: "4h 16m"}
  Answer: "At 140 knots, the estimated flight time is 4 hours 16 minutes."

Turn 3:
  User: "What about with a C172?"
  Planner: Same route, different aircraft
  Tool: calculate_flight_distance → {distance: 596, cruise_speed: 120, source: "typical C172"}
  Answer: "At typical C172 cruise speed (~120 kts), it would take about 5 hours."
```

### Planner Context Awareness

The planner must be context-aware to handle follow-ups:

```python
# Planner prompt guidance
"""
When the user provides missing information (speed, aircraft type, etc.)
in a follow-up message, use the conversation history to:
1. Identify what query they're continuing
2. Extract the newly provided information
3. Call the appropriate tool with complete parameters
"""
```

### Benefits of This Approach

| Aspect | Multi-Tool | Single + Follow-up |
|--------|------------|-------------------|
| Complexity | High | Low |
| Latency per turn | Higher (multiple tools) | Lower (one tool) |
| User clarity | May overwhelm | Clear, guided |
| Error handling | Complex | Simple |
| Token usage | Higher | Lower per turn |

---

## Implementation Priority

1. [x] `calculate_flight_distance` tool with aircraft lookup
2. [x] Add `missing_info` pattern to tool responses (implemented in calculate_flight_distance)
3. [ ] Update planner prompt for follow-up context awareness
4. [ ] Update formatter to handle `missing_info` gracefully
5. [ ] Add `max_leg_time_hours` filter to `find_airports_near_route`
6. [ ] Test conversational flows end-to-end
7. [ ] Add unit tests for `missing_info` behavior
