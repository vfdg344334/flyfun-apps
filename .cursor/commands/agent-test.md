# Aviation Agent Test Improvement Agent

## Overview
Analyze planner behavioral test results and apply a multi-agent improvement workflow to systematically enhance tool definitions, planner prompts, and test coverage. This agent uses **existing test infrastructure** at `tests/aviation_agent/` - no need to build scripts from scratch.

## ⚠️ CRITICAL: Use Existing Infrastructure Only

**DO NOT CREATE NEW SCRIPTS OR FILES.** All infrastructure already exists:

✅ **Test Runner**: `tests/aviation_agent/test_planner_behavior.py` (already complete)
✅ **Test Cases**: `tests/aviation_agent/fixtures/planner_test_cases.json` (edit this file)
✅ **CSV Results**: `tests/aviation_agent/results/` (read CSV files directly)

When the user asks for:
- **Agent 1 (Ground Truth)**: Read and append to existing `planner_test_cases.json`
- **Agent 2 (Analyze Failures)**: Read CSV from `results/` and propose code changes
- **Agent 3 (Validation)**: Read and compare two CSV files from `results/`

**Your job is to analyze data and propose changes, NOT write new infrastructure code.**

## Quick Start Example

**Typical workflow when user provides new test questions:**

1. **Read** existing test cases from `tests/aviation_agent/fixtures/planner_test_cases.json`
2. **Generate** new test cases and **append** to JSON file
3. **Load environment** from `web/server/.env` to get `OPENAI_API_KEY`
4. **Verify API key** is set with `echo $OPENAI_API_KEY`
5. **Run tests** using venv from `/root/Projects/flyfun`:
   ```bash
   export $(cat web/server/.env | grep -v '^#' | xargs)
   source /root/Projects/flyfun/bin/activate
   RUN_PLANNER_BEHAVIOR_TESTS=1 /root/Projects/flyfun/bin/python -m pytest tests/aviation_agent/test_planner_behavior.py -v
   ```
6. **Report** CSV file path and summary metrics
7. **If failures exist**, analyze CSV and propose code changes

## Existing Test Infrastructure

**IMPORTANT:** All test infrastructure already exists. Use these files directly:

- **Test Runner**: `tests/aviation_agent/test_planner_behavior.py` (already has CSV export)
- **Test Cases**: `tests/aviation_agent/fixtures/planner_test_cases.json` (21 test cases)
- **Results Directory**: `tests/aviation_agent/results/` (CSV files saved here)
- **Configuration**: `tests/aviation_agent/conftest.py` (pytest fixtures)

**DO NOT create new test scripts.** Use the existing `test_planner_behavior.py` which already:
- Loads test cases from JSON
- Runs planner with live LLM
- Saves results to CSV with timestamps
- Reports pass/fail for tool selection and argument extraction

## Agent Workflow

This agent orchestrates a continuous improvement loop using existing infrastructure:

```
New Test Questions → Ground Truth Generator → Update planner_test_cases.json
                              ↓
                    Run Existing Pytest (test_planner_behavior.py)
                              ↓
                    Analyze CSV Results (in results/ directory)
                              ↓
                  Tool Definition Improver → Update Code
                              ↓
                    Validation Agent → Compare CSV Results
                              ↓
                    Iterate if Needed
```

## Agent 1: Ground Truth Generator

### Purpose
Learn patterns from existing test cases to generate expected tool selection and arguments for new test questions.

### Input Requirements
- Existing test cases from `tests/aviation_agent/fixtures/planner_test_cases.json`
- New test questions (user-provided)
- Tool catalog from `shared/aviation_agent/tools.py`

### Output
New test cases appended to `tests/aviation_agent/fixtures/planner_test_cases.json` with correctly populated `expected_tool` and `expected_arguments` fields.

### Implementation Instructions
**Use existing test infrastructure - DO NOT write new scripts:**
1. Read existing test cases from `tests/aviation_agent/fixtures/planner_test_cases.json`
2. Read tool catalog from `shared/aviation_agent/tools.py`
3. Learn patterns from existing test cases
4. Generate new test cases following the same JSON format
5. Append new test cases to the existing JSON file

### Pattern Learning Rules

