"""
Behavioral tests for the GA notification agent parser.

These tests verify that the parser correctly extracts notification rules
from AIP text. Tests are split into:
- Regex-only tests: Run without LLM, test simple patterns
- LLM tests: Require OPENAI_API_KEY, test complex patterns

Run with:
    pytest tests/ga_notification_agent/                    # Regex-only tests
    pytest tests/ga_notification_agent/ -m parser_llm     # Include LLM tests

Or set environment variable:
    RUN_PARSER_LLM_TESTS=1 pytest tests/ga_notification_agent/
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, Dict, List

import pytest

from shared.ga_notification_agent import NotificationParser
from shared.ga_notification_agent.config import get_notification_config


def _load_test_cases() -> List[Dict[str, Any]]:
    """Load test cases from JSON fixture file."""
    fixture_path = Path(__file__).parent / "fixtures" / "parser_test_cases.json"
    with open(fixture_path) as f:
        all_cases = json.load(f)
    # Filter out comment-only entries
    return [tc for tc in all_cases if "text" in tc]


def _load_regex_test_cases() -> List[Dict[str, Any]]:
    """Load only test cases that don't require LLM."""
    return [tc for tc in _load_test_cases() if not tc.get("requires_llm", False)]


def _load_llm_test_cases() -> List[Dict[str, Any]]:
    """Load only test cases that require LLM."""
    return [tc for tc in _load_test_cases() if tc.get("requires_llm", False)]


def _should_run_llm_tests() -> bool:
    """Check if LLM tests should run."""
    return os.getenv("RUN_PARSER_LLM_TESTS") == "1"


@pytest.fixture(scope="module")
def regex_parser():
    """Parser with LLM disabled (regex-only)."""
    return NotificationParser(use_llm_fallback=False)


@pytest.fixture(scope="module")
def llm_parser():
    """Parser with LLM enabled."""
    if not _should_run_llm_tests():
        pytest.skip("LLM tests require RUN_PARSER_LLM_TESTS=1")

    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        pytest.skip("OPENAI_API_KEY not set")

    return NotificationParser(use_llm_fallback=True)


class TestParserRegex:
    """Tests that run with regex-only parsing (no LLM required)."""

    @pytest.mark.parametrize(
        "test_case",
        _load_regex_test_cases(),
        ids=lambda tc: f"{tc.get('icao', 'X')}: {tc.get('description', tc.get('text', '')[:30])}"
    )
    def test_parser_extracts_correct_rules(
        self,
        test_case: Dict[str, Any],
        regex_parser: NotificationParser,
    ):
        """Test that parser extracts expected notification rules."""
        icao = test_case["icao"]
        text = test_case["text"]
        expected = test_case["expected"]
        description = test_case.get("description", "")

        # Parse the text
        result = regex_parser.parse(icao, text)

        # Print for visibility
        print(f"\n{'='*60}")
        print(f"ICAO: {icao}")
        print(f"Text: {text}")
        print(f"Description: {description}")
        print(f"Rules found: {len(result.rules)}")
        for rule in result.rules:
            print(f"  - {rule.notification_type.value}: {rule.hours_notice}h, conf={rule.confidence:.2f}")
        print(f"{'='*60}")

        # Check notification type
        if "notification_type" in expected:
            expected_type = expected["notification_type"]
            if result.rules:
                # Check if any rule matches the expected type
                actual_types = [r.notification_type.value for r in result.rules]
                assert expected_type in actual_types, (
                    f"Expected notification_type '{expected_type}' not found. "
                    f"Got: {actual_types}. Description: {description}"
                )
            else:
                pytest.fail(f"No rules parsed. Expected: {expected_type}. Description: {description}")

        # Check hours notice
        if "hours_notice" in expected:
            expected_hours = expected["hours_notice"]
            if expected_hours is not None:
                actual_hours = result.max_hours_notice
                assert actual_hours == expected_hours, (
                    f"Expected hours_notice={expected_hours}, got {actual_hours}. "
                    f"Description: {description}"
                )

        # Check specific time (for business day rules)
        if "specific_time" in expected:
            expected_time = expected["specific_time"]
            actual_times = [r.specific_time for r in result.rules if r.specific_time]
            assert expected_time in actual_times, (
                f"Expected specific_time '{expected_time}' not found. "
                f"Got: {actual_times}. Description: {description}"
            )

        # Check weekend rules
        if expected.get("has_weekend_rules"):
            has_weekend = any(
                r.weekday_start is not None and r.weekday_start >= 5
                for r in result.rules
            )
            assert has_weekend, (
                f"Expected weekend rules but none found. Description: {description}"
            )

        # Check non-Schengen only
        if expected.get("non_schengen_only"):
            has_non_schengen = any(r.non_schengen_only for r in result.rules)
            assert has_non_schengen, (
                f"Expected non_schengen_only rule but none found. Description: {description}"
            )


