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
    """Filter airports by maximum landing fee."""
    name = "max_landing_fee"
    description = "Filter by maximum landing fee (C172) in local currency"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None:
            return True  # Not filtering by landing fee

        enrichment_storage = getattr(context, "enrichment_storage", None)
        if not enrichment_storage:
            return True  # No enrichment data - don't filter (graceful degradation)

        try:
            max_fee = float(value)
        except (TypeError, ValueError):
            return True  # Invalid value, skip filter

        try:
            pricing = enrichment_storage.get_pricing_data(airport.ident)
            if not pricing:
                return True  # No pricing data for this airport - don't filter

            # Use C172 landing fee as default (most common GA aircraft)
            landing_fee = pricing.get('landing_fee_c172')
            if landing_fee is None:
                return True  # No fee data - don't filter

            try:
                fee_value = float(landing_fee)
                return fee_value <= max_fee
            except (TypeError, ValueError):
                return True  # Invalid fee data - don't filter
        except Exception:
            # Pricing data table doesn't exist or other error - don't filter
            return True
