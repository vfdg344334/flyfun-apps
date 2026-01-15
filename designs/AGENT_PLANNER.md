# Aviation Agent Planner

> Planner node, AviationPlan schema, tool selection, and filter extraction.

## Quick Reference

| File | Purpose |
|------|---------|
| `shared/aviation_agent/planning.py` | Planner node and AviationPlan schema |
| `shared/airport_tools.py` | Tool manifest (single source of truth) |
| `configs/aviation_agent/prompts/planner_v1.md` | Planner system prompt |

**Key Exports:**
- `AviationPlan` - Pydantic schema for planner output
- `build_planner_runnable()` - Creates planner chain
- `planner_node()` - LangGraph node function

**Prerequisites:** Read `AGENT_ARCHITECTURE.md` first.

---

## AviationPlan Schema

```python
class AviationPlan(BaseModel):
    selected_tool: str                    # Tool name from manifest
    arguments: Dict[str, Any]             # Tool arguments including filters
    answer_style: Optional[str] = None    # How to present results
    reasoning: Optional[str] = None       # Why this tool was selected
```

### Example Planner Output

```python
AviationPlan(
    selected_tool="find_airports_near_route",
    arguments={
        "from_location": "EGTF",
        "to_location": "LFMD",
        "filters": {
            "has_avgas": True,
            "point_of_entry": True
        },
        "max_distance_nm": 25
    },
    answer_style="list with distances",
    reasoning="User wants airports along route with fuel and customs"
)
```

---

## Tool Selection

The planner selects exactly one tool per request. Tool names come from `shared/airport_tools.get_shared_tool_specs()`.

### Available Tools

**Airport Tools:**

| Tool | Use Case | Key Arguments |
|------|----------|---------------|
| `search_airports` | Text search | `query`, `filters` |
| `find_airports_near_location` | Airports near a point | `location_query`, `filters`, `max_distance_nm` |
| `find_airports_near_route` | Airports along a route | `from_location`, `to_location`, `filters`, `max_leg_time_hours` |
| `get_airport_details` | Details for one airport | `icao_code` |
| `get_notification_for_airport` | PPR/notification info | `icao`, `day_of_week` |
| `calculate_flight_distance` | Distance/time between airports | `from_location`, `to_location`, `cruise_speed_kts` |

**Rules Tools:**

| Tool | Use Case | Key Arguments |
|------|----------|---------------|
| `answer_rules_question` | Specific question (one country) | `country_code`, `question`, `tags` |
| `browse_rules` | List rules in category | `country_code`, `tags`, `offset`, `limit` |
| `compare_rules_between_countries` | Compare 2+ countries | `countries`, `category`, `tags` |

### Tool Validation

```python
def _validate_plan(plan: AviationPlan, tools: Sequence[AviationTool]) -> None:
    valid_names = {tool.name for tool in tools}
    if plan.selected_tool not in valid_names:
        raise ValueError(f"Tool '{plan.selected_tool}' not in manifest: {valid_names}")
```

---

## Filter Extraction

The planner extracts user requirements into `plan.arguments.filters`.

### Supported Filters

| Filter | Type | Example User Input |
|--------|------|-------------------|
| `country` | string | "in France" → `"FR"` |
| `has_avgas` | boolean | "with AVGAS" → `true` |
| `has_jet_a` | boolean | "with Jet A" → `true` |
| `fuel_type` | string | "need fuel" → `"avgas"` |
| `has_procedures` | boolean | "IFR airports" → `true` |
| `point_of_entry` | boolean | "customs airports" → `true` |
| `has_hard_runway` | boolean | "hard surface" → `true` |
| `min_runway_length_ft` | number | "1000m runway" → `3281` |
| `max_hours_notice` | number | "no PPR" → `0` |
| `hotel` | number | "hotel nearby" → `1` |
| `restaurant` | number | "restaurant" → `1` |

### Filter Extraction Example

**User**: "Find airports near Paris with AVGAS and customs"

**Planner extracts**:
```python
{
    "selected_tool": "find_airports_near_location",
    "arguments": {
        "location_query": "Paris",
        "filters": {
            "has_avgas": True,
            "point_of_entry": True
        }
    }
}
```

---

## Planner Prompt Guidance

The planner prompt (`planner_v1.md`) includes guidance for tool selection:

### Tool Selection Guidance

