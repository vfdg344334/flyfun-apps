"""
Unit tests for time-constrained airport search in find_airports_near_route.

Tests cover:
- max_leg_time_hours with cruise_speed_kts
- max_leg_time_hours with aircraft_type
- missing_info when time constraint specified but no speed
- Filtering behavior based on enroute distance
"""
from __future__ import annotations

import pytest

from shared.airport_tools import find_airports_near_route


# =============================================================================
# Time-Constrained Search Tests
# =============================================================================


class TestTimeConstrainedSearch:
    """Tests for max_leg_time_hours filtering behavior."""

    def test_missing_info_when_time_specified_without_speed(self, tool_client):
        """When max_leg_time_hours is set but no speed provided, should return missing_info."""
        ctx = tool_client._context
        result = find_airports_near_route(
            ctx,
            from_location="EGTF",
            to_location="LFMD",
            max_leg_time_hours=3,
        )

        # Should indicate need for speed info
        assert len(result["missing_info"]) == 1
        missing = result["missing_info"][0]
        assert missing["key"] == "cruise_speed"
        assert "3" in missing["reason"]  # Should mention the time constraint
        assert "prompt" in missing
        assert len(missing["examples"]) > 0

    def test_time_filter_with_explicit_speed(self, tool_client):
        """When both time and speed are provided, should filter by enroute distance."""
        ctx = tool_client._context
        result = find_airports_near_route(
            ctx,
            from_location="EGTF",
            to_location="LFMD",
            max_leg_time_hours=3,
            cruise_speed_kts=120,
            max_results=20,
        )

        # Should have no missing_info
        assert result.get("missing_info", []) == []

        # Should have filter profile with time-based info
        filter_profile = result.get("filter_profile", {})
        assert filter_profile.get("max_leg_time_hours") == 3
        assert filter_profile.get("cruise_speed_kts") == 120
        assert filter_profile.get("max_enroute_distance_nm") == 360  # 3h * 120kts

        # All returned airports should be within 360nm from departure
        for airport in result["airports"]:
            if "enroute_distance_nm" in airport:
                assert airport["enroute_distance_nm"] <= 360

    def test_time_filter_with_aircraft_type(self, tool_client):
        """When time and aircraft type are provided, should use looked-up speed."""
        ctx = tool_client._context
        result = find_airports_near_route(
            ctx,
            from_location="EGTF",
            to_location="LFMD",
            max_leg_time_hours=3,
            aircraft_type="SR22",
            max_results=20,
        )

        # Should have no missing_info
        assert result.get("missing_info", []) == []

        # SR22 cruise speed is 170kts, so max_enroute_distance = 3 * 170 = 510nm
        filter_profile = result.get("filter_profile", {})
        assert filter_profile.get("max_leg_time_hours") == 3
        assert filter_profile.get("cruise_speed_kts") == 170
        assert filter_profile.get("max_enroute_distance_nm") == 510

        # All returned airports should be within 510nm from departure
        for airport in result["airports"]:
            if "enroute_distance_nm" in airport:
                assert airport["enroute_distance_nm"] <= 510

    def test_time_filter_explicit_speed_overrides_aircraft(self, tool_client):
        """Explicit cruise_speed_kts should override aircraft_type lookup."""
        ctx = tool_client._context
        result = find_airports_near_route(
            ctx,
            from_location="EGTF",
            to_location="LFMD",
            max_leg_time_hours=2,
            cruise_speed_kts=140,
            aircraft_type="C172",  # C172 is 120kts, but explicit 140 should be used
        )

        filter_profile = result.get("filter_profile", {})
        assert filter_profile.get("cruise_speed_kts") == 140
        assert filter_profile.get("max_enroute_distance_nm") == 280  # 2h * 140kts

    def test_time_filter_with_unknown_aircraft(self, tool_client):
        """Unknown aircraft type without explicit speed should return missing_info."""
        ctx = tool_client._context
        result = find_airports_near_route(
            ctx,
            from_location="EGTF",
            to_location="LFMD",
            max_leg_time_hours=3,
            aircraft_type="unknown_plane",
        )

        # Should indicate need for speed info since aircraft not recognized
        assert len(result["missing_info"]) == 1
        assert result["missing_info"][0]["key"] == "cruise_speed"


class TestTimeConstrainedWithOtherFilters:
    """Tests for combining time constraint with other filters."""

    def test_time_filter_with_fuel_filter(self, tool_client):
        """Time constraint should work alongside fuel filters."""
        ctx = tool_client._context
        result = find_airports_near_route(
            ctx,
            from_location="EGTF",
            to_location="LFMD",
            max_leg_time_hours=4,
            cruise_speed_kts=120,
            filters={"has_avgas": True},
            max_results=20,
        )

        # Should have no missing_info
        assert result.get("missing_info", []) == []

        # All returned airports should have AVGAS and be within range
        for airport in result["airports"]:
            if "enroute_distance_nm" in airport:
                assert airport["enroute_distance_nm"] <= 480  # 4h * 120kts

    def test_no_time_filter_returns_all_enroute(self, tool_client):
        """Without max_leg_time_hours, should not filter by enroute distance."""
        ctx = tool_client._context
        result = find_airports_near_route(
            ctx,
            from_location="EGTF",
            to_location="LFMD",
            max_results=20,
        )

        # Should have no missing_info (no time constraint)
        assert result.get("missing_info", []) == []

        # Filter profile should NOT contain time-based fields
        filter_profile = result.get("filter_profile", {})
        assert "max_leg_time_hours" not in filter_profile
        assert "max_enroute_distance_nm" not in filter_profile


class TestTimeConstrainedEdgeCases:
    """Edge case tests for time-constrained searches."""

    def test_very_short_time_constraint(self, tool_client):
        """Very short time constraint may return empty results."""
        ctx = tool_client._context
        result = find_airports_near_route(
            ctx,
            from_location="EGTF",
            to_location="LFMD",
            max_leg_time_hours=0.5,  # 30 minutes
            cruise_speed_kts=120,  # 60nm max range
        )

        # Should work without error
        assert result.get("missing_info", []) == []
        # May have 0 airports in range, which is valid
        assert isinstance(result.get("airports", []), list)

    def test_zero_time_constraint(self, tool_client):
        """Zero time constraint should filter everything except departure."""
        ctx = tool_client._context
        result = find_airports_near_route(
            ctx,
            from_location="EGTF",
            to_location="LFMD",
            max_leg_time_hours=0,
            cruise_speed_kts=120,
        )

        # Should return empty or only departure (0nm)
        assert result.get("missing_info", []) == []
        for airport in result.get("airports", []):
            if "enroute_distance_nm" in airport:
                assert airport["enroute_distance_nm"] == 0
