#!/usr/bin/env python3
"""
Fuel availability filters (AVGAS, Jet-A, etc.)
"""
from typing import Any, Optional, TYPE_CHECKING
from euro_aip.models.airport import Airport
from .base import Filter

if TYPE_CHECKING:
    from shared.tool_context import ToolContext


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
        if value is None:
            return True
        has_avgas = bool(getattr(airport, "avgas", False))
        return has_avgas == bool(value)


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
        if value is None:
            return True
        has_jet_a = bool(getattr(airport, "jet_a", False))
        return has_jet_a == bool(value)