1. **Tool Selection Patterns:**
   - Routes (from X to Y) → `find_airports_near_route`
   - Near location (near X, around X) → `find_airports_near_location`
   - Airport details (details for ICAO) → `get_airport_details`
   - Country search (airports in X) → `search_airports`
   - Customs by country → `get_border_crossing_airports`
   - Rules questions → `list_rules_for_country` or `compare_rules_between_countries`

2. **Argument Extraction Patterns:**
   - Route queries: Extract `from_location` and `to_location`
   - Location queries: Extract `location_query` (include country if mentioned)
   - ICAO codes: Pass exactly as provided (4 uppercase letters)
   - Location names: Include country context when provided
   - Filters: Extract `has_avgas`, `point_of_entry`, `has_hard_runway`, etc.

3. **Critical Rules:**
   - Preserve country context: "Vik, Iceland" not just "Vik"
   - Pass locations exactly as user provides them
   - Only include filters explicitly mentioned by user
   - ICAO codes are 4 uppercase letters

### Example Task

When given new questions like:
```
1. Find fuel stops between KJFK and EGLL
2. What are customs rules for Spain?
3. Airports near Barcelona with hard runways
```

Generate test cases:
```json
[
  {
    "question": "Find fuel stops between KJFK and EGLL",
    "expected_tool": "find_airports_near_route",
    "expected_arguments": {
      "from_location": "KJFK",
      "to_location": "EGLL"
    },
    "description": "Route query with ICAO codes - fuel context implies route planning"
  },
  {
    "question": "What are customs rules for Spain?",
    "expected_tool": "list_rules_for_country",
    "expected_arguments": {
      "country_code": "ES"
    },
    "description": "Country-specific customs rules query"
  },
  {
    "question": "Airports near Barcelona with hard runways",
    "expected_tool": "find_airports_near_location",
    "expected_arguments": {
      "location_query": "Barcelona",
      "filters": {
        "has_hard_runway": true
      }
    },
    "description": "Location search with runway surface filter"
  }
]
```

## Agent 2: Tool Definition Improver

### Purpose
Analyze pytest failures from CSV results and propose improvements to tool definitions, planner prompts, or formatting logic.

### Input Requirements
- Latest CSV results from `tests/aviation_agent/results/planner_test_results_*.csv`
- Current code files:
  - `shared/aviation_agent/tools.py`
  - `shared/aviation_agent/planning.py`
  - `shared/aviation_agent/formatting.py`

### Output
- Failure pattern analysis
- Root cause identification
- Specific code changes with file:line references
- Expected improvement metrics

### Implementation Instructions
**Use existing CSV results - DO NOT create new analysis scripts:**
1. Read the latest CSV file from `tests/aviation_agent/results/` directory
2. Load and analyze current code from `shared/aviation_agent/` files
3. Identify failure patterns from CSV columns: status, tool_match, args_match
4. Propose specific code changes to fix systematic issues

### Analysis Checklist

1. **Identify Failure Patterns:**
   - [ ] Are failures clustered around specific tools?
   - [ ] Are arguments consistently missing or wrong?
   - [ ] Are there tool selection errors (wrong tool chosen)?
   - [ ] Are filters not being recognized?

2. **Root Cause Categories:**
   - **Tool description ambiguity** - Multiple tools seem applicable
   - **Missing examples in planner prompt** - LLM needs concrete patterns
   - **Unclear parameter descriptions** - Tool arguments not well-defined
   - **Conflicting tool purposes** - Tools overlap in functionality

3. **Propose Fixes:**
   - Update tool descriptions to be more distinctive
   - Add explicit examples to planner prompt
   - Clarify parameter requirements
   - Add validation rules

### Failure Categories

**Tool Mismatch** (Expected tool ≠ Actual tool):
- Fix: Improve tool descriptions, add examples showing when to use each tool
- Example: If LLM confuses `search_airports` with `find_airports_near_location`, make descriptions more distinctive

**Missing Arguments** (Expected args not extracted):
- Fix: Add explicit extraction instructions to planner prompt
- Example: Add "ALWAYS set 'from_location' and 'to_location' for find_airports_near_route"

**Wrong Argument Values** (Extracted incorrectly):
- Fix: Add examples showing correct extraction
- Example: Show that "Vik, Iceland" should be passed with country context, not just "Vik"

**Filter Issues** (Filters not recognized or wrong):
- Fix: List available filters explicitly, add examples
- Example: Add "Available filters: has_avgas, has_jet_a, has_hard_runway, point_of_entry..."

### Example Analysis

