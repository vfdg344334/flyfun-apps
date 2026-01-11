---
name: agent-test
description: >
  Analyze aviation agent planner behavioral test results and apply improvement workflow.
  Use when: running planner tests, adding test cases to planner_test_cases.json,
  analyzing test failures, improving planner prompts, validating planner improvements,
  or working with tests/aviation_agent/ test infrastructure.
allowed-tools: Read, Edit, Write, Bash, Glob, Grep
---

# Aviation Agent Test Improvement

Analyze planner behavioral test results and systematically enhance tool definitions, planner prompts, and test coverage.

## Critical: Use Existing Infrastructure Only

**DO NOT CREATE NEW SCRIPTS.** All infrastructure exists:

- **Test Runner**: `tests/aviation_agent/test_planner_behavior.py`
- **Test Cases**: `tests/aviation_agent/fixtures/planner_test_cases.json`
- **CSV Results**: `tests/aviation_agent/results/`

## Quick Start

1. **Read** existing test cases from `tests/aviation_agent/fixtures/planner_test_cases.json`
2. **Generate** new test cases and **append** to JSON file
3. **Run tests**:
   ```bash
   source ./venv/bin/activate
   export $(cat web/server/.env | grep -v '^#' | xargs)
   RUN_PLANNER_BEHAVIOR_TESTS=1 python -m pytest tests/aviation_agent/test_planner_behavior.py -v
   ```
4. **Report** CSV file path and summary metrics
5. **If failures exist**, analyze CSV and propose code changes

## Three-Agent Workflow

For detailed instructions on each agent, see:
- [Ground Truth Generator](ground-truth.md) - Generate expected tool selection for new questions
- [Failure Analysis](failure-analysis.md) - Analyze failures and propose fixes
- [Validation](validation.md) - Compare before/after results

## Tool Selection Patterns

| Query Type | Tool | Key Arguments |
|------------|------|---------------|
| Routes (from X to Y) | `find_airports_near_route` | `from_location`, `to_location`, `filters` |
| Near location | `find_airports_near_location` | `location_query`, `filters` |
| Airport details | `get_airport_details` | `icao_code` |
| Country search | `search_airports` | `query`, `filters` |
| Notification requirements | `get_notification_for_airport` | `icao`, `day_of_week` |
| Rules question (ONE country) | `answer_rules_question` | `country_code`, `question`, `tags` |
| Rules browsing (list all) | `browse_rules` | `country_code`, `tags`, `offset`, `limit` |
| Rules comparison (2+ countries) | `compare_rules_between_countries` | `countries`, `tags`, `category` |

## Available Filters

| Filter | Type | Description |
|--------|------|-------------|
| `fuel_type` | `'avgas'` \| `'jet_a'` | Preferred over legacy `has_avgas`/`has_jet_a` |
| `has_avgas` | boolean | Legacy - still works |
| `has_jet_a` | boolean | Legacy - still works |
| `has_hard_runway` | boolean | Paved/hard surface runways |
| `has_procedures` | boolean | IFR procedures available |
| `point_of_entry` | boolean | Customs/border crossing |
| `country` | string | ISO-2 country code |
| `min_runway_length_ft` | number | Minimum runway length |
| `max_runway_length_ft` | number | Maximum runway length |
| `max_landing_fee` | number | Maximum landing fee |
| `max_hours_notice` | number | Notification requirements |
| `hotel` | boolean | On-site hotel |
| `restaurant` | boolean | On-site restaurant |

## Test Case Format

```json
{
  "question": "User question in natural language",
  "expected_tool": "tool_name_from_manifest",
  "expected_arguments": {
    "arg1": "value1",
    "filters": { "filter_key": true }
  },
  "description": "Why this tool/args combination is correct"
}
```

## Critical Rules

1. **NEVER create new test scripts** - Use existing `test_planner_behavior.py`
2. **NEVER create analysis scripts** - Read CSV files directly
3. **ALWAYS edit existing files** - Append to `planner_test_cases.json`
4. **ALWAYS use venv** - `source ./venv/bin/activate`
5. **ALWAYS load environment** - `export $(cat web/server/.env | grep -v '^#' | xargs)`
6. **ALWAYS run tests and report** - Print CSV path and summary metrics

## Output Format

### After Running Tests
```
Tests completed
Results saved to: tests/aviation_agent/results/planner_test_results_YYYYMMDD_HHMMSS.csv

Summary:
- Total tests: 21
- Passed: 21 (100%)
- Failed: 0 (0%)
- Tool match: 21/21 (100%)
- Args match: 21/21 (100%)
```

## Key Files

- **Test Cases**: `tests/aviation_agent/fixtures/planner_test_cases.json`
- **Test Runner**: `tests/aviation_agent/test_planner_behavior.py`
- **Planner Prompt**: `shared/aviation_agent/planning.py`
- **Tool Definitions**: `shared/aviation_agent/tools.py`
- **Formatter**: `shared/aviation_agent/formatting.py`
