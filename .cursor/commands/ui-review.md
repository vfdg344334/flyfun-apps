# UI Architecture Review

## Overview
Review code changes in `web/client/ts/` to ensure compliance with our architecture principles. Verify that the store remains the single source of truth and proper separation of concerns is maintained.

## Architecture Rules

1. **Store is single source of truth** - All state lives in store, no duplicated state in components
2. **State updates ONLY via store actions** - Use `store.getState().setX()` methods, never direct assignment
3. **Component communication patterns:**
   - ✅ Store updates (primary method)
   - ✅ Custom events (for cross-component actions)
   - ✅ Public API methods (limited, well-defined)
   - ❌ Direct private method calls across components
4. **No direct DOM manipulation** without updating store first
5. **Reactive updates** - UI/map updates via store subscriptions, not manual calls after store updates
6. **Separation of concerns:**
   - `UIManager` = UI/DOM handling only
   - `APIAdapter` = API communication only
   - `Store` = State management only
   - `VisualizationEngine` = Map rendering only
   - `LLMIntegration` = LLM orchestration only

## Review Checklist

For each code change, verify:

### 1. Store as Source of Truth
- [ ] All state updates use `store.getState().setX()` actions?
- [ ] No direct state manipulation (`state.airports = ...`, `state.filters. = ...`)?
- [ ] No duplicated state in components (component-level state that mirrors store)?

### 2. Component Communication
- [ ] LLMIntegration → UIManager uses public APIs or events only?
- [ ] No private method calls across components (`handleSearch()`, `updateMarkers()`, etc.)?
- [ ] Cross-component updates go through store or events?
- [ ] No direct instantiation creating tight coupling?

### 3. Separation of Concerns
- [ ] UIManager doesn't make direct API calls (uses APIAdapter)?
- [ ] APIAdapter doesn't manage state or manipulate DOM?
- [ ] Store doesn't contain business logic or UI code?
- [ ] VisualizationEngine doesn't manage state or make API calls?

### 4. Reactive Updates
- [ ] UI updates happen via `store.subscribe()`?
- [ ] No manual `updateUI()` or similar calls after `store.setX()`?
- [ ] Updates are automatic via subscriptions, not manually triggered?

### 5. Event Handling
- [ ] User events update store first, then trigger actions?
- [ ] Programmatic updates go through store?
- [ ] Events don't bypass store for state changes?

## Red Flags to Flag

Flag these violations immediately:

- 🔴 Direct state assignment: `state.airports = ...`, `state.filters.country = ...`
- 🔴 Direct DOM manipulation without store: `element.value = ...` without `store.setSearchQuery()`
- 🔴 Private method calls: `this.uiManager.handleSearch()` (handleSearch is private)
- 🔴 API calls outside APIAdapter: `fetch(...)` in UIManager or other components
- 🔴 Manual UI updates after store changes: `updateUI()` called right after `store.setX()`
- 🔴 Duplicated state: Component maintains its own copy of store state
- 🔴 Tight coupling: Direct instantiation like `new OtherComponent()` in constructors

## Review Process

1. **Analyze changed files** in `web/client/ts/` directory
2. **Check each rule** against the checklist above
3. **Identify violations** with specific file paths and line numbers
4. **Suggest fixes** with code examples showing the corrected approach
5. **Provide approved patterns** where code follows architecture correctly

## Output Format

For each finding:

**✅ APPROVED:**
- `file:line` - Brief explanation of why it's correct
- Example: `store/store.ts:154` - Uses `store.getState().setAirports()` correctly

**❌ VIOLATION:**
- `file:line` - Description of violation
- **Problem:** Why it violates architecture
- **Fix:** Suggested corrected implementation
- **Pattern:** Reference to approved pattern (store update, event, public API)

Example violation:
```
❌ VIOLATION:
web/client/ts/adapters/llm-integration.ts:45
- Issue: Direct call to `this.uiManager.handleSearch(query)`
- Problem: handleSearch() is private, breaks separation of concerns
- Fix: Use `store.getState().setSearchQuery(query)` + dispatch `trigger-search` event
- Pattern: Store update + event pattern (see approved patterns)
```

## Approved Patterns Reference

**Store Update Pattern:**
```typescript
// ✅ GOOD: Update store, components react via subscription
store.getState().setAirports(airports);
// UI updates automatically via store.subscribe() in UIManager
```

**Event Pattern:**
```typescript
// ✅ GOOD: Loose coupling via events
window.dispatchEvent(new CustomEvent('trigger-search', { 
  detail: { query: "EGKB LFPG" } 
}));
```

**Public API Pattern:**
```typescript
// ✅ GOOD: Public method designed for external use
// In UIManager:
public syncFiltersToUI(filters: Partial<FilterConfig>): void { ... }

// In LLMIntegration:
this.uiManager.syncFiltersToUI(filters); // ✅ OK, public API
```

## Notes

- Focus on architecture compliance, not code style or formatting
- Flag even minor violations to prevent pattern drift
- Reference `designs/CODE_REVIEW_GUIDELINES.md` for detailed examples
- Be constructive - suggest fixes, don't just point out problems