**CSV Shows:**
- 10 failures with empty arguments `{}`
- Tool selection correct but argument extraction failed

**Root Cause:**
- Planner prompt lacks explicit argument extraction instructions

**Fix:**
```python
# In planning.py, add to system prompt:
"**CRITICAL - Argument Extraction:**\n"
"You MUST extract ALL required arguments for the selected tool:\n"
"- find_airports_near_route: ALWAYS set 'from_location' and 'to_location'\n"
"- find_airports_near_location: ALWAYS set 'location_query'\n"
"Example: 'airports between Paris and LOWI' → {{'from_location': 'Paris', 'to_location': 'LOWI'}}\n"
```

**Expected Improvement:**
- Pass rate should increase from 50% to 90%+

## Agent 3: Validation Agent

### Purpose
Re-run tests after improvements and validate that changes actually improved results without introducing regressions.

### Input Requirements
- Previous test results CSV (before changes)
- Current test results CSV (after changes)

### Output
- Comparison report (before vs after)
- Regression detection
- Recommendation (accept/iterate/reject)

### Validation Checklist

1. **Compare Metrics:**
   - [ ] Pass rate improvement (PASS / TOTAL)
   - [ ] Tool match rate improvement (tool_match=YES / TOTAL)
   - [ ] Args match rate improvement (args_match=YES / TOTAL)
   - [ ] New failures introduced (regressions)

2. **Quality Assessment:**
   - [ ] Did changes address root causes?
   - [ ] Are there new systematic issues?
   - [ ] Should we iterate again?

3. **Recommendation Criteria:**
   - **Accept**: improvement > 0, no critical regressions
   - **Iterate**: some improvement but issues remain
   - **Reject**: regressions or no improvement

### Example Validation Report

**Before Results:**
- Total tests: 21
- Passed: 11 (52%)
- Tool match: 18 (86%)
- Args match: 11 (52%)

**After Results:**
- Total tests: 21
- Passed: 21 (100%)
- Tool match: 21 (100%)
- Args match: 21 (100%)

**Analysis:**
- ✅ Improvement: +48% pass rate
- ✅ No regressions: All previously passing tests still pass
- ✅ Improved tests: 10 tests that were failing now pass

**Recommendation:** Accept changes

## Usage Guide

### Step 1: Generate Ground Truth for New Questions

**DO NOT write new scripts.** Use this agent to directly update the JSON file:

**Example invocation:**
```
/agent-test

I have these new test questions:
1. Find airports with AVGAS between Munich and Vienna
2. Route from LSZH to EDDM with customs
3. Airports near Salzburg, Austria

Please use Agent 1 (Ground Truth Generator) to:
- Read existing patterns from tests/aviation_agent/fixtures/planner_test_cases.json
- Generate test cases for my questions
- Append them to the JSON file
```

The agent will directly edit `tests/aviation_agent/fixtures/planner_test_cases.json`.

### Step 2: Run Tests with Existing Infrastructure

**CRITICAL: The agent should run the tests after adding new test cases.**

**Use the virtual environment and run pytest:**

```bash
# Load environment variables from web/server/.env
if [ -f "web/server/.env" ]; then
  export $(cat web/server/.env | grep -v '^#' | xargs)
  echo "✓ Loaded environment from web/server/.env"
fi

# Check API key first
if [ -z "$OPENAI_API_KEY" ]; then
  echo "⚠️  ERROR: OPENAI_API_KEY not set. Check web/server/.env file."
  exit 1
fi

# Activate venv
source /root/Projects/flyfun/bin/activate

# Run tests
RUN_PLANNER_BEHAVIOR_TESTS=1 /root/Projects/flyfun/bin/python -m pytest tests/aviation_agent/test_planner_behavior.py -v

# Results saved automatically
```

**The agent must:**
1. Load environment from `web/server/.env`
2. Check if `OPENAI_API_KEY` environment variable is set
3. Run the pytest command above
4. Wait for tests to complete
5. Report the CSV file path: `tests/aviation_agent/results/planner_test_results_YYYYMMDD_HHMMSS.csv`
6. Print summary metrics (total tests, passed, failed, pass rate)

### Step 3: Analyze Failures and Improve

**Use existing CSV files - DO NOT create analysis scripts:**

**Example invocation:**
```
/agent-test

I have test failures in tests/aviation_agent/results/planner_test_results_20251130_170000.csv

Please use Agent 2 (Tool Definition Improver) to:
- Read the CSV file
- Identify failure patterns
- Propose code changes to shared/aviation_agent/ files
```

