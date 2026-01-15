from __future__ import annotations

from shared.aviation_agent.formatting import build_ui_payload, _determine_kind
from shared.aviation_agent.planning import AviationPlan


def test_ui_payload_route_kind():
    plan = AviationPlan(
        selected_tool="search_airports",
        arguments={"departure": "EGTF", "destination": "LSGS"},
    )
    payload = build_ui_payload(plan, {"airports": [], "pretty": "demo"})
    assert payload["kind"] == "route"
    assert payload["departure"] == "EGTF"
    assert payload["destination"] == "LSGS"


def test_ui_payload_none_when_no_tool_result():
    plan = AviationPlan(selected_tool="search_airports", arguments={})
    assert build_ui_payload(plan, None) is None


# =============================================================================
# _determine_kind tests
# =============================================================================


def test_determine_kind_route_tools():
    """Test that route-related tools return 'route' kind."""
    assert _determine_kind("search_airports") == "route"
    assert _determine_kind("find_airports_near_location") == "route"
    assert _determine_kind("find_airports_near_route") == "route"
    assert _determine_kind("calculate_flight_distance") == "route"


def test_determine_kind_airport_tools():
    """Test that airport-specific tools return 'airport' kind."""
    assert _determine_kind("get_airport_details") == "airport"
    assert _determine_kind("get_notification_for_airport") == "airport"


def test_determine_kind_rules_tools():
    """Test that rules tools return 'rules' kind."""
    assert _determine_kind("answer_rules_question") == "rules"
    assert _determine_kind("browse_rules") == "rules"
    assert _determine_kind("compare_rules_between_countries") == "rules"


def test_determine_kind_unknown_tool():
    """Test that unknown tools return None."""
    assert _determine_kind("unknown_tool") is None


# =============================================================================
# calculate_flight_distance UI payload tests
# =============================================================================


def test_ui_payload_calculate_flight_distance():
    """Test UI payload for calculate_flight_distance tool."""
    plan = AviationPlan(
        selected_tool="calculate_flight_distance",
        arguments={"from_location": "EGTF", "to_location": "LFMD"},
    )
    tool_result = {
        "found": True,
        "distance_nm": 558.3,
        "visualization": {
            "type": "route",
            "route": {
                "from": {"icao": "EGTF", "name": "Fairoaks"},
                "to": {"icao": "LFMD", "name": "Cannes-Mandelieu"},
            },
        },
    }

    payload = build_ui_payload(plan, tool_result)

    assert payload is not None
    assert payload["kind"] == "route"
    assert payload["tool"] == "calculate_flight_distance"
    assert payload["departure"] == "EGTF"
    assert payload["destination"] == "LFMD"
    assert payload["visualization"]["type"] == "route"


def test_ui_payload_calculate_flight_distance_includes_visualization():
    """Test that visualization is flattened into UI payload."""
    plan = AviationPlan(
        selected_tool="calculate_flight_distance",
        arguments={"from_location": "EGLL", "to_location": "LFPG"},
    )
    tool_result = {
        "found": True,
        "visualization": {
            "type": "route",
            "route": {"from": {"icao": "EGLL"}, "to": {"icao": "LFPG"}},
        },
    }

    payload = build_ui_payload(plan, tool_result)

    assert "visualization" in payload
    assert payload["visualization"]["type"] == "route"

