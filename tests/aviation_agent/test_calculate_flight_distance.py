"""
Unit tests for the calculate_flight_distance tool.

Tests cover:
- Basic distance calculation between airports
- missing_info behavior when speed not provided
- Aircraft type lookup for speed resolution
- Explicit cruise speed handling
- Location resolution (ICAO codes and city names)
"""
from __future__ import annotations

import pytest

from shared.airport_tools import calculate_flight_distance
from shared.aircraft_speeds import (
    resolve_cruise_speed,
    normalize_aircraft_type,
    get_aircraft_info,
    format_time,
    AIRCRAFT_CRUISE_SPEEDS,
)


# =============================================================================
# Aircraft Speeds Module Tests
# =============================================================================


class TestNormalizeAircraftType:
    """Tests for aircraft type normalization."""

    def test_direct_key_match(self):
        assert normalize_aircraft_type("c172") == "c172"
        assert normalize_aircraft_type("sr22") == "sr22"

    def test_case_insensitive(self):
        assert normalize_aircraft_type("C172") == "c172"
        assert normalize_aircraft_type("SR22") == "sr22"

    def test_full_name_to_code(self):
        assert normalize_aircraft_type("Cessna 172") == "c172"
        assert normalize_aircraft_type("cessna172") == "c172"
        assert normalize_aircraft_type("Cessna-172") == "c172"

    def test_aliases(self):
        assert normalize_aircraft_type("skyhawk") == "c172"
        assert normalize_aircraft_type("skylane") == "c182"
        assert normalize_aircraft_type("bonanza") == "be36"
        assert normalize_aircraft_type("cherokee") == "pa28"

    def test_piper_models(self):
        assert normalize_aircraft_type("PA28") == "pa28"
        assert normalize_aircraft_type("piper 28") == "pa28"

    def test_cirrus_models(self):
        assert normalize_aircraft_type("SR22") == "sr22"
        assert normalize_aircraft_type("sr22t") == "sr22t"

    def test_diamond_models(self):
        assert normalize_aircraft_type("DA40") == "da40"
        assert normalize_aircraft_type("DA42") == "da42"


class TestGetAircraftInfo:
    """Tests for aircraft info lookup."""

    def test_known_aircraft(self):
        info = get_aircraft_info("c172")
        assert info is not None
        assert info["name"] == "Cessna 172"
        assert info["cruise_kts"] == 120

    def test_unknown_aircraft(self):
        info = get_aircraft_info("unknown_plane")
        assert info is None

    def test_alias_lookup(self):
        info = get_aircraft_info("skyhawk")
        assert info is not None
        assert info["name"] == "Cessna 172"


class TestResolveCruiseSpeed:
    """Tests for cruise speed resolution."""

    def test_explicit_speed_takes_precedence(self):
        speed, source = resolve_cruise_speed(cruise_speed_kts=140)
        assert speed == 140.0
        assert source == "provided"

    def test_explicit_speed_over_aircraft_type(self):
        speed, source = resolve_cruise_speed(cruise_speed_kts=140, aircraft_type="c172")
        assert speed == 140.0
        assert source == "provided"

    def test_aircraft_type_lookup(self):
        speed, source = resolve_cruise_speed(aircraft_type="c172")
        assert speed == 120.0
        assert "Cessna 172" in source

    def test_unknown_aircraft_returns_none(self):
        speed, source = resolve_cruise_speed(aircraft_type="unknown_plane")
        assert speed is None
        assert source is None

    def test_neither_provided_returns_none(self):
        speed, source = resolve_cruise_speed()
        assert speed is None
        assert source is None


class TestFormatTime:
    """Tests for time formatting."""

    def test_hours_and_minutes(self):
        assert format_time(4.5) == "4h 30m"
        assert format_time(2.25) == "2h 15m"

    def test_whole_hours(self):
        assert format_time(3.0) == "3h"

    def test_minutes_only(self):
        assert format_time(0.5) == "30m"
        assert format_time(0.75) == "45m"

    def test_rounding(self):
        # 4.65 hours = 4h 39m
        assert format_time(4.65) == "4h 39m"


# =============================================================================
# Calculate Flight Distance Tool Tests
# =============================================================================


class TestCalculateFlightDistanceBasic:
    """Basic functionality tests for calculate_flight_distance."""

    def test_distance_between_icao_codes(self, tool_client):
        """Test basic distance calculation between two ICAO codes."""
        ctx = tool_client._context
        result = calculate_flight_distance(ctx, "EGTF", "LFMD")

        assert result["found"] is True
        assert result["from"]["icao"] == "EGTF"
        assert result["to"]["icao"] == "LFMD"
        assert result["distance_nm"] > 500  # ~558nm
        assert result["distance_nm"] < 600

    def test_visualization_included(self, tool_client):
        """Test that visualization data is included."""
        ctx = tool_client._context
        result = calculate_flight_distance(ctx, "EGTF", "LFMD")

        assert "visualization" in result
        assert result["visualization"]["type"] == "route"
        assert "route" in result["visualization"]
        assert result["visualization"]["route"]["from"]["icao"] == "EGTF"
        assert result["visualization"]["route"]["to"]["icao"] == "LFMD"


