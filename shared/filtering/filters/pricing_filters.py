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
            return False  # Can't check without enrichment data

        try:
            max_fee = float(value)
        except (TypeError, ValueError):
            return True  # Invalid value, skip filter

        try:
            pricing = enrichment_storage.get_pricing_data(airport.ident)
            if not pricing:
                return False  # No pricing data, exclude airport

            # Use C172 landing fee as default (most common GA aircraft)
            landing_fee = pricing.get('landing_fee_c172')
            if landing_fee is None:
                return False  # No fee data, exclude

            try:
                fee_value = float(landing_fee)
                return fee_value <= max_fee
            except (TypeError, ValueError):
                return False  # Invalid fee data
        except Exception:
            # Pricing data table doesn't exist or other error
            return False