### Step 4: Validate Improvements

**Use existing CSV files for comparison:**

**Example invocation:**
```
/agent-test

Compare these CSV results:
- Before: tests/aviation_agent/results/planner_test_results_20251130_170000.csv
- After: tests/aviation_agent/results/planner_test_results_20251130_171500.csv

Please use Agent 3 (Validation Agent) to validate improvements.
```

## Running Tests

**CRITICAL: Use the virtual environment from /root/Projects/flyfun**

**Environment Setup:**
Before running tests, ensure OpenAI API key is loaded:
- **Location**: API keys are stored in `web/server/.env`
- **Load environment**: `source web/server/.env` or `export $(cat web/server/.env | xargs)`
- **Check if set**: Run `echo $OPENAI_API_KEY` to verify
- **If not set**: Load the .env file first

**Always activate the venv, load environment, and run tests with these exact commands:**

```bash
# Load environment variables from .env file
if [ -f "web/server/.env" ]; then
  export $(cat web/server/.env | grep -v '^#' | xargs)
  echo "✓ Loaded environment from web/server/.env"
else
  echo "⚠️  WARNING: web/server/.env not found"
fi

# Verify API key is set
if [ -z "$OPENAI_API_KEY" ]; then
  echo "⚠️  ERROR: OPENAI_API_KEY is not set"
  echo "Please check web/server/.env file"
  exit 1
fi

# Activate virtual environment
source /root/Projects/flyfun/bin/activate

# Run tests from project root
RUN_PLANNER_BEHAVIOR_TESTS=1 /root/Projects/flyfun/bin/python -m pytest tests/aviation_agent/test_planner_behavior.py -v

# Deactivate when done
deactivate
```

**After running tests:**
- Results are automatically saved to: `tests/aviation_agent/results/planner_test_results_YYYYMMDD_HHMMSS.csv`
- The CSV file contains columns: test_case, question, description, status, expected_tool, actual_tool, tool_match, expected_args, actual_args, args_match
- **Always print the CSV file path** so the user knows where to find it
- **Report summary metrics**: Total tests, Passed, Failed, Pass rate percentage

**Example output after running tests:**
```
✅ Tests completed successfully
📊 Results saved to: tests/aviation_agent/results/planner_test_results_20251201_150530.csv

Summary:
- Total tests: 21
- Passed: 21 (100%)
- Failed: 0 (0%)
- Tool match: 21/21 (100%)
- Args match: 21/21 (100%)
```

## Test Case Structure

Test cases in `tests/aviation_agent/fixtures/planner_test_cases.json` follow this format:

```json
{
  "question": "User question in natural language",
  "expected_tool": "tool_name_from_manifest",
  "expected_arguments": {
    "arg1": "value1",
    "filters": {
      "filter_key": true
    }
  },
  "description": "Why this tool/args combination is correct"
}
```

## Key Files (All Existing - Use Directly)

- **Test Cases**: `tests/aviation_agent/fixtures/planner_test_cases.json` (21 test cases)
- **Test Runner**: `tests/aviation_agent/test_planner_behavior.py` (runs tests, saves CSV)
- **Test Results**: `tests/aviation_agent/results/planner_test_results_*.csv` (auto-generated)
- **Planner Prompt**: `shared/aviation_agent/planning.py` (modify to fix failures)
- **Tool Definitions**: `shared/aviation_agent/tools.py` (modify to fix tool issues)
- **Formatter**: `shared/aviation_agent/formatting.py` (modify to fix output issues)

**DO NOT create new files or scripts - all infrastructure exists.**

## Output Format

### For Ground Truth Generation

```
Generated X new test cases:

1. Question: "..."
   Expected Tool: tool_name
   Arguments: {...}
   Reasoning: Why this is correct

2. Question: "..."
   ...

✅ Appended to tests/aviation_agent/fixtures/planner_test_cases.json
✅ Total test cases now: YY
```

### For Failure Analysis

