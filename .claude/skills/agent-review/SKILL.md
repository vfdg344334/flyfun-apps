---
name: agent-review
description: >
  Review aviation agent code changes for architecture compliance.
  Use when reviewing changes to shared/aviation_agent/, web/server/api/aviation_agent_chat.py,
  or configs/aviation_agent/. Verifies UI payload stability, tool name consistency,
  state management patterns, and LangGraph best practices.
allowed-tools: Read, Glob, Grep
---

# Aviation Agent Architecture Review

Review code changes in `shared/aviation_agent/` and `web/server/api/aviation_agent_chat.py` for compliance with the LangGraph agent architecture.

## Agent Flow

```
Planner -> [Predict Next Queries] -> Tool -> Formatter -> END
```

The planner selects the appropriate tool based on user query. No routing layer.

## Available Tools (from `shared/airport_tools.py`)

**Airport Tools:**
- `search_airports` - Text/name/code search, country queries
- `find_airports_near_location` - Proximity search near a place
- `find_airports_near_route` - Airports along a route
- `get_airport_details` - Details for a specific ICAO code
- `get_notification_for_airport` - Notification requirements

**Rules Tools:**
- `answer_rules_question` - RAG-based semantic search (single country)
- `browse_rules` - Tag-based listing with pagination
- `compare_rules_between_countries` - Semantic comparison (2+ countries)

## Architecture Rules

1. **UI Payload Stability** - Flattened approach:
   - Stable top-level keys (`kind`, `tool`, `departure`, `icao`, etc.)
   - `tool` field for frontend context (e.g., legend mode switching)
   - Flattened common fields (`filters`, `visualization`, `airports`)
   - `suggested_queries` for follow-up suggestions
   - `show_rules` for rules tools

2. **Tool Name Consistency**:
   - Tool names must match `shared/airport_tools.get_shared_tool_specs()`
   - Planner uses literal tool names from manifest

3. **State Management**:
   - Use `AgentState` TypedDict, no direct mutations
   - Errors stored in state, not raised as exceptions
   - Use LangGraph reducers (`operator.add` for messages)

4. **UI Payload Building**:
   - Only `build_ui_payload()` creates `ui_payload`
   - Centralized in `formatting.py`
   - Tool-to-kind mapping must be correct

5. **Visualization Types** (from tool results):
   - `route_with_markers` - Route with airport markers
   - `markers` - General airport markers
   - `point_with_markers` - Location point with airports
   - `marker_with_details` - Single airport focus

6. **Filter Extraction**:
   - Filters in `plan.arguments.filters`
   - Extracted by planner, not formatter
   - Tools return `filter_profile`

7. **Error Handling**:
   - Store errors in `state["error"]`
   - Formatter handles errors gracefully
   - Errors emitted as SSE events

8. **Separation of Concerns**:
   - `planning.py` - Planner logic only
   - `execution.py` - Tool execution only
   - `formatting.py` - Formatting and UI payload
   - `graph.py` - LangGraph nodes only

9. **Configuration Management**:
   - LLM settings from `behavior_config.llms.*`
   - Feature flags from `behavior_config.*.enabled`
   - Prompts via `behavior_config.load_prompt(key)`
   - No hardcoded config values

10. **Tools Return DATA, Formatters Do SYNTHESIS**:
    - Tools NEVER call LLMs or do synthesis
    - Tools return `_tool_type` marker for formatter routing
    - Formatter selects prompt based on `_tool_type`
    - Example: `_tool_type: "comparison"` → use `comparison_synthesis_v1.md`

11. **Streaming Requirements**:
    - Use `astream_events(version="v2")` for streaming
    - SSE events: `plan`, `thinking`, `tool_call_start`, `tool_call_end`, `message`, `ui_payload`, `done`, `error`
    - Track token usage across all LLM calls

12. **Structured Output**:
    - Prefer `with_structured_output(method="function_calling")` for OpenAI
    - Validate planner output against tool manifest
    - Fallback to `PydanticOutputParser` for non-OpenAI models

## Review Checklist

### UI Payload Structure
- `ui_payload` has `kind` field?
- `ui_payload` has `tool` field for frontend context?
- Common fields flattened at top level?
- `build_ui_payload()` is the only place creating `ui_payload`?

### Tool Name Consistency
- Tool names match `shared/airport_tools.py`?
- No hardcoded tool names that don't exist?

### State Management
- Uses `AgentState` TypedDict?
- Errors stored in state, not raised?
- Messages use `operator.add` reducer?

### Configuration
- No hardcoded LLM models/temperatures?
- Prompts loaded from config?

### Formatter Strategy
- Comparison tool returns `_tool_type: "comparison"`?
- Formatter checks `_tool_type` and uses correct prompt?
- No LLM synthesis happening in tools?

### Streaming
- Uses `astream_events(version="v2")`?
- Token usage tracked across all LLM calls?

## Red Flags

- **Breaking UI payload structure**: Changing stable top-level fields
- **Missing tool field**: UI payload without `tool` field
- **Invented tool names**: Using names not in `shared/airport_tools.py`
- **Direct state mutations**: `state["key"] = value` instead of returning dict
- **UI payload outside `build_ui_payload()`**: Creating manually
- **Raised exceptions**: `raise Exception()` instead of `return {"error": "..."}`
- **Hardcoded config**: LLM models, temperatures in code
- **LLM synthesis in tools**: Tools calling LLM directly (should return data only)
- **Missing `_tool_type` marker**: Comparison tool not setting `_tool_type: "comparison"`
- **Wrong streaming API**: Using deprecated `astream()` instead of `astream_events(version="v2")`

## Output Format

**APPROVED:**
- `file:line` - Explanation of why it's correct

**VIOLATION:**
- `file:line` - Description
- **Problem:** Why it violates architecture
- **Fix:** Suggested corrected implementation
- **Impact:** What breaks

## Key Files

### Core Agent
- `shared/aviation_agent/state.py` - AgentState TypedDict
- `shared/aviation_agent/planning.py` - Planner and AviationPlan
- `shared/aviation_agent/execution.py` - Tool execution
- `shared/aviation_agent/formatting.py` - Formatter and UI payload
- `shared/aviation_agent/graph.py` - LangGraph assembly

### RAG & Comparison
- `shared/aviation_agent/rules_rag.py` - RAG system for rules retrieval
- `shared/aviation_agent/answer_comparer.py` - Embedding-based comparison
- `shared/aviation_agent/comparison_service.py` - High-level comparison API

### Adapters
- `shared/aviation_agent/adapters/streaming.py` - SSE streaming adapter
- `shared/aviation_agent/next_query_predictor.py` - Follow-up suggestions

### External
- `shared/airport_tools.py` - Tool manifest
- `configs/aviation_agent/default.json` - Config schema
- `web/server/api/aviation_agent_chat.py` - FastAPI endpoint

## Design Documents

- `designs/LLM_AGENT_DESIGN.md` - Full architecture reference
- `designs/CHATBOT_WEBUI_DESIGN.md` - WebUI integration
- `designs/UI_FILTER_STATE_DESIGN.md` - Filter and visualization mapping
