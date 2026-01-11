# Agent 1: Ground Truth Generator

## Purpose
Learn patterns from existing test cases to generate expected tool selection and arguments for new test questions.

## Input Requirements
- Existing test cases from `tests/aviation_agent/fixtures/planner_test_cases.json`
- New test questions (user-provided)
- Tool catalog from `shared/aviation_agent/tools.py`

## Process

1. **Read** existing test cases from JSON file
2. **Read** tool catalog from `shared/aviation_agent/tools.py`
3. **Learn** patterns from existing test cases
4. **Generate** new test cases following the same JSON format
5. **Append** new test cases to the existing JSON file

## Pattern Learning Rules

### Tool Selection

| Query Pattern | Tool |
|--------------|------|
| Routes (from X to Y, between X and Y) | `find_airports_near_route` |
| Near location (near X, around X) | `find_airports_near_location` |
| Airport details (details for ICAO) | `get_airport_details` |
| Country search (airports in X) | `search_airports` |
| Notification/customs timing | `get_notification_for_airport` |
| Rules question (ONE country) | `answer_rules_question` |
| Rules listing (show all, list) | `browse_rules` |
| Rules comparison (2+ countries) | `compare_rules_between_countries` |

### Argument Extraction

- **Route queries**: Extract `from_location` and `to_location`
- **Location queries**: Extract `location_query` (include country if mentioned)
- **ICAO codes**: Pass exactly as provided (4 uppercase letters)
- **Location names**: Include country context when provided
- **Filters**: Only include filters explicitly mentioned by user

### Critical Rules

- Preserve country context: "Vik, Iceland" not just "Vik"
- Pass locations exactly as user provides them
- Only include filters explicitly mentioned by user
- ICAO codes are 4 uppercase letters
- For rules tools: pass original question text in `question` field

## Example

Given questions:
```
1. Find fuel stops between KJFK and EGLL
2. What are customs rules for Spain?
3. Compare VFR rules in France and Germany
```

Generate:
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
    "expected_tool": "answer_rules_question",
    "expected_arguments": {
      "country_code": "ES",
      "question": "What are customs rules for Spain?"
    },
    "description": "Single country rules question"
  },
  {
    "question": "Compare VFR rules in France and Germany",
    "expected_tool": "compare_rules_between_countries",
    "expected_arguments": {
      "countries": ["FR", "DE"],
      "tags": ["vfr"]
    },
    "description": "VFR rules comparison between two countries"
  }
]
```

## Output Format

```
Generated X new test cases:

1. Question: "..."
   Expected Tool: tool_name
   Arguments: {...}
   Reasoning: Why this is correct

Appended to tests/aviation_agent/fixtures/planner_test_cases.json
Total test cases now: YY
```
