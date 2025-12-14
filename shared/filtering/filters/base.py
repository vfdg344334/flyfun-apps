#!/usr/bin/env python3
"""
Base classes for airport filtering system.
"""
from abc import ABC, abstractmethod
from typing import Any, Optional, TYPE_CHECKING
from euro_aip.models.airport import Airport

if TYPE_CHECKING:
    from shared.tool_context import ToolContext


class Filter(ABC):
    """
    Base class for all airport filters.

    Each filter is responsible for evaluating a single criterion.
    Filters can be composed using AND/OR logic.
    """

    # Override these in subclasses
    name: str = "base_filter"
    description: str = "Base filter"

    @abstractmethod
    def apply(
        self,
        airport: Airport,
        value: Any,
        context: Optional["ToolContext"] = None,
    ) -> bool:
        """
        Check if airport passes this filter.

        Args:
            airport: Airport to check
            value: Filter value from user (e.g., country code, boolean, number)
            enrichment_storage: Optional enrichment data (pricing, fuel, etc.)

        Returns:
            True if airport passes filter, False otherwise
        """
        raise NotImplementedError

    def __repr__(self):
        return f"<Filter: {self.name}>"
