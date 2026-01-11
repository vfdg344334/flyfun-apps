# Agent 3: Validation

## Purpose
Re-run tests after improvements and validate that changes actually improved results without introducing regressions.

## Input Requirements
- Previous test results CSV (before changes)
- Current test results CSV (after changes)

## Process

1. **Compare** two CSV files from `tests/aviation_agent/results/`
2. **Calculate** metrics: pass rate, tool match rate, args match rate
3. **Detect** regressions (tests that were passing but now fail)
4. **Recommend** accept/iterate/reject

## Validation Checklist

1. **Compare Metrics:**
   - Pass rate improvement (PASS / TOTAL)
   - Tool match rate improvement (tool_match=YES / TOTAL)
   - Args match rate improvement (args_match=YES / TOTAL)
   - New failures introduced (regressions)

2. **Quality Assessment:**
   - Did changes address root causes?
   - Are there new systematic issues?
   - Should we iterate again?

3. **Recommendation Criteria:**
   - **Accept**: improvement > 0, no critical regressions
   - **Iterate**: some improvement but issues remain
   - **Reject**: regressions or no improvement

## Example Report

```
Validation Report:

**Before:** (planner_test_results_20251130_170000.csv)
- Pass rate: 52% (11/21)
- Tool match: 86% (18/21)
- Args match: 52% (11/21)

**After:** (planner_test_results_20251130_171500.csv)
- Pass rate: 100% (21/21)
- Tool match: 100% (21/21)
- Args match: 100% (21/21)

**Improvements:** 10 tests fixed
- test_case_1: Arguments now extracted correctly
- test_case_7: Filter recognized properly
...

**Regressions:** None

**Recommendation:** ACCEPT changes
- Significant improvement (+48% pass rate)
- No regressions detected
- All systematic issues resolved
```

## Red Flags

Flag these issues immediately:

- Test case without description
- Tool name not in manifest
- Missing required arguments for tool
- Invented filters that don't exist
- Regressions (previously passing tests now fail)
- Inconsistent patterns (similar questions get different tools)

## Metrics to Track

### Test Quality
- Pass rate: `PASS / TOTAL`
- Tool match rate: `tool_match=YES / TOTAL`
- Args match rate: `args_match=YES / TOTAL`

### Improvement Velocity
- Tests fixed per iteration
- Time to 100% pass rate
- Regression rate per change
