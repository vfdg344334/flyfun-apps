#!/usr/bin/env python3
"""
Basic airport filters (country, procedures, border crossing, etc.)
"""
from typing import Any, Optional, TYPE_CHECKING
from euro_aip.models.airport import Airport
from .base import Filter

if TYPE_CHECKING:
    from shared.airport_tools import ToolContext

class TripDistanceFilter(Filter):
    """Filter airports by trip distance (in nautical miles)."""
    name = "trip_distance"
    description = "Filter by trip distance range (dict with optional 'min'/'max' keys in NM)"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None or not isinstance(value, dict):
            return True
        max_distance = value.get('max', None)
        min_distance = value.get('min', None)
        if max_distance is not None and min_distance is not None:
            return max_distance >= airport.distance_nm >= min_distance
        elif max_distance is not None:
            return airport.distance_nm <= max_distance
        elif min_distance is not None:
            return airport.distance_nm >= min_distance
        return True

class CountryFilter(Filter):
    """Filter airports by ISO country code."""
    name = "country"
    description = "Filter by country (ISO-2 code, e.g., 'FR', 'GB')"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if not value:
            return True
        country_code = str(value).upper()
        airport_country = (airport.iso_country or "").upper()
        return airport_country == country_code


class HasProceduresFilter(Filter):
    """Filter airports by procedure availability."""
    name = "has_procedures"
    description = "Filter by instrument procedures availability (boolean)"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None:
            return True
        has_procedures = bool(airport.has_procedures)
        return has_procedures == bool(value)


class HasAipDataFilter(Filter):
    """Filter airports by AIP data availability."""
    name = "has_aip_data"
    description = "Filter by AIP data availability (boolean)"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None:
            return True
        has_aip = bool(len(airport.aip_entries) > 0)
        return has_aip == bool(value)


class HasHardRunwayFilter(Filter):
    """Filter airports by hard surface runway availability."""
    name = "has_hard_runway"
    description = "Filter by hard surface runway (boolean)"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None:
            return True
        has_hard = bool(getattr(airport, "has_hard_runway", False))
        return has_hard == bool(value)


class PointOfEntryFilter(Filter):
    """Filter airports by border crossing (customs) capability."""
    name = "point_of_entry"
    description = "Filter by border crossing/customs capability (boolean)"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None:
            return True
        is_poe = bool(getattr(airport, "point_of_entry", False))
        return is_poe == bool(value)
