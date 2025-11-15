#!/usr/bin/env python3
"""
Fuel availability filters (AVGAS, Jet-A, etc.)
"""
from typing import Any, Optional, TYPE_CHECKING
from euro_aip.models.airport import Airport
from .base import Filter

if TYPE_CHECKING:
    from shared.airport_tools import ToolContext


class HasAvgasFilter(Filter):
    """Filter airports by AVGAS availability."""
    name = "has_avgas"
    description = "Filter by AVGAS fuel availability (boolean)"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None or not value:
            return True  # Not filtering for AVGAS

        enrichment_storage = getattr(context, "enrichment_storage", None)
        if not enrichment_storage:
            return True  # No enrichment data - don't filter (graceful degradation)

        try:
            fuels = enrichment_storage.get_fuel_availability(airport.ident)
            if not fuels:
                return True  # No fuel data for this airport - don't filter

            has_avgas = any(
                'avgas' in fuel.get('fuel_type', '').lower() and fuel.get('available', False)
                for fuel in fuels
            )

            return has_avgas
        except Exception:
            # Fuel data table doesn't exist or other error - don't filter
            return True


class HasJetAFilter(Filter):
    """Filter airports by Jet-A fuel availability."""
    name = "has_jet_a"
    description = "Filter by Jet-A fuel availability (boolean)"

    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        if value is None or not value:
            return True  # Not filtering for Jet-A

        enrichment_storage = getattr(context, "enrichment_storage", None)
        if not enrichment_storage:
            return True  # No enrichment data - don't filter (graceful degradation)

        try:
            fuels = enrichment_storage.get_fuel_availability(airport.ident)
            if not fuels:
                return True  # No fuel data for this airport - don't filter

            has_jet_a = any(
                ('jeta1' in fuel.get('fuel_type', '').lower() or
                 'jet a1' in fuel.get('fuel_type', '').lower() or
                 'jet a' in fuel.get('fuel_type', '').lower())
                and fuel.get('available', False)
                for fuel in fuels
            )

            return has_jet_a
        except Exception:
            # Fuel data table doesn't exist or other error - don't filter
            return True
