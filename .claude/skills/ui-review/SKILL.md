---
name: ui-review
description: >
  Review code changes in web/client/ts/ for compliance with architecture principles.
  Use when reviewing TypeScript UI code, checking store patterns, or validating
  separation of concerns. Verifies Zustand store as single source of truth,
  reactive updates, and proper component communication patterns.
allowed-tools: Read, Glob, Grep
---

# UI Architecture Review

Review code changes in `web/client/ts/` for compliance with architecture principles.

## Architecture Rules

1. **Store is Single Source of Truth**:
   - All state lives in Zustand store (`ts/store/store.ts`)
   - No duplicated state in components

2. **State Updates via Actions**:
   - Use `store.getState().setX()` methods
   - Never direct assignment

3. **Component Communication Patterns**:
   - Store updates (primary method)
   - Custom events (cross-component actions)
   - Public API methods (limited, well-defined)
   - Never direct private method calls across components

4. **No Direct DOM Manipulation**:
   - Update store first

5. **Reactive Updates**:
   - UI/map updates via store subscriptions
   - Not manual calls after store updates

6. **Separation of Concerns**:
   - `UIManager` = UI/DOM handling only
   - `APIAdapter` = API communication only
   - `Store` = State management only
   - `VisualizationEngine` = Map rendering only
   - `LLMIntegration` = LLM orchestration only

## Review Checklist

### Store as Source of Truth
- All state updates use `store.getState().setX()` actions?
- No direct state manipulation?
- No duplicated state in components?

### Component Communication
- LLMIntegration -> UIManager uses public APIs or events only?
- No private method calls across components?
- Cross-component updates go through store or events?

### Separation of Concerns
- UIManager doesn't make direct API calls?
- APIAdapter doesn't manage state or manipulate DOM?
- Store doesn't contain business logic or UI code?

### Reactive Updates
- UI updates happen via `store.subscribe()`?
- No manual `updateUI()` calls after `store.setX()`?

## Red Flags

Flag these violations immediately:

- **Direct state assignment**: `state.airports = ...`, `state.filters.country = ...`
- **Direct DOM without store**: `element.value = ...` without `store.setSearchQuery()`
- **Private method calls**: `this.uiManager.handleSearch()` (handleSearch is private)
- **API calls outside APIAdapter**: `fetch(...)` in UIManager
- **Manual UI updates after store**: `updateUI()` right after `store.setX()`
- **Duplicated state**: Component maintains its own copy of store state
- **Tight coupling**: Direct instantiation like `new OtherComponent()`

## Output Format

**APPROVED:**
- `file:line` - Explanation of why it's correct

**VIOLATION:**
- `file:line` - Description
- **Problem:** Why it violates architecture
- **Fix:** Suggested corrected implementation
- **Pattern:** Reference to approved pattern

## Approved Patterns

**Store Update Pattern:**
```typescript
// GOOD: Update store, components react via subscription
store.getState().setAirports(airports);
// UI updates automatically via store.subscribe() in UIManager
```

**Event Pattern:**
```typescript
// GOOD: Loose coupling via events
window.dispatchEvent(new CustomEvent('trigger-search', {
  detail: { query: "EGKB LFPG" }
}));
```

**Public API Pattern:**
```typescript
// GOOD: Public method designed for external use
// In UIManager:
public syncFiltersToUI(filters: Partial<FilterConfig>): void { ... }

// In LLMIntegration:
this.uiManager.syncFiltersToUI(filters); // OK, public API
```

## Available Custom Events

- `trigger-search` - Trigger a search
- `trigger-locate` - Trigger a locate search
- `trigger-filter-refresh` - Load airports matching current store filters
- `render-route` - Render route on map
- `reset-rules-panel` - Clear rules panel state
- `show-country-rules` - Display country rules in Rules panel
- `airport-click` - Trigger airport selection
- `display-airport-details` - Display airport details in right panel

## Reference

- `designs/UI_FILTER_STATE_DESIGN.md` - Detailed examples
- `designs/CHATBOT_WEBUI_DESIGN.md` - LLM integration specifics
