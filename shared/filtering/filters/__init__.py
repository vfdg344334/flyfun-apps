#!/usr/bin/env python3
"""
Airport filtering system - filter implementations.
"""
from .base import Filter
from .basic_filters import (
    CountryFilter,
    HasProceduresFilter,
    HasAipDataFilter,
    HasHardRunwayFilter,
    PointOfEntryFilter,
    ExcludeLargeAirportsFilter,
)
from .runway_filters import (
    MaxRunwayLengthFilter,
    MinRunwayLengthFilter,
)
from .fuel_filters import (
    HasAvgasFilter,
    HasJetAFilter,
    FuelTypeFilter,
)
from .pricing_filters import (
    MaxLandingFeeFilter,
)
from .distance_filters import (
    TripDistanceFilter,
)
from .hospitality_filters import (
    HotelFilter,
    RestaurantFilter,
)

__all__ = [
    "Filter",
    # Basic filters
    "CountryFilter",
    "HasProceduresFilter",
    "HasAipDataFilter",
    "HasHardRunwayFilter",
    "PointOfEntryFilter",
    "ExcludeLargeAirportsFilter",
    # Runway filters
    "MaxRunwayLengthFilter",
    "MinRunwayLengthFilter",
    # Fuel filters
    "HasAvgasFilter",
    "HasJetAFilter",
    "FuelTypeFilter",
    # Pricing filters
    "MaxLandingFeeFilter",
    # Distance filters
    "TripDistanceFilter",
    # Hospitality filters
    "HotelFilter",
    "RestaurantFilter",
]
