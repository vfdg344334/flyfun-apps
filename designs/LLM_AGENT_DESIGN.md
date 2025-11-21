# Aviation Agent – Design & Implementation Guide (A3 UI Payload Version)

This document describes the full architecture, components, testing strategy, and UI-integration
design for an aviation-focused LangChain/LangGraph agent that uses your custom **aviation MCP database**
(routes, airports, rules) and exposes **structured outputs** suitable for a modern chat UI
(including side panels such as maps, airport cards, or rules checklists).

This version implements **UI payload Plan A3**:

- The UI receives a **stable, curated JSON payload (`ui_payload`)**
- It contains:
  - `kind`: `"route"`, `"airport"`, or `"rules"`
  - A small set of stable **top-level fields** (e.g. `departure`, `icao`, `region`)
  - A **full MCP tool output** stored under the key:  
    ```
    "mcp_raw": { ... }
    ```

- Internally, the agent’s planner (`AviationPlan`) is **decoupled** from the UI.
- Only the `_build_ui_payload(plan, tool_result)` function must be updated if planner output evolves.

This design strongly isolates UI from internal LLM schema changes while still enabling rich UI behavior.

---

## 1. High-Level Architecture

### Core design:

The agent operates in **three steps via LangGraph**:

1. **Planner Node**
   - LLM with structured output (`AviationPlan`).
   - Selects one aviation tool.
   - Extracts the best possible arguments.
   - Specifies answer style.

2. **Tool Runner Node**
   - Executes the chosen MCP-backed LangChain tool.
   - Returns raw JSON (`tool_result`).

3. **Formatter Node**
   - Produces:
     - The final answer text.
     - A **UI payload** (`ui_payload`) matching A3:
       ```
       {
         "kind": "...",
         ... stable high-level fields ...,
         "mcp_raw": { ... full MCP response ... }
       }
       ```

### Agent state flow

```
┌────────┐     ┌─────────────┐     ┌───────────────┐
│ User   │ --> │ Planner Node │ --> │ Tool Runner   │ --> Formatter Node --> UI
└────────┘     └─────────────┘     └───────────────┘
```

The UI receives:

- `answer` (markdown)
- `ui_payload` (stable JSON)
- `planner_meta` (full plan for debugging)
- `tool_result` is not needed but can also be exposed.

---

## 2. Project Structure

```
aviation_agent/
  config.py
  state.py
  mcp_client.py
  tools.py
  planning.py
  execution.py
  formatting.py
  graph.py
  app/
    api.py
    ui_chat.py
  eval/
    fixtures.py
    test_planner.py
    test_execution.py
    test_formatter.py
    test_graph_e2e.py
```

---

## 3. `state.py` — Agent State With A3 UI Payload

```python
class AgentState(TypedDict):
    messages: Annotated[List[BaseMessage], operator.add]
    plan: Optional[AviationPlan]
    tool_result: Optional[Any]
    final_answer: Optional[str]

    # A3: stable UI payload
    ui_payload: Optional[dict]
```

---

## 4. `_build_ui_payload()` — The A3 Specification

A3’s rule:

> **Stable top-level keys** + **raw MCP result under `mcp_raw`**  
> UI must not depend on full planner or full tool_result.

```python
def _build_ui_payload(plan: AviationPlan, tool_result: dict | None) -> dict | None:
    if tool_result is None:
        return None

    if plan.selected_tool == "get_route_options":
        return {
            "kind": "route",
            "departure": plan.arguments.get("departure"),
            "destination": plan.arguments.get("destination"),
            "ifr": plan.arguments.get("ifr"),
            "mcp_raw": tool_result,    # the authoritative data
        }

    if plan.selected_tool == "get_airport_info":
        return {
            "kind": "airport",
            "icao": plan.arguments.get("icao"),
            "mcp_raw": tool_result,
        }

    if plan.selected_tool == "get_flying_rules":
        return {
            "kind": "rules",
            "region": plan.arguments.get("region"),
            "topic": plan.arguments.get("topic"),
            "mcp_raw": tool_result,
        }

    return None
```

### Why this design?

- **Highly stable**: UI structure rarely changes.
- **Fully future-proof**: Planner can evolve without breaking UI.
- **Powerful**: UI still gets everything via `mcp_raw`.

---

## 5. Formatter Node — Now Returns `final_answer` + `ui_payload`

Final code:

```python
resp = formatter_llm.invoke(llm_input)
ui_payload = _build_ui_payload(plan, tool_result)

return {
    "final_answer": resp.content,
    "ui_payload": ui_payload,
}
```

---

## 6. FastAPI Endpoint — Clean Stable Output

```python
class ChatResponse(BaseModel):
    answer: str
    planner_meta: dict | None = None
    ui_payload: dict | None = None

@app.post("/chat")
def chat(request: ChatRequest):
    ...
    state = run_aviation_agent(messages, mcp_client)
    plan_dict = state["plan"].model_dump() if state["plan"] else None

    return ChatResponse(
        answer=state["final_answer"],
        planner_meta=plan_dict,
        ui_payload=state.get("ui_payload"),
    )
```

### UI only needs `ui_payload`:

- `"kind": "route"` → show a route map  
- `"kind": "airport"` → show airport info card  
- `"kind": "rules"` → show rules panel  
- `"mcp_raw"` provides all underlying details for drawing polylines, etc.

---

## 7. Tests Updated for A3 Payload

Example:

```python
def test_end_to_end_route_query_builds_route_ui_payload():
    state = run_aviation_agent([HumanMessage(content="IFR EGTF to LSGS")], mcp)

    ui = state["ui_payload"]
    assert ui["kind"] == "route"
    assert ui["departure"] == "EGTF"
    assert "mcp_raw" in ui
    assert "suggested_route" in ui["mcp_raw"]
```

---

## 8. Summary of A3 Benefits

### ✔ Stable for the UI  
Only `kind`, `departure`, `icao`, etc. matter.

### ✔ Internal evolution is painless  
Planner and tool schemas can change freely.

### ✔ Full richness preserved  
`mcp_raw` always contains everything.

### ✔ Clean, simple UI dispatch  
```ts
switch(ui_payload.kind) {
  case "route": renderRoute(ui_payload.mcp_raw); break;
  case "airport": renderAirport(ui_payload.mcp_raw); break;
  case "rules": renderRules(ui_payload.mcp_raw); break;
}
```

---

## Final Notes

This README is now ready for:

- Cursor
- Claude Code
- ChatGPT code interpreter
- Direct handoff to developers

Everything needed to implement the agent end‑to‑end is included.

