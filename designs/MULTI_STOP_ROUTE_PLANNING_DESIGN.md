# Multi-Stop Route Planning Design

Design document for adding multi-stop route planning capability to the aviation agent.

**Last Updated:** 2026-01-10  
**Status:** Planning

---

## Overview

Enable queries like:
- "Route from EGKL to LFKO with 3 stops enroute"
- "First stop within 400nm"  
- "Plan a fuel stop along the route"

---

## Research Summary

### Commercial GA Flight Planning Tools

| Software | Approach | Key Features |
|----------|----------|--------------|
| **ForeFlight Trip Assistant** | Algorithmic optimization | Fuel Stop Advisor auto-suggests stops based on aircraft performance + fuel prices |
| **Voyager/FlyQ** | SmartRouter with optimization | Weighs detour distance vs fuel cost to find lowest total cost |
| **Garmin Pilot** | Manual with data assistance | Pilot chooses stops using fuel price maps and range circles |
| **SkyDemon** | Manual multi-leg | Pilot marks "Land Here"; app calculates each leg separately |

### Algorithm Insights

**Key finding**: Commercial planners use **Dijkstra/A\* graph search**, not simple greedy heuristics.

> "The problem can be modeled as a graph: airports are nodes and viable flight legs (within range) are edges. This is a classic shortest-path problem."

**Why not greedy?**
- Flying till empty → may force expensive fuel stop
- Always cheapest fuel → multiple short hops waste time
- Optimal solution requires global search

### Stop Selection Algorithm (from research)

**Case A: First leg constraint (e.g., "within 400nm")**
1. Find airports where `dist(origin, airport) <= 400nm`
2. Filter "on-the-way": keep within corridor around great-circle line
3. Rank by: progress toward destination, minimal detour, fuel/runway suitability
4. Pick best stop

**Case B: Specific stop count (e.g., "3 stops")**
1. Compute total great-circle distance
2. Split into equal legs: 3 stops → 4 legs → target ≈ total/4
3. For each target leg endpoint, find nearest suitable airport
4. Validate and rebalance if any leg is too long

**Case C: Max leg distance constraint**
- Standard graph problem: edges exist only if `dist(i,j) <= max_leg`
- Find shortest path (fewest legs) OR exactly N stops if requested

### NLU Parsing Requirements

Must recognize:
```
"3 stops", "three stops", "3 fuel stops" → stops_count = 3
"first stop within 400nm" → first_leg_max_nm = 400
"no leg longer than 300nm" → max_leg_nm = 300
```

### Graceful Degradation

If `stops_count > 1` but tool only supports 1 stop:
1. Return single-stop route
2. Add suggestion: "If you share max_leg_nm, I can compute the stops automatically"

---

## Proposed Solution

### Request Schema

```python
@dataclass
class MultiStopRouteRequest:
    from_icao: str
    to_icao: str
    stops_count: Optional[int] = None  # "3 stops"
    first_leg_max_nm: Optional[float] = None  # "first stop within 400nm"
    max_leg_nm: Optional[float] = None  # "no leg longer than X"
    filters: Optional[Dict] = None  # fuel_type, min_runway, etc.
```

### Cost Function

```python
cost = (
    distance_nm * 1.0  # Base distance cost
    + stop_penalty * 30  # ~30nm equivalent per stop
    - persona_score * 50  # Up to 50nm "discount" for good airports
    + fuel_penalty * 500  # Major penalty if no required fuel
    + runway_penalty * 1000  # Eliminate if runway too short
)
```

### Persona Aircraft Performance

Typical ranges for UK/Europe GA:

| Persona | Leg Cap | Fuel | Min Rwy | Cruise |
|---------|---------|------|---------|--------|
| `ifr_touring_sr22` | 700–900nm | avgas | 2000–2500ft | 170–180kts |
| `vfr_budget` | 300–450nm | avgas/mogas | 1200–1800ft | 95–110kts |
| `lunch_stop` | 150–250nm | avgas | 1500–2200ft | 110–125kts |
| `training` | 150–300nm | avgas | 1200–1800ft | 85–100kts |

---

## Implementation

### Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `shared/route_planner.py` | NEW | MultiStopRoutePlanner with A* algorithm |
| `shared/ga_friendliness/models.py` | MODIFY | Add AircraftPerformance model |
| `shared/ga_friendliness/config.py` | MODIFY | Add aircraft data to DEFAULT_PERSONAS |
| `shared/airport_tools.py` | MODIFY | Add plan_multi_leg_route tool |

### Example Output (EGKL → LFKO, ~661nm)

**Request**: "3 stops enroute"

```
EGKL → LFBL (Limoges, ~304nm)
LFBL → LFML (Marseille, ~226nm)  
LFML → LFKJ (Ajaccio, ~182nm)
LFKJ → LFKO (Propriano, ~16nm)
```

### Multi-Turn Human-in-the-Loop Example

For complex multi-stop planning, the AI guides users through iterative stop selection:

```
Human: I want to plan 3 stops between EGKL and LFKO

AI: Ok, let's plan your route step by step. 
    Within what distance would you like the first stop to be from EGKL?

Human: 500nm

AI: Ok, here are the best stops within 500nm of EGKL along the route to LFKO:
    
    1. LFBL (Limoges) - 304nm from EGKL, good progress toward LFKO
    2. LFBP (Pau) - 421nm, IFR-capable with AVGAS
    3. LFBO (Toulouse) - 489nm, major GA hub
    
    Which would you like for your first stop?
Human: LFBL looks good

AI: Great choice! LFBL (Limoges) it is. 
    Now for the second stop - from LFBL it's about 357nm to LFKO.
    Within what distance from LFBL would you like the second stop?
Human: Let's do around 200nm

AI: Here are options around 200nm from LFBL toward LFKO:
    
    1. LFML (Marseille) - 226nm, large GA-friendly airport
    2. LFMP (Perpignan) - 195nm, good facilities
    
    Both work well. LFML gives you a shorter final two legs to Corsica.
```

This iterative approach helps pilots make informed decisions at each step, especially when they have specific preferences or constraints that are hard to specify upfront.

---

## Test Cases (Acceptance Criteria)

| Test | Expected |
|------|----------|
| "Route EGKL→LFKO with 3 stops" | Returns 3 stop ICAOs + 4 leg distances, OR graceful degradation |
| "First stop within 400nm" | Stop where dist(origin, stop1) <= 400nm |
| Unit parsing: "400nm", "400 NM", "400 nautical miles" | All work |
| Explanation quality | Shows why stop was chosen (distance + "on the way") |
| Multi-turn flow | AI asks clarifying questions when constraints unclear |

---

## Phases

| Phase | Effort | Tasks |
|-------|--------|-------|
| **Phase 1** | 2 days | Persona extension, route planner class with A* |
| **Phase 2** | 1 day | Tool + schema registration |
| **Phase 3** | 1 day | NLU handling + graceful degradation |
| **Phase 4** | 1 day | Testing + tuning |
