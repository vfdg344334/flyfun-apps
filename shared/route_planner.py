"""
Multi-stop route planner using A* algorithm with persona-aware cost function.

This module provides route planning capabilities for GA flights with multiple
intermediate stops. It considers aircraft performance, persona preferences,
and airport suitability when selecting optimal stops.
"""

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple
import heapq
import logging
import math

logger = logging.getLogger(__name__)


@dataclass
class RouteLeg:
    """Single leg of a multi-leg route."""
    from_icao: str
    to_icao: str
    distance_nm: float
    airport_info: Dict[str, Any] = field(default_factory=dict)


@dataclass
class PlannedRoute:
    """Complete planned route with multiple stops."""
    legs: List[RouteLeg]
    stops: List[Dict[str, Any]]  # Airport details at each stop (excluding departure)
    total_distance_nm: float
    estimated_time_hrs: float
    persona_score: float  # Overall route quality score
    
    @property
    def num_stops(self) -> int:
        """Number of intermediate stops (excluding destination)."""
        return len(self.stops) - 1 if self.stops else 0


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate great-circle distance between two points in nautical miles.
    
    Args:
        lat1, lon1: Coordinates of point 1 (degrees)
        lat2, lon2: Coordinates of point 2 (degrees)
        
    Returns:
        Distance in nautical miles
    """
    R = 3440.065  # Earth radius in nautical miles
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = (math.sin(delta_lat / 2) ** 2 + 
         math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    
    return R * c


def cross_track_distance(
    point_lat: float, point_lon: float,
    start_lat: float, start_lon: float,
    end_lat: float, end_lon: float
) -> float:
    """
    Calculate cross-track distance from a point to the great-circle path.
    
    Returns the perpendicular distance in nm from the point to the route.
    Positive = right of track, negative = left of track.
    """
    R = 3440.065  # Earth radius in nm
    
    # Convert to radians
    lat1 = math.radians(start_lat)
    lon1 = math.radians(start_lon)
    lat2 = math.radians(end_lat)
    lon2 = math.radians(end_lon)
    lat3 = math.radians(point_lat)
    lon3 = math.radians(point_lon)
    
    # Angular distance from start to point
    d13 = haversine_distance(start_lat, start_lon, point_lat, point_lon) / R
    
    # Initial bearing from start to end
    theta13 = math.atan2(
        math.sin(lon3 - lon1) * math.cos(lat3),
        math.cos(lat1) * math.sin(lat3) - math.sin(lat1) * math.cos(lat3) * math.cos(lon3 - lon1)
    )
    
    # Initial bearing from start to point
    theta12 = math.atan2(
        math.sin(lon2 - lon1) * math.cos(lat2),
        math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(lon2 - lon1)
    )
    
    # Cross-track distance
    dxt = math.asin(math.sin(d13) * math.sin(theta13 - theta12))
    
    return abs(dxt * R)


class MultiStopRoutePlanner:
    """
    Plans optimal multi-stop routes using A* algorithm with persona-aware cost function.
    
    The planner considers:
    1. Aircraft performance (max leg distance, fuel type, runway requirements)
    2. Persona preferences (airport quality scoring)
    3. Route efficiency (corridor-based filtering)
    4. Airport suitability (fuel, runway, operations)
    """
    
    def __init__(
        self,
        airports_db_path: Optional[str] = None,
        corridor_width_nm: float = 50.0,
    ):
        """
        Initialize the route planner.
        
        Args:
            airports_db_path: Path to airports database (uses default if None)
            corridor_width_nm: Max cross-track distance for candidate airports
        """
        self.corridor_width_nm = corridor_width_nm
        self._airports_db_path = airports_db_path
        self._airports_cache: Dict[str, Dict[str, Any]] = {}
    
    def find_route_candidates(
        self,
        from_lat: float,
        from_lon: float,
        to_lat: float,
        to_lon: float,
        max_leg_nm: float,
        min_progress_nm: float = 50.0,
    ) -> List[Dict[str, Any]]:
        """
        Find airports that are candidates for stops along a route.
        
        Args:
            from_lat, from_lon: Origin coordinates
            to_lat, to_lon: Destination coordinates
            max_leg_nm: Maximum leg distance in nm
            min_progress_nm: Minimum forward progress required
            
        Returns:
            List of airport candidates with distance info
        """
        # This would query the airports database
        # For now, return empty list - will be implemented with actual DB query
        logger.info(
            f"Finding candidates: max_leg={max_leg_nm}nm, "
            f"corridor={self.corridor_width_nm}nm"
        )
        return []
    
    def calculate_stop_cost(
        self,
        airport: Dict[str, Any],
        from_airport: Dict[str, Any],
        to_airport: Dict[str, Any],
        persona_weights: Optional[Dict[str, float]] = None,
        aircraft_requirements: Optional[Dict[str, Any]] = None,
    ) -> float:
        """
        Calculate the cost of using an airport as a stop.
        
        Lower cost = better choice.
        
        Cost components:
        1. Distance penalty (actual distance adds to cost)
        2. Stop time penalty (~30nm equivalent for time on ground)
        3. Persona score bonus (reduces cost for preferred airports)
        4. Fuel availability penalty (major if required fuel unavailable)
        5. Runway penalty (eliminates if runway too short)
        """
        # Base: distance from previous point
        dist = haversine_distance(
            from_airport.get("latitude_deg", 0),
            from_airport.get("longitude_deg", 0),
            airport.get("latitude_deg", 0),
            airport.get("longitude_deg", 0),
        )
        
        cost = dist  # Base distance cost
        
        # Stop time penalty (~30 minutes = ~30nm equivalent at 60kts)
        cost += 30.0
        
        # Persona score bonus (up to 50nm discount for score=1.0)
        persona_score = airport.get("persona_score", 0.5)
        cost -= persona_score * 50.0
        
        # Aircraft requirements checks
        if aircraft_requirements:
            # Fuel type check
            required_fuel = aircraft_requirements.get("fuel_type", "any")
            if required_fuel != "any":
                has_avgas = airport.get("has_avgas", False)
                has_jeta = airport.get("has_jeta", False)
                has_mogas = airport.get("has_mogas", False)
                
                if required_fuel == "avgas" and not has_avgas:
                    cost += 500  # Major penalty
                elif required_fuel == "jet_a" and not has_jeta:
                    cost += 500
                elif required_fuel == "mogas" and not has_mogas:
                    cost += 500
            
            # Runway length check
            min_runway = aircraft_requirements.get("min_runway_ft", 0)
            runway_length = airport.get("longest_runway_ft", 0)
            if runway_length and runway_length < min_runway:
                cost += 1000  # Effective elimination
        
        return max(cost, 0.0)  # Cost cannot be negative
    
    def plan_route(
        self,
        from_icao: str,
        to_icao: str,
        num_stops: Optional[int] = None,
        max_leg_nm: Optional[float] = None,
        first_leg_max_nm: Optional[float] = None,
        persona_id: Optional[str] = None,
        filters: Optional[Dict[str, Any]] = None,
    ) -> PlannedRoute:
        """
        Plan an optimal multi-stop route.
        
        Args:
            from_icao: Departure airport ICAO code
            to_icao: Destination airport ICAO code
            num_stops: Desired number of intermediate stops (None = auto)
            max_leg_nm: Maximum leg distance (None = use persona default)
            first_leg_max_nm: Override max for first leg only
            persona_id: Persona for scoring and aircraft performance
            filters: Additional airport filters
            
        Returns:
            PlannedRoute with optimal stop sequence
        """
        logger.info(
            f"Planning route: {from_icao} → {to_icao}, "
            f"stops={num_stops}, max_leg={max_leg_nm}nm"
        )
        
        # TODO: Implement A* search
        # For now, return a placeholder empty route
        return PlannedRoute(
            legs=[],
            stops=[],
            total_distance_nm=0.0,
            estimated_time_hrs=0.0,
            persona_score=0.0,
        )
    
    def find_first_stop_candidates(
        self,
        from_icao: str,
        to_icao: str,
        max_distance_nm: float,
        persona_id: Optional[str] = None,
        max_results: int = 5,
    ) -> List[Dict[str, Any]]:
        """
        Find candidate airports for the first stop within a distance constraint.
        
        This is used for the human-in-the-loop flow where the user specifies
        "first stop within 400nm" and we return options for them to choose.
        
        Args:
            from_icao: Departure airport
            to_icao: Ultimate destination (for "on the way" filtering)
            max_distance_nm: Maximum distance from departure
            persona_id: Persona for scoring
            max_results: Maximum number of candidates to return
            
        Returns:
            List of candidate airports ranked by persona score
        """
        logger.info(
            f"Finding first stop candidates: {from_icao} → {to_icao}, "
            f"max_dist={max_distance_nm}nm"
        )
        
        # TODO: Implement with actual database query
        # 1. Query airports within max_distance_nm of from_icao
        # 2. Filter to corridor toward to_icao
        # 3. Score with persona
        # 4. Return top candidates
        
        return []