@pytest.mark.parser_llm
class TestParserLLM:
    """Tests that require LLM (complex patterns)."""

    @pytest.mark.parametrize(
        "test_case",
        _load_llm_test_cases(),
        ids=lambda tc: f"{tc.get('icao', 'X')}: {tc.get('description', tc.get('text', '')[:30])}"
    )
    def test_parser_handles_complex_rules(
        self,
        test_case: Dict[str, Any],
        llm_parser: NotificationParser,
    ):
        """Test that parser handles complex rules with LLM."""
        icao = test_case["icao"]
        text = test_case["text"]
        expected = test_case["expected"]
        description = test_case.get("description", "")

        # Parse the text
        result = llm_parser.parse(icao, text)

        # Print for visibility
        print(f"\n{'='*60}")
        print(f"ICAO: {icao}")
        print(f"Text: {text}")
        print(f"Description: {description}")
        print(f"Rules found: {len(result.rules)}")
        for rule in result.rules:
            print(f"  - {rule.notification_type.value}: {rule.hours_notice}h")
            print(f"    method={rule.extraction_method}, conf={rule.confidence:.2f}")
            if rule.schengen_only or rule.non_schengen_only:
                print(f"    schengen_only={rule.schengen_only}, non_schengen_only={rule.non_schengen_only}")
        print(f"{'='*60}")

        # Check notification type
        if "notification_type" in expected:
            expected_type = expected["notification_type"]
            if result.rules:
                actual_types = [r.notification_type.value for r in result.rules]
                assert expected_type in actual_types, (
                    f"Expected notification_type '{expected_type}' not found. "
                    f"Got: {actual_types}. Description: {description}"
                )
            else:
                pytest.fail(f"No rules parsed. Expected: {expected_type}")

        # Check hours notice (max across all rules)
        if "hours_notice" in expected:
            expected_hours = expected["hours_notice"]
            if expected_hours is not None:
                actual_hours = result.max_hours_notice
                assert actual_hours == expected_hours, (
                    f"Expected max hours_notice={expected_hours}, got {actual_hours}. "
                    f"Description: {description}"
                )

        # Check Schengen rules present
        if expected.get("has_schengen_rules"):
            has_schengen = any(
                r.schengen_only or r.non_schengen_only
                for r in result.rules
            )
            assert has_schengen, (
                f"Expected Schengen-specific rules but none found. Description: {description}"
            )

        # Check weekend rules present
        if expected.get("has_weekend_rules"):
            has_weekend = any(
                r.weekday_start is not None and r.weekday_start >= 5
                for r in result.rules
            )
            assert has_weekend, (
                f"Expected weekend rules but none found. Description: {description}"
            )


class TestParserConfig:
    """Test configuration loading."""

    def test_config_loads_successfully(self):
        """Test that config loads without errors."""
        config = get_notification_config()
        assert config is not None
        assert config.llm.model == "gpt-4o-mini"
        assert config.parsing.use_llm_fallback is True

    def test_parser_uses_config(self):
        """Test that parser loads config correctly."""
        parser = NotificationParser()
        assert parser._config is not None
        assert parser._confidence is not None
        assert parser._complexity_threshold == 2

    def test_parser_override_config(self):
        """Test that parser parameters override config."""
        parser = NotificationParser(
            use_llm_fallback=False,
            llm_model="gpt-4o",
        )
        assert parser.use_llm_fallback is False
        assert parser.llm_model == "gpt-4o"