```
Analyzed XX failures from tests/aviation_agent/results/planner_test_results_YYYYMMDD_HHMMSS.csv:

**Failure Pattern 1:** Empty arguments (10 tests)
- Root Cause: Planner prompt lacks explicit extraction instructions
- Affected Tests: test_case_1, test_case_7, test_case_14, ...
- Fix: Add "CRITICAL - Argument Extraction" section to shared/aviation_agent/planning.py
- Code Change:
  ```python
  # In shared/aviation_agent/planning.py, line 62, add:
  "**CRITICAL - Argument Extraction:**\n"
  "You MUST extract ALL required arguments..."
  ```
- Expected Improvement: +40% pass rate

**Failure Pattern 2:** Wrong tool selection (2 tests)
...

✅ Total fixes proposed: 3
✅ Expected pass rate improvement: 52% → 90%
```

### For Validation

```
Validation Report:

**Before:**
- Pass rate: 52% (11/21)
- Tool match: 86% (18/21)
- Args match: 52% (11/21)

**After:**
- Pass rate: 100% (21/21)
- Tool match: 100% (21/21)
- Args match: 100% (21/21)

**Improvements:** 10 tests fixed
- test_case_1: Arguments now extracted correctly
- test_case_7: Filter recognized properly
...

**Regressions:** None

**Recommendation:** ✅ ACCEPT changes
- Significant improvement (+48% pass rate)
- No regressions detected
- All systematic issues resolved
```

## Metrics to Track

### Test Coverage
- Tool coverage: % of tools with test cases
- Query type coverage: ICAO-only, location-only, mixed, filtered
- Edge cases: Ambiguous names, multi-word locations, country context

### Test Quality
- Pass rate: `PASS / TOTAL`
- Tool match rate: `tool_match=YES / TOTAL`
- Args match rate: `args_match=YES / TOTAL`

### Improvement Velocity
- Tests fixed per iteration
- Time to 100% pass rate
- Regression rate per change

## Red Flags to Report

Flag these issues immediately:

- 🔴 **Test case without description**: All test cases must explain why the expected tool/args are correct
- 🔴 **Tool name not in manifest**: Expected tool doesn't exist in `shared/aviation_agent/tools.py`
- 🔴 **Missing required arguments**: Expected arguments missing required fields for the tool
- 🔴 **Invented filters**: Filter keys that don't exist in the system
- 🔴 **Regressions**: Previously passing tests now fail after changes
- 🔴 **Inconsistent patterns**: Similar questions get different tool selections
- 🔴 **Creating new scripts**: Agent tries to write new test scripts instead of using existing infrastructure

## Critical Rules

1. **NEVER create new test scripts** - Use `tests/aviation_agent/test_planner_behavior.py`
2. **NEVER create analysis scripts** - Read CSV files directly from `tests/aviation_agent/results/`
3. **NEVER create validation scripts** - Compare CSV files directly
4. **ALWAYS edit existing files** - Append to `planner_test_cases.json`, modify files in `shared/aviation_agent/`
5. **ALWAYS use relative paths** - `tests/aviation_agent/`, `shared/aviation_agent/`, not absolute paths
6. **ALWAYS use venv from /root/Projects/flyfun** - Activate with `source /root/Projects/flyfun/bin/activate`
7. **ALWAYS load environment from web/server/.env** - Use `export $(cat web/server/.env | grep -v '^#' | xargs)`
8. **ALWAYS check OPENAI_API_KEY** - Verify environment variable is set before running tests
9. **ALWAYS run tests and generate CSV** - After adding test cases, run pytest and report CSV file path
10. **ALWAYS report test summary** - Print total tests, passed, failed, and pass rate percentage

## Best Practices

### For Ground Truth Generation
- Always explain reasoning in description field
- Include country context for ambiguous locations
- Only include filters user explicitly mentions
- Pass locations exactly as user provides them

### For Failure Analysis
- Identify patterns, not individual failures
- Fix root causes, not symptoms
- Propose specific code changes with file:line references
- Estimate expected improvement

### For Validation
- Always check for regressions first
- Compare before/after metrics
- Provide clear accept/iterate/reject recommendation
- Track improvement velocity

### Incremental Improvement
- Add 5-10 test cases per iteration (not 50+)
- Fix systematic issues before adding more tests
- Validate each improvement before moving on
- Keep historical CSV results for tracking

## Notes

- This agent focuses on behavioral testing (LLM tool selection and argument extraction)
- Results vary between LLM runs due to non-deterministic nature
- Use `temperature=0` for more consistent results
- Consider acceptable variations (e.g., LLM adding country context is OK)
- CSV results are gitignored (not committed to repo)
- Test improvements should be committed to repo
