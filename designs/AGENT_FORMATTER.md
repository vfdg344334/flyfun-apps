# Aviation Agent Formatter

> Formatter node, strategy-based formatting, and UI payload construction.

## Quick Reference

| File | Purpose |
|------|---------|
| `shared/aviation_agent/formatting.py` | Formatter chains and UI payload |
| `configs/aviation_agent/prompts/formatter_v1.md` | Standard formatter prompt |
| `configs/aviation_agent/prompts/comparison_synthesis_v1.md` | Comparison formatter prompt |

**Key Exports:**
- `formatter_node()` - LangGraph node function
- `build_ui_payload()` - UI payload construction
- `build_formatter_chain()` - Standard formatter chain
- `build_comparison_formatter_chain()` - Comparison chain

**Prerequisites:** Read `AGENT_ARCHITECTURE.md` first.

---

## Strategy-Based Formatting

The formatter detects tool type and uses the appropriate prompt:

```
Tool Result
    ↓
Check _tool_type marker
    ↓
┌────────────────────────────────────┐
│ "comparison" → comparison_formatter │
│ default     → standard_formatter    │
└────────────────────────────────────┘
    ↓
Final Answer + UI Payload
```

### Tool Type Markers

Tools mark themselves with `_tool_type` for formatter routing:

```python
# Comparison tool returns
{
    "_tool_type": "comparison",
    "differences": [...],
    "rules_context": "...",
    "countries": ["FR", "DE"],
}

# Standard tool returns (no marker)
{
    "airports": [...],
    "filter_profile": {...},
}
```

### Formatter Selection

```python
def formatter_node(state: AgentState) -> Dict[str, Any]:
    tool_result = state.get("tool_result") or {}

    if tool_result.get("_tool_type") == "comparison":
        # Use comparison formatter chain
        chain_result = comparison_formatter_chain.invoke({
            "countries": ", ".join(tool_result["countries"]),
            "topic_context": extract_topic(state),
            "rules_context": tool_result["rules_context"],
        })
    else:
        # Use standard formatter chain
        chain_result = formatter_chain.invoke({
            "messages": state.get("messages") or [],
            "tool_result": json.dumps(tool_result),
            "plan": state.get("plan"),
        })

    return {
        "final_answer": chain_result.content,
        "thinking": combine_thinking(state),
        "ui_payload": build_ui_payload(state["plan"], tool_result),
    }
```

---

## Formatter Chains

### Standard Formatter

For most tools — synthesizes natural language answer from data:

```python
def build_formatter_chain(llm: Runnable, system_prompt: str) -> Runnable:
    prompt = ChatPromptTemplate.from_messages([
        ("system", system_prompt),
        MessagesPlaceholder("messages"),
        ("human", "Tool result:\n{tool_result}\n\nFormat a helpful answer."),
    ])
    return prompt | llm
```

**Prompt (`formatter_v1.md`) includes:**
- Present data in user-friendly format
- Handle `missing_info` by asking follow-up
- Cite sources and provide links
- Keep answers concise

### Comparison Formatter

For `compare_rules_between_countries` — synthesizes comparison answer:

```python
def build_comparison_formatter_chain(llm: Runnable) -> Runnable:
    prompt = ChatPromptTemplate.from_messages([
        ("system", COMPARISON_SYNTHESIS_PROMPT),
        ("human", """Countries: {countries}
Topic: {topic_context}
Rules Context:
{rules_context}

Synthesize a clear comparison highlighting key differences."""),
    ])
    return prompt | llm
```

**Prompt (`comparison_synthesis_v1.md`) includes:**
- Highlight key differences between countries
- Organize by topic/category
- Use tables for clarity when appropriate
- Cite specific rules

---

## UI Payload Structure

### Flattened Design

The UI payload uses **flattened commonly-used fields** for easy frontend access:

```python
{
    "kind": "route" | "airport" | "rules",
    "tool": "find_airports_near_route",  # Tool name for frontend context

    # Kind-specific metadata
    "departure": "EGTF",       # For route kind
    "destination": "LFMD",     # For route kind
    "icao": "EGTF",            # For airport kind
    "region": "France",        # For rules kind

    # Flattened common fields
    "filters": {...},          # From tool_result.filter_profile
    "visualization": {...},    # From tool_result.visualization
    "airports": [...],         # From tool_result.airports

    # Optional
    "suggested_queries": [...] # Follow-up suggestions
}
```

### Kind Determination

```python
TOOL_TO_KIND = {
    "search_airports": "route",
    "find_airports_near_location": "route",
    "find_airports_near_route": "route",
    "get_airport_details": "airport",
    "get_notification_for_airport": "airport",
    "calculate_flight_distance": "route",
    "answer_rules_question": "rules",
    "browse_rules": "rules",
    "compare_rules_between_countries": "rules",
}
```

### build_ui_payload Implementation

