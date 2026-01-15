# Agent 2: Failure Analysis

## Purpose
Analyze pytest failures from CSV results and propose improvements to tool definitions, planner prompts, or formatting logic.

## Input Requirements
- Latest CSV from `tests/aviation_agent/results/planner_test_results_*.csv`
- Current code files:
  - `shared/aviation_agent/tools.py`
  - `shared/aviation_agent/planning.py`
  - `shared/aviation_agent/formatting.py`
  - `configs/aviation_agent/prompts/planner_v1.md`

## Process

1. **Read** the latest CSV file from `tests/aviation_agent/results/`
2. **Load** current code from `shared/aviation_agent/` files
3. **Identify** failure patterns from CSV columns: status, tool_match, args_match
4. **Propose** specific code changes to fix systematic issues

## Analysis Checklist

1. **Identify Failure Patterns:**
   - Are failures clustered around specific tools?
   - Are arguments consistently missing or wrong?
   - Are there tool selection errors (wrong tool chosen)?
   - Are filters not being recognized?

2. **Root Cause Categories:**
   - **Tool description ambiguity** - Multiple tools seem applicable
   - **Missing examples in planner prompt** - LLM needs concrete patterns
   - **Unclear parameter descriptions** - Tool arguments not well-defined
   - **Conflicting tool purposes** - Tools overlap in functionality

## Failure Categories

### Tool Mismatch (Expected tool ≠ Actual tool)
**Fix**: Improve tool descriptions, add examples showing when to use each tool
**Example**: If LLM confuses `search_airports` with `find_airports_near_location`, make descriptions more distinctive

### Missing Arguments (Expected args not extracted)
**Fix**: Add explicit extraction instructions to planner prompt
**Example**: Add "ALWAYS set 'from_location' and 'to_location' for find_airports_near_route"

### Wrong Argument Values (Extracted incorrectly)
**Fix**: Add examples showing correct extraction
**Example**: Show that "Vik, Iceland" should be passed with country context

### Filter Issues (Filters not recognized or wrong)
**Fix**: List available filters explicitly, add examples
**Example**: Add "Available filters: fuel_type, has_hard_runway, point_of_entry..."

## Example Analysis

**CSV Shows:**
- 10 failures with empty arguments `{}`
- Tool selection correct but argument extraction failed

**Root Cause:**
- Planner prompt lacks explicit argument extraction instructions

**Fix:**
```python
# In planning.py or planner_v1.md, add:
"**CRITICAL - Argument Extraction:**\n"
"You MUST extract ALL required arguments for the selected tool:\n"
"- find_airports_near_route: ALWAYS set 'from_location' and 'to_location'\n"
"- find_airports_near_location: ALWAYS set 'location_query'\n"
"Example: 'airports between Paris and LOWI' → {{'from_location': 'Paris', 'to_location': 'LOWI'}}\n"
```

**Expected Improvement:**
- Pass rate should increase from 50% to 90%+

## Output Format

```
Analyzed XX failures from tests/aviation_agent/results/planner_test_results_*.csv:

**Failure Pattern 1:** Empty arguments (10 tests)
- Root Cause: Planner prompt lacks explicit extraction instructions
- Affected Tests: test_case_1, test_case_7, test_case_14, ...
- Fix: Add "CRITICAL - Argument Extraction" section to planning.py
- Code Change:
  ```python
  # In shared/aviation_agent/planning.py, line 62, add:
  ...
  ```
- Expected Improvement: +40% pass rate

**Failure Pattern 2:** Wrong tool selection (2 tests)
...

Total fixes proposed: 3
Expected pass rate improvement: 52% → 90%
```
