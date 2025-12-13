#!/usr/bin/env python3
"""
Pricing-related filters (landing fees, etc.)
"""
from typing import Any, Optional, TYPE_CHECKING
from euro_aip.models.airport import Airport
from .base import Filter

if TYPE_CHECKING:
    from shared.airport_tools import ToolContext


class MaxLandingFeeFilter(Filter):
    """Filter airports by maximum landing fee (C172 equivalent)."""
    name = "max_landing_fee"
    description = "Filter by maximum landing fee (C172 equivalent) in local currency"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None:
            return True  # Not filtering by landing fee

        if not context or not context.ga_friendliness_service:
            return True  # No GA service - don't filter (graceful degradation)

        try:
            max_fee = float(value)
        except (TypeError, ValueError):
            return True  # Invalid value, skip filter

        try:
            # Use C172 MTOW (1157kg) as default for fee lookup
            from shared.ga_friendliness.features import AIRCRAFT_MTOW_MAP
            default_mtow = AIRCRAFT_MTOW_MAP["c172"]

            fee_data = context.ga_friendliness_service.get_landing_fee_by_weight(
                airport.ident,
                default_mtow
            )
            if not fee_data or fee_data.get('fee') is None:
                return True  # No fee data - don't filter

            try:
                fee_value = float(fee_data['fee'])
                return fee_value <= max_fee
            except (TypeError, ValueError):
                return True  # Invalid fee data - don't filter
        except Exception:
            # Error getting fee data - don't filter (graceful degradation)
            return True