```markdown
**Airport Tools - Which to Use:**
- search_airports: For text queries ("airports called...", "find EGKB")
- find_airports_near_location: For "near X" queries
- find_airports_near_route: For "between X and Y", "on the way"
- get_airport_details: For specific airport info ("tell me about EGTF")
- calculate_flight_distance: For distance/time queries

**Rules Tools - Which to Use:**
- answer_rules_question: For specific questions about ONE country
- browse_rules: For listing/browsing ("show all customs rules in France")
- compare_rules_between_countries: ONLY for comparing 2+ countries
```

### Country Extraction

```markdown
**Country Extraction:**
- "France" → countries: ["FR"]
- "UK" → countries: ["GB"]
- "LFMD" → Infer from ICAO prefix (LF = France)
- Use ISO-2 codes in arguments
```

### Follow-up Context

```markdown
**Follow-up Messages:**
When user provides missing information in a follow-up:
1. Check conversation history for context
2. Extract newly provided info (speed, aircraft type, etc.)
3. Call tool with complete parameters
```

---

## Planner Node Implementation

```python
def build_planner_runnable(
    llm: Runnable,
    tools: Sequence[AviationTool],
    system_prompt: Optional[str] = None
) -> Runnable:
    """Build planner chain with structured output."""

    # Use function calling for reliable structured output
    structured_llm = llm.with_structured_output(
        AviationPlan,
        method="function_calling"
    )

    prompt = ChatPromptTemplate.from_messages([
        ("system", system_prompt or DEFAULT_PLANNER_PROMPT),
        MessagesPlaceholder("messages"),
    ])

    return prompt | structured_llm


def planner_node(state: AgentState) -> Dict[str, Any]:
    """LangGraph node that produces AviationPlan."""
    try:
        plan: AviationPlan = planner.invoke({
            "messages": state.get("messages") or []
        })

        # Validate tool exists in manifest
        _validate_plan(plan, tools)

        reasoning = f"Selected tool: {plan.selected_tool}."
        if plan.reasoning:
            reasoning += f" {plan.reasoning}"

        return {
            "plan": plan,
            "planning_reasoning": reasoning
        }
    except Exception as e:
        return {"error": str(e)}
```

### Structured Output Method

**Why `method="function_calling"`:**
- More reliable with conversation history (critical for multi-turn)
- Works better than strict JSON schema mode
- Native LangChain integration
- Clear error messages on parsing failure

---

## Time-Constrained Search

For queries like "where can I stop within 3 hours":

### Planner Extraction

```python
{
    "selected_tool": "find_airports_near_route",
    "arguments": {
        "from_location": "EGTF",
        "to_location": "LFMD",
        "max_leg_time_hours": 3,
        "aircraft_type": "sr22"  # Or cruise_speed_kts
    }
}
```

### Tool Computes Distance

```python
# In find_airports_near_route tool
if max_leg_time_hours and cruise_speed_kts:
    max_distance_nm = max_leg_time_hours * cruise_speed_kts
    # Filter airports within this distance
```

---

## Testing

### Unit Tests

```python
# test_planning.py
def test_filter_extraction():
    """Planner extracts filters from natural language."""
    messages = [HumanMessage(content="airports near Paris with AVGAS")]
    plan = planner.invoke({"messages": messages})

    assert plan.selected_tool == "find_airports_near_location"
    assert plan.arguments.get("filters", {}).get("has_avgas") == True
```

### Behavior Tests (LLM)

```python
# test_planner_behavior.py
@pytest.mark.parametrize("query,expected_tool", [
    ("airports near London", "find_airports_near_location"),
    ("EGTF to LFMD", "find_airports_near_route"),
    ("tell me about EGKB", "get_airport_details"),
    ("how long to fly EGTF to LFMD", "calculate_flight_distance"),
])
def test_tool_selection(query, expected_tool):
    """Planner selects correct tool for query type."""
    plan = planner.invoke({"messages": [HumanMessage(content=query)]})
    assert plan.selected_tool == expected_tool
```

---

## Debugging

```bash
# See planner output
python tools/avdbg.py "Find airports near Paris" --plan

# Output:
# Plan:
#   selected_tool: find_airports_near_location
#   arguments:
#     location_query: Paris
#     filters: {}
#   reasoning: User wants airports near a location
```

```python
# In Python
from shared.aviation_agent.planning import build_planner_runnable

planner = build_planner_runnable(llm, tools)
plan = planner.invoke({"messages": [HumanMessage(content="...")]})
print(plan.selected_tool)
print(plan.arguments)
```
