#!/usr/bin/env python3
"""
Hospitality-related filters (hotel, restaurant availability).

These filters use AIP-derived data from the GA friendliness service.
They follow a "fail-closed" approach: airports are excluded if data is unavailable.
"""
import logging
from typing import Any, Optional, TYPE_CHECKING
from euro_aip.models.airport import Airport
from .base import Filter

if TYPE_CHECKING:
    from shared.tool_context import ToolContext

logger = logging.getLogger(__name__)


class HotelFilter(Filter):
    """
    Filter airports by hotel availability.

    Filter values:
        - "any": Has hotel (at_airport or vicinity)
        - "at_airport": Hotel on-site at the airport
        - "vicinity": Hotel nearby but not on-site
        - None: No filter applied

    Fail-closed behavior: Excludes airports when:
        - GA service is unavailable
        - No data for airport
        - hotel_info is "unknown" or None
    """

    name = "hotel"
    description = "Filter by hotel availability (any|at_airport|vicinity)"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None:
            return True  # No filter applied

        if not context or not context.ga_friendliness_service:
            return False  # No GA service - exclude (fail closed for AIP filters)

        try:
            # Use service method for consistent data access
            summary = context.ga_friendliness_service.get_summary_dict(airport.ident)
            if not summary or not summary.get("has_data"):
                return False  # No data - exclude

            # hotel_info is a string: "at_airport", "vicinity", "none", "unknown", or None
            hotel_info = summary.get("hotel_info")
            if hotel_info is None or hotel_info == "unknown":
                return False  # No known data - exclude

            if value == "any":
                # "any" means has facility (at_airport or vicinity), excludes "none"
                return hotel_info in ("at_airport", "vicinity")
            elif value == "at_airport":
                return hotel_info == "at_airport"
            elif value == "vicinity":
                return hotel_info == "vicinity"
            else:
                return True  # Unknown filter value - don't filter

        except Exception as e:
            logger.warning(f"Error applying hotel filter to {airport.ident}: {e}")
            return False  # Error - exclude (fail closed)


class RestaurantFilter(Filter):
    """
    Filter airports by restaurant availability.

    Filter values:
        - "any": Has restaurant (at_airport or vicinity)
        - "at_airport": Restaurant on-site at the airport
        - "vicinity": Restaurant nearby but not on-site
        - None: No filter applied

    Fail-closed behavior: Excludes airports when:
        - GA service is unavailable
        - No data for airport
        - restaurant_info is "unknown" or None
    """

    name = "restaurant"
    description = "Filter by restaurant availability (any|at_airport|vicinity)"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None:
            return True  # No filter applied

        if not context or not context.ga_friendliness_service:
            return False  # No GA service - exclude (fail closed for AIP filters)

        try:
            # Use service method for consistent data access
            summary = context.ga_friendliness_service.get_summary_dict(airport.ident)
            if not summary or not summary.get("has_data"):
                return False  # No data - exclude

            # restaurant_info is a string: "at_airport", "vicinity", "none", "unknown", or None
            restaurant_info = summary.get("restaurant_info")
            if restaurant_info is None or restaurant_info == "unknown":
                return False  # No known data - exclude

            if value == "any":
                # "any" means has facility (at_airport or vicinity), excludes "none"
                return restaurant_info in ("at_airport", "vicinity")
            elif value == "at_airport":
                return restaurant_info == "at_airport"
            elif value == "vicinity":
                return restaurant_info == "vicinity"
            else:
                return True  # Unknown filter value - don't filter

        except Exception as e:
            logger.warning(f"Error applying restaurant filter to {airport.ident}: {e}")
            return False  # Error - exclude (fail closed)