class TestCalculateFlightDistanceMissingInfo:
    """Tests for missing_info behavior."""

    def test_missing_info_when_no_speed(self, tool_client):
        """When no speed provided, missing_info should request cruise_speed."""
        ctx = tool_client._context
        result = calculate_flight_distance(ctx, "EGTF", "LFMD")

        assert result["found"] is True
        assert result["distance_nm"] is not None  # Distance should still be provided
        assert result["cruise_speed_kts"] is None
        assert result["estimated_time_formatted"] is None

        # Check missing_info structure
        assert len(result["missing_info"]) == 1
        missing = result["missing_info"][0]
        assert missing["key"] == "cruise_speed"
        assert "reason" in missing
        assert "prompt" in missing
        assert "examples" in missing
        assert len(missing["examples"]) > 0

    def test_no_missing_info_with_explicit_speed(self, tool_client):
        """When speed is provided, missing_info should be empty."""
        ctx = tool_client._context
        result = calculate_flight_distance(ctx, "EGTF", "LFMD", cruise_speed_kts=140)

        assert result["found"] is True
        assert result["cruise_speed_kts"] == 140.0
        assert result["cruise_speed_source"] == "provided"
        assert result["estimated_time_formatted"] is not None
        assert result["missing_info"] == []

    def test_no_missing_info_with_aircraft_type(self, tool_client):
        """When aircraft type is provided, missing_info should be empty."""
        ctx = tool_client._context
        result = calculate_flight_distance(ctx, "EGTF", "LFMD", aircraft_type="C172")

        assert result["found"] is True
        assert result["cruise_speed_kts"] == 120.0
        assert "Cessna 172" in result["cruise_speed_source"]
        assert result["estimated_time_formatted"] is not None
        assert result["missing_info"] == []


class TestCalculateFlightDistanceTimeCalculation:
    """Tests for flight time calculation."""

    def test_time_calculation_with_speed(self, tool_client):
        """Test that time is calculated correctly with explicit speed."""
        ctx = tool_client._context
        result = calculate_flight_distance(ctx, "EGTF", "LFMD", cruise_speed_kts=120)

        assert result["estimated_time_hours"] is not None
        assert result["estimated_time_formatted"] is not None

        # ~558nm at 120kts = ~4.65 hours
        assert 4.0 < result["estimated_time_hours"] < 5.0
        assert "4h" in result["estimated_time_formatted"]

    def test_time_calculation_with_aircraft_type(self, tool_client):
        """Test time calculation using aircraft type lookup."""
        ctx = tool_client._context
        result = calculate_flight_distance(ctx, "EGTF", "LFMD", aircraft_type="SR22")

        # SR22 cruise speed is 170kts
        assert result["cruise_speed_kts"] == 170.0
        assert result["estimated_time_hours"] is not None

        # ~558nm at 170kts = ~3.28 hours
        assert 3.0 < result["estimated_time_hours"] < 4.0

    def test_various_aircraft_types(self, tool_client):
        """Test with various aircraft types."""
        ctx = tool_client._context

        test_cases = [
            ("C172", 120),
            ("SR22", 170),
            ("PA28", 125),
            ("DA40", 130),
            ("Cessna 182", 145),
            ("Bonanza", 170),  # be36
        ]

        for aircraft, expected_speed in test_cases:
            result = calculate_flight_distance(
                ctx, "EGTF", "LFMD", aircraft_type=aircraft
            )
            assert result["cruise_speed_kts"] == expected_speed, (
                f"Expected {expected_speed} kts for {aircraft}, "
                f"got {result['cruise_speed_kts']}"
            )
            assert result["missing_info"] == []


class TestCalculateFlightDistanceLocationResolution:
    """Tests for location resolution (geocoding)."""

    def test_city_names_geocoding(self, tool_client):
        """Test that city names return appropriate response.

        Note: Geocoding requires API access which may not be available in tests.
        This test verifies the behavior is correct regardless.
        """
        ctx = tool_client._context
        result = calculate_flight_distance(ctx, "London", "Paris", cruise_speed_kts=120)

        # If geocoding works, should find airports
        # If not, should return helpful missing_info
        if result["found"]:
            assert result["distance_nm"] is not None
        else:
            # Should have missing_info explaining the issue
            assert len(result["missing_info"]) > 0
            assert result["missing_info"][0]["key"] in ("from_location", "to_location")

    def test_invalid_icao_returns_error(self, tool_client):
        """Test that invalid ICAO codes return appropriate error."""
        ctx = tool_client._context
        result = calculate_flight_distance(ctx, "ZZZZ", "LFMD")

        # Should not find ZZZZ
        assert result["found"] is False
        assert "error" in result or len(result.get("missing_info", [])) > 0


class TestCalculateFlightDistanceEdgeCases:
    """Edge case tests."""

    def test_same_airport(self, tool_client):
        """Test distance between same airport."""
        ctx = tool_client._context
        result = calculate_flight_distance(ctx, "EGTF", "EGTF", cruise_speed_kts=120)

        assert result["found"] is True
        assert result["distance_nm"] == 0.0

    def test_speed_zero_handled(self, tool_client):
        """Test that zero speed doesn't cause division by zero."""
        ctx = tool_client._context
        # Zero speed should be treated as "no speed provided"
        result = calculate_flight_distance(ctx, "EGTF", "LFMD", cruise_speed_kts=0)

        # Either returns missing_info or handles gracefully
        assert result["found"] is True
