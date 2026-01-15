"""
Behavioral tests for the aviation agent formatter.

These tests verify that the formatter correctly processes tool results,
including handling missing_info prompts. They require a live LLM.

Run with:
    RUN_FORMATTER_BEHAVIOR_TESTS=1 pytest tests/aviation_agent/test_formatter_behavior.py -v
"""
from __future__ import annotations

import json
import os

import pytest
from langchain_core.messages import HumanMessage
from langchain_openai import ChatOpenAI

from shared.aviation_agent.formatting import build_formatter_chain


def _should_run_behavior_tests() -> bool:
    """Check if behavioral tests should run (require explicit opt-in)."""
    return os.getenv("RUN_FORMATTER_BEHAVIOR_TESTS") == "1"


@pytest.fixture(scope="module")
def formatter_llm():
    """Create a live LLM for formatter tests."""
    if not _should_run_behavior_tests():
        pytest.skip("Behavioral tests require RUN_FORMATTER_BEHAVIOR_TESTS=1")

    model = os.getenv("AVIATION_AGENT_FORMATTER_MODEL", "gpt-4o-mini")
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        pytest.skip("OPENAI_API_KEY not set")

    return ChatOpenAI(model=model, temperature=0, api_key=api_key)


@pytest.fixture(scope="module")
def formatter_chain(formatter_llm):
    """Build the formatter chain with live LLM."""
    return build_formatter_chain(formatter_llm)


# =============================================================================
# missing_info Handling Tests
# =============================================================================


class TestFormatterMissingInfo:
    """Tests for formatter handling of missing_info in tool results."""

    def test_formatter_asks_for_cruise_speed_when_missing(self, formatter_chain):
        """
        When tool result contains missing_info for cruise_speed,
        formatter should ask the user for speed or aircraft type.
        """
        # Simulate tool result from calculate_flight_distance without speed
        tool_result = {
            "found": True,
            "from": {"icao": "EGTF", "name": "Fairoaks"},
            "to": {"icao": "LFMD", "name": "Cannes-Mandelieu"},
            "distance_nm": 558.3,
            "cruise_speed_kts": None,
            "estimated_time_formatted": None,
            "missing_info": [{
                "key": "cruise_speed",
                "reason": "Required to calculate flight time",
                "prompt": "What's your cruise speed or aircraft type?",
                "examples": ["120 knots", "Cessna 172", "SR22"],
            }],
        }

        messages = [HumanMessage(content="How long to fly from EGTF to LFMD")]

        result = formatter_chain.invoke({
            "messages": messages,
            "answer_style": "concise",
            "tool_result_json": json.dumps(tool_result, indent=2),
            "pretty_text": "",
        })

        # Formatter should mention the distance
        assert "558" in result or "559" in result, f"Expected distance in response: {result}"

        # Formatter should ask for speed/aircraft - check for common patterns
        result_lower = result.lower()
        asks_for_speed = any([
            "cruise speed" in result_lower,
            "aircraft type" in result_lower,
            "what speed" in result_lower,
            "how fast" in result_lower,
            "what aircraft" in result_lower,
            "which aircraft" in result_lower,
        ])
        assert asks_for_speed, f"Expected formatter to ask for speed/aircraft: {result}"

    def test_formatter_asks_for_speed_on_route_search(self, formatter_chain):
        """
        When find_airports_near_route returns missing_info for cruise_speed,
        formatter should ask for speed to filter by time.
        """
        tool_result = {
            "found": True,
            "count": 0,
            "airports": [],
            "missing_info": [{
                "key": "cruise_speed",
                "reason": "Required to calculate 3h flight range",
                "prompt": "What's your cruise speed or aircraft type?",
                "examples": ["120 knots", "Cessna 172", "SR22"],
            }],
            "filter_profile": {
                "max_leg_time_hours": 3,
            },
        }

        messages = [HumanMessage(content="Where can I stop within 3h from EGTF to LFMD")]

        result = formatter_chain.invoke({
            "messages": messages,
            "answer_style": "concise",
            "tool_result_json": json.dumps(tool_result, indent=2),
            "pretty_text": "",
        })

        result_lower = result.lower()

        # Should ask for speed/aircraft
        asks_for_speed = any([
            "cruise speed" in result_lower,
            "aircraft type" in result_lower,
            "speed" in result_lower,
            "aircraft" in result_lower,
        ])
        assert asks_for_speed, f"Expected formatter to ask for speed: {result}"

    def test_formatter_includes_distance_with_time(self, formatter_chain):
        """
        When tool result has both distance and time, formatter should include both.
        """
        tool_result = {
            "found": True,
            "from": {"icao": "EGTF", "name": "Fairoaks"},
            "to": {"icao": "LFMD", "name": "Cannes-Mandelieu"},
            "distance_nm": 558.3,
            "cruise_speed_kts": 170,
            "cruise_speed_source": "typical Cirrus SR22 cruise",
            "estimated_time_hours": 3.28,
            "estimated_time_formatted": "3h 17m",
            "missing_info": [],
        }

        messages = [HumanMessage(content="How long to fly from EGTF to LFMD with my SR22")]

        result = formatter_chain.invoke({
            "messages": messages,
            "answer_style": "concise",
            "tool_result_json": json.dumps(tool_result, indent=2),
            "pretty_text": "",
        })

        # Should mention distance
        assert "558" in result or "559" in result, f"Expected distance in response: {result}"

        # Should mention time
        assert "3h" in result or "3 hour" in result.lower(), f"Expected time in response: {result}"

        # Should NOT ask for speed (missing_info is empty)
        result_lower = result.lower()
        assert "what" not in result_lower or "what's your" not in result_lower, \
            f"Should not ask questions when missing_info is empty: {result}"