```python
def build_ui_payload(
    plan: AviationPlan,
    tool_result: dict | None,
    suggested_queries: List[dict] | None = None
) -> dict | None:
    if not plan:
        return None

    tool_name = plan.selected_tool
    kind = TOOL_TO_KIND.get(tool_name, "route")

    payload = {
        "kind": kind,
        "tool": tool_name,
    }

    # Add kind-specific metadata
    if kind == "route":
        args = plan.arguments
        if "from_location" in args:
            payload["departure"] = args["from_location"]
        if "to_location" in args:
            payload["destination"] = args["to_location"]
    elif kind == "airport":
        payload["icao"] = plan.arguments.get("icao_code")
    elif kind == "rules":
        payload["region"] = plan.arguments.get("country_code")

    # Flatten commonly-used fields from tool_result
    if tool_result:
        if "filter_profile" in tool_result:
            payload["filters"] = tool_result["filter_profile"]
        if "visualization" in tool_result:
            payload["visualization"] = tool_result["visualization"]
        if "airports" in tool_result:
            payload["airports"] = tool_result["airports"]

    if suggested_queries:
        payload["suggested_queries"] = suggested_queries

    return payload
```

---

## Visualization Types

Tool results include visualization hints:

| Tool | Visualization Type | Frontend Behavior |
|------|-------------------|-------------------|
| `search_airports` | `markers` | Show airport markers on map |
| `find_airports_near_location` | `point_with_markers` | Show center point + markers |
| `find_airports_near_route` | `route_with_markers` | Draw route line + markers |
| `get_airport_details` | `marker_with_details` | Show marker + details panel |
| `calculate_flight_distance` | `route` | Draw route line only |

### Example Visualization Payload

```python
"visualization": {
    "type": "route_with_markers",
    "route": {
        "from": {"icao": "EGTF", "lat": 51.348, "lon": -0.559},
        "to": {"icao": "LFMD", "lat": 43.542, "lon": 6.953}
    },
    "markers": [
        {"icao": "LFPB", "lat": 48.969, "lon": 2.441, "highlight": true}
    ]
}
```

---

## Handling missing_info

When tool result contains `missing_info`, formatter asks follow-up:

```python
# Tool result
{
    "distance_nm": 596.4,
    "estimated_time_formatted": None,
    "missing_info": [{
        "key": "cruise_speed",
        "reason": "Required to calculate flight time",
        "prompt": "What's your cruise speed or aircraft type?",
        "examples": ["120 knots", "Cessna 172", "SR22"]
    }]
}

# Formatter produces
"The distance from EGTF to LFMD is 596 nautical miles.

To estimate flight time, what's your cruise speed or aircraft type?
(e.g., 120 knots, Cessna 172)"
```

### Formatter Prompt Guidance

```markdown
**Missing Information:**
If tool result contains `missing_info`:
1. Present any partial results first
2. Ask the follow-up question naturally
3. Include examples to help user
```

---

## Thinking Combination

The formatter combines planning and formatting reasoning:

```python
def combine_thinking(state: AgentState) -> str:
    parts = []
    if state.get("planning_reasoning"):
        parts.append(f"Planning: {state['planning_reasoning']}")
    if state.get("formatting_reasoning"):
        parts.append(f"Formatting: {state['formatting_reasoning']}")
    return "\n".join(parts)
```

This `thinking` field is sent to frontend for transparency.

---

## Why This Design?

### Stable for UI

Only `kind`, `tool`, and flattened fields matter. Internal structure can evolve.

### Convenient Access

```typescript
// Frontend can directly access
ui_payload.filters.has_avgas
ui_payload.airports[0].icao
ui_payload.visualization.type
```

### Tool-Based Context

Frontend uses `tool` field for context-aware behavior:

```typescript
if (ui_payload.tool === 'get_notification_for_airport') {
    switchLegendMode('notification');
}
```

---

## Testing

```python
# test_formatting.py
def test_ui_payload_structure():
    """UI payload has stable structure."""
    plan = AviationPlan(
        selected_tool="find_airports_near_route",
        arguments={"from_location": "EGTF", "to_location": "LFMD"}
    )
    tool_result = {
        "airports": [{"icao": "LFPB"}],
        "filter_profile": {"has_avgas": True}
    }

    payload = build_ui_payload(plan, tool_result)

    assert payload["kind"] == "route"
    assert payload["tool"] == "find_airports_near_route"
    assert payload["departure"] == "EGTF"
    assert "filters" in payload
    assert "airports" in payload


def test_missing_info_handling():
    """Formatter asks follow-up for missing info."""
    tool_result = {
        "distance_nm": 596,
        "missing_info": [{"prompt": "What speed?"}]
    }

    answer = formatter.invoke({"tool_result": tool_result})
    assert "speed" in answer.content.lower()
```

---

## Debugging

```bash
# See UI payload
python tools/avdbg.py "Find airports near Paris" --ui

# Output:
# UI Payload:
#   kind: route
#   tool: find_airports_near_location
#   filters: {}
#   airports: [...]
```

```python
# In Python
from shared.aviation_agent.formatting import build_ui_payload

payload = build_ui_payload(plan, tool_result)
print(json.dumps(payload, indent=2))
```
