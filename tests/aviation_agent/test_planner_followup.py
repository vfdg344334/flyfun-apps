"""
Behavioral tests for planner follow-up context awareness.

These tests verify that the planner correctly extracts context from conversation
history when the user provides follow-up information (e.g., speed after being asked).

Run with:
    RUN_PLANNER_BEHAVIOR_TESTS=1 pytest tests/aviation_agent/test_planner_followup.py -v
"""
from __future__ import annotations

import json
import os
from typing import Any, Dict, List

import pytest
from langchain_core.messages import AIMessage, HumanMessage
from langchain_openai import ChatOpenAI

from shared.aviation_agent.planning import build_planner_runnable
from shared.aviation_agent.tools import AviationToolClient


def _should_run_behavior_tests() -> bool:
    """Check if behavioral tests should run (require explicit opt-in)."""
    return os.getenv("RUN_PLANNER_BEHAVIOR_TESTS") == "1"


@pytest.fixture(scope="module")
def live_planner_llm():
    """Create a live LLM for planner tests."""
    if not _should_run_behavior_tests():
        pytest.skip("Behavioral tests require RUN_PLANNER_BEHAVIOR_TESTS=1")

    model = os.getenv("AVIATION_AGENT_PLANNER_MODEL", "gpt-4o-mini")
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        pytest.skip("OPENAI_API_KEY not set")

    return ChatOpenAI(model=model, temperature=0, api_key=api_key)


@pytest.fixture(scope="module")
def planner(live_planner_llm, tool_client):
    """Build the planner with live LLM."""
    available_tags = None
    if tool_client._context.rules_manager:
        available_tags = tool_client._context.rules_manager.get_available_tags()

    return build_planner_runnable(
        live_planner_llm,
        tuple(tool_client.tools.values()),
        available_tags=available_tags,
    )


# =============================================================================
# Follow-up Context Tests for calculate_flight_distance
# =============================================================================


class TestPlannerFollowupFlightDistance:
    """Tests for planner handling follow-up speed/aircraft info after distance query."""

    def test_followup_with_explicit_speed(self, planner):
        """
        After asking 'how long to fly', user provides '140 knots'.
        Planner should re-run calculate_flight_distance with cruise_speed_kts=140.
        """
        messages = [
            HumanMessage(content="How long to fly from EGTF to LFMD"),
            AIMessage(content="The distance from Fairoaks (EGTF) to Cannes-Mandelieu (LFMD) is approximately 558 nautical miles. To estimate flight time, what's your cruise speed or aircraft type?"),
            HumanMessage(content="140 knots"),
        ]

        plan = planner.invoke({"messages": messages})

        assert plan.selected_tool == "calculate_flight_distance", \
            f"Expected calculate_flight_distance, got {plan.selected_tool}"

        args = plan.arguments or {}
        assert args.get("cruise_speed_kts") == 140, \
            f"Expected cruise_speed_kts=140, got {args}"

        # Should preserve original locations
        assert "EGTF" in str(args.get("from_location", "")).upper(), \
            f"Expected from_location to contain EGTF, got {args}"
        assert "LFMD" in str(args.get("to_location", "")).upper(), \
            f"Expected to_location to contain LFMD, got {args}"

    def test_followup_with_aircraft_type(self, planner):
        """
        After asking 'how long to fly', user provides 'I fly a DA40'.
        Planner should re-run calculate_flight_distance with aircraft_type.
        """
        messages = [
            HumanMessage(content="How long from EGTF to LFMD"),
            AIMessage(content="The distance is about 558 nm. What's your cruise speed or aircraft type?"),
            HumanMessage(content="I fly a DA40"),
        ]

        plan = planner.invoke({"messages": messages})

        assert plan.selected_tool == "calculate_flight_distance", \
            f"Expected calculate_flight_distance, got {plan.selected_tool}"

        args = plan.arguments or {}

        # Should have aircraft_type
        from shared.aircraft_speeds import normalize_aircraft_type
        aircraft = args.get("aircraft_type", "")
        assert normalize_aircraft_type(aircraft) == "da40", \
            f"Expected aircraft_type DA40, got {args}"

    def test_followup_with_just_aircraft_name(self, planner):
        """
        User just says 'Cessna 172' as follow-up.
        Planner should understand context and use aircraft_type.
        """
        messages = [
            HumanMessage(content="Flight time from London to Nice"),
            AIMessage(content="The distance from London to Nice is approximately 520 nm. To calculate flight time, I need your cruise speed or aircraft type."),
            HumanMessage(content="Cessna 172"),
        ]

        plan = planner.invoke({"messages": messages})

        assert plan.selected_tool == "calculate_flight_distance", \
            f"Expected calculate_flight_distance, got {plan.selected_tool}"

        args = plan.arguments or {}
        from shared.aircraft_speeds import normalize_aircraft_type
        aircraft = args.get("aircraft_type", "")
        assert normalize_aircraft_type(aircraft) == "c172", \
            f"Expected C172, got {args}"


# =============================================================================
# Follow-up Context Tests for find_airports_near_route (time-constrained)
# =============================================================================


class TestPlannerFollowupTimeConstrained:
    """Tests for planner handling follow-up speed info after time-constrained route query."""

    def test_followup_speed_for_time_constrained_search(self, planner):
        """
        After asking for 'stops within 3h', user provides '120 knots'.
        Planner should re-run find_airports_near_route with speed.
        """
        messages = [
            HumanMessage(content="Where can I stop within 3h from EGTF to LFMD"),
            AIMessage(content="To find airports within 3 hours flight time, I need to know your cruise speed. What's your cruise speed or aircraft type?"),
            HumanMessage(content="120 knots"),
        ]

        plan = planner.invoke({"messages": messages})

        assert plan.selected_tool == "find_airports_near_route", \
            f"Expected find_airports_near_route, got {plan.selected_tool}"

        args = plan.arguments or {}
        assert args.get("cruise_speed_kts") == 120, \
            f"Expected cruise_speed_kts=120, got {args}"
        assert args.get("max_leg_time_hours") == 3, \
            f"Expected max_leg_time_hours=3, got {args}"

    def test_followup_aircraft_for_time_constrained_search(self, planner):
        """
        After asking for 'fuel stop within 2h', user provides 'SR22'.
        Planner should re-run find_airports_near_route with aircraft_type.
        """
        messages = [
            HumanMessage(content="Fuel stop within 2 hours between EGKB and LFMD"),
            AIMessage(content="I can help find fuel stops within 2 hours. What aircraft are you flying or what's your cruise speed?"),
            HumanMessage(content="SR22"),
        ]

        plan = planner.invoke({"messages": messages})

        assert plan.selected_tool == "find_airports_near_route", \
            f"Expected find_airports_near_route, got {plan.selected_tool}"

        args = plan.arguments or {}
        from shared.aircraft_speeds import normalize_aircraft_type
        aircraft = args.get("aircraft_type", "")
        assert normalize_aircraft_type(aircraft) == "sr22", \
            f"Expected SR22, got {args}"

        assert args.get("max_leg_time_hours") == 2, \
            f"Expected max_leg_time_hours=2, got {args}"

        # Should also preserve fuel filter context
        filters = args.get("filters", {})
        assert filters.get("has_avgas") is True or "fuel" in str(messages[0].content).lower(), \
            "Expected fuel filter or fuel context preserved"
