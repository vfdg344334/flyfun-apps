#!/usr/bin/env python3
"""
Shared Airport & Aviation Rules Tools
======================================

This module provides the core tool functions used by both the MCP server and
the internal aviation chatbot agent. Tools are organized into two main categories:

AIRPORT TOOLS (Section 5):
    - search_airports: Search by ICAO, name, city, or country
    - find_airports_near_location: Find airports near a geographic point
    - find_airports_near_route: Find airports along a flight route
    - get_airport_details: Get comprehensive airport information
    - get_notification_for_airport: Customs notification requirements

RULES TOOLS (Section 6):
    - answer_rules_question: Answer specific questions about rules for a country (RAG-based)
    - browse_rules: Browse/list rules by category and tags with pagination
    - compare_rules_between_countries: Compare rules between two or more countries

TOOL REGISTRY (Section 7):
    - get_shared_tool_specs(): Returns the tool manifest for registration

Usage:
    from shared.airport_tools import get_shared_tool_specs
    specs = get_shared_tool_specs()
"""
from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass
from typing import Any, Callable, Dict, Iterable, List, Optional, OrderedDict as OrderedDictType, TypedDict
import os
import urllib.parse
import json
import urllib.request

from euro_aip.models.airport import Airport
from euro_aip.models.navpoint import NavPoint

from .filtering import FilterEngine
from .prioritization import PriorityEngine
from .tool_context import ToolContext


# =============================================================================
# SECTION 2: TYPE DEFINITIONS
# =============================================================================

ToolCallable = Callable[..., Dict[str, Any]]


class ToolSpec(TypedDict):
    """Metadata describing a shared tool.

    Attributes:
        name: Tool identifier used for registration and invocation
        handler: The callable function that implements the tool
        description: Human-readable description (from config or docstring)
        parameters: JSON Schema defining the tool's parameters
        expose_to_llm: If True, tool is available to the aviation agent;
                       if False, tool is internal or MCP-only
    """
    name: str
    handler: ToolCallable
    description: str
    parameters: Dict[str, Any]
    expose_to_llm: bool


# =============================================================================
# SECTION 4: INTERNAL HELPERS
# =============================================================================

# -----------------------------------------------------------------------------
# Geocoding & Location Helpers
# -----------------------------------------------------------------------------

# European country codes for geocoding preference
EUROPEAN_COUNTRY_CODES = {
    "DE", "FR", "GB", "ES", "IT", "NL", "BE", "CH", "AT", "PL", "PT",
    "GR", "IE", "SE", "NO", "DK", "FI", "CZ", "HU", "HR", "SI", "SK",
    "RO", "BG", "TR", "MT", "LU", "IS", "EE", "LV", "LT", "CY", "RS",
    "AL", "ME", "MK", "BA", "GG", "JE", "IM", "FO", "MC", "AD", "LI",
}


def _geoapify_geocode(query: str) -> Optional[Dict[str, Any]]:
    """
    Forward-geocode a free-text location using Geoapify.

    Prefers European locations for ambiguous queries (e.g., "Bromley" returns UK, not USA).

    Args:
        query: Free-text location name (e.g., "Paris", "Lake Geneva")

    Returns:
        Dict with 'lat', 'lon', 'formatted', 'country_code' on success;
        None on failure or if GEOAPIFY_API_KEY is not set.
    """
    api_key = os.environ.get("GEOAPIFY_API_KEY")
    if not api_key:
        return None
    base_url = "https://api.geoapify.com/v1/geocode/search"
    params = {
        "text": query,
        "limit": 5,  # Get multiple results to find European match
        "format": "json",
        "apiKey": api_key,
    }
    url = f"{base_url}?{urllib.parse.urlencode(params)}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            payload = resp.read()
            data = json.loads(payload.decode("utf-8"))
            results = data.get("results") or []
            if not results:
                return None

            # Prefer European results for ambiguous queries like "Bromley"
            selected = None
            for result in results:
                country_code = (result.get("country_code") or "").upper()
                if country_code in EUROPEAN_COUNTRY_CODES:
                    selected = result
                    break

            # Fall back to first result if no European match
            if not selected:
                selected = results[0]

            lat = selected.get("lat")
            lon = selected.get("lon")
            if lat is None or lon is None:
                return None
            return {
                "lat": float(lat),
                "lon": float(lon),
                "formatted": selected.get("formatted") or query,
                "country_code": selected.get("country_code"),
            }
    except Exception:
        return None


def _find_nearest_airport_in_db(
    ctx: ToolContext,
    icao_or_location: str,
    max_search_radius_nm: float = 100.0
) -> Optional[Dict[str, Any]]:
    """
    Find the nearest airport in the database for a given ICAO code or location name.

    Resolution process:
    1. First checks if the input is an ICAO code in the database
    2. If not found, tries to geocode it as a location name
    3. Finds the nearest airport to those coordinates
       - Prefers airports in the same country as the geocoded location
       - Falls back to nearest airport if none in same country

    Args:
        ctx: Tool context with airport model
        icao_or_location: ICAO code or free-text location name
        max_search_radius_nm: Maximum search radius in nautical miles

    Returns:
        Dict with 'airport', 'original_query', 'was_geocoded', 'distance_nm',
        'geocoded_location'; or None if nothing found.
    """
    icao = icao_or_location.strip().upper()

    # First try direct ICAO lookup
    airport = ctx.model.airports.get(icao)
    if airport:
        return {
            "airport": airport,
            "original_query": icao_or_location,
            "was_geocoded": False,
            "distance_nm": 0.0,
            "geocoded_location": None
        }

    # Not found as ICAO - try geocoding as location name
    geocode = _geoapify_geocode(icao_or_location)

    if not geocode:
        return None

    center_point = NavPoint(latitude=geocode["lat"], longitude=geocode["lon"], name=geocode["formatted"])
    geocode_country = geocode.get("country_code")  # ISO-2 country code from Geoapify

    # Find airports within radius, tracking both same-country and any-country nearest
    nearest_same_country = None
    nearest_same_country_distance = float('inf')
    nearest_any = None
    nearest_any_distance = float('inf')

    for apt in ctx.model.airports:
        if not getattr(apt, "navpoint", None):
            continue
        try:
            _, distance_nm = apt.navpoint.haversine_distance(center_point)
        except Exception:
            continue

        if distance_nm > max_search_radius_nm:
            continue

        # Track nearest airport overall
        if distance_nm < nearest_any_distance:
            nearest_any_distance = distance_nm
            nearest_any = apt

        # Track nearest airport in same country (if country known)
        if geocode_country and getattr(apt, "iso_country", None):
            if apt.iso_country.upper() == geocode_country.upper():
                if distance_nm < nearest_same_country_distance:
                    nearest_same_country_distance = distance_nm
                    nearest_same_country = apt

    # Prefer same-country airport if found, otherwise use nearest any
    if nearest_same_country:
        return {
            "airport": nearest_same_country,
            "original_query": icao_or_location,
            "was_geocoded": True,
            "distance_nm": round(nearest_same_country_distance, 1),
            "geocoded_location": geocode["formatted"]
        }

    if nearest_any:
        return {
            "airport": nearest_any,
            "original_query": icao_or_location,
            "was_geocoded": True,
            "distance_nm": round(nearest_any_distance, 1),
            "geocoded_location": geocode["formatted"]
        }

    return None


# -----------------------------------------------------------------------------
# Airport Data Helpers
# -----------------------------------------------------------------------------

def _airport_summary(a: Airport) -> Dict[str, Any]:
    """Convert an Airport object to a summary dict for API responses."""
    return {
        "ident": a.ident,
        "name": a.name,
        "municipality": a.municipality,
        "country": a.iso_country,
        "iso_country": a.iso_country,  # Include both for compatibility
        "latitude_deg": getattr(a, "latitude_deg", None),
        "longitude_deg": getattr(a, "longitude_deg", None),
        "longest_runway_length_ft": getattr(a, "longest_runway_length_ft", None),
        "point_of_entry": bool(getattr(a, "point_of_entry", False)),
        "has_aip_data": bool(a.aip_entries) if hasattr(a, "aip_entries") else False,
        "has_procedures": bool(a.procedures),
        "has_hard_runway": bool(getattr(a, "has_hard_runway", False)),
    }


def _build_priority_context(
    base_context: Optional[Dict[str, Any]] = None,
    persona_id: Optional[str] = None
) -> Dict[str, Any]:
    """
    Build context dict for PriorityEngine.apply().

    Merges base_context (e.g., segment_distances) with persona_id if provided.
    """
    context = dict(base_context) if base_context else {}
    if persona_id:
        context["persona_id"] = persona_id
    return context


# -----------------------------------------------------------------------------
# Airport Filter & Sort Pipeline
# -----------------------------------------------------------------------------

@dataclass
class AirportFilterResult:
    """Result of filtering and sorting airports.

    Attributes:
        airports: Filtered and sorted list of Airport objects
        notification_infos: Dict mapping ICAO codes to NotificationInfo objects
    """
    airports: List[Airport]
    notification_infos: Dict[str, Any]


def _filter_and_sort_airports(
    ctx: ToolContext,
    airports: List[Airport],
    filters: Optional[Dict[str, Any]] = None,
    include_large_airports: bool = False,
    priority_strategy: str = "persona_optimized",
    priority_context_extra: Optional[Dict[str, Any]] = None,
    max_hours_notice: Optional[int] = None,
    max_results: int = 100,
    persona_id: Optional[str] = None,
) -> AirportFilterResult:
    """
    Common pipeline for airport tools: filter → notification filter → priority sort.

    This helper consolidates the repeated filtering and sorting logic used by
    all airport search tools.

    Args:
        ctx: Tool context with model and services
        airports: List of candidate airports to filter/sort
        filters: Optional dict of filter criteria (has_avgas, point_of_entry, etc.)
        include_large_airports: If False, excludes large commercial airports
        priority_strategy: Sorting strategy for PriorityEngine
        priority_context_extra: Additional context for priority sorting (e.g., distances)
        max_hours_notice: If set, filter to airports with <= this notification requirement
        max_results: Maximum number of airports to return
        persona_id: Optional persona ID for personalized sorting

    Returns:
        AirportFilterResult with sorted airports and notification info dict
    """
    # 1. Build effective filters (always exclude large airports unless explicitly included)
    effective_filters: Dict[str, Any] = {}
    if not include_large_airports:
        effective_filters["exclude_large_airports"] = True
    if filters:
        effective_filters.update(filters)

    # 2. Apply filters using FilterEngine
    if effective_filters:
        filter_engine = FilterEngine(context=ctx)
        airports = filter_engine.apply(airports, effective_filters)

    # 3. Fetch notification info for all candidate airports
    notification_infos: Dict[str, Any] = {}
    if ctx.notification_service and airports:
        candidate_icaos = [a.ident for a in airports]
        notification_infos = ctx.notification_service.get_notification_info_batch(candidate_icaos)

        # Filter by notification requirements if max_hours_notice is specified
        if max_hours_notice is not None and notification_infos:
            filtered_by_notification = []
            for airport in airports:
                info = notification_infos.get(airport.ident)
                if info and info.matches_criteria(max_hours_notice=max_hours_notice):
                    filtered_by_notification.append(airport)
                elif info is None:
                    # No notification data - include by default (unknown requirements)
                    filtered_by_notification.append(airport)
            airports = filtered_by_notification

    # 4. Apply priority sorting using PriorityEngine
    priority_engine = PriorityEngine(context=ctx)
    priority_context = _build_priority_context(
        base_context=priority_context_extra,
        persona_id=persona_id
    )
    sorted_airports = priority_engine.apply(
        airports,
        strategy=priority_strategy,
        context=priority_context,
        max_results=max_results
    )

    return AirportFilterResult(
        airports=sorted_airports,
        notification_infos=notification_infos
    )


def _build_filter_profile(
    base: Dict[str, Any],
    filters: Optional[Dict[str, Any]] = None,
    max_hours_notice: Optional[int] = None,
) -> Dict[str, Any]:
    """
    Build filter profile dict for UI synchronization.

    Args:
        base: Base profile dict (e.g., {"search_query": "Paris"})
        filters: Optional filters dict from tool call
        max_hours_notice: Optional notification filter

    Returns:
        Complete filter profile for UI sync
    """
    profile = dict(base)

    if max_hours_notice is not None:
        profile["max_hours_notice"] = max_hours_notice

    if not filters:
        return profile

    # Direct copy keys (values matter - strings or numbers, not booleans)
    for key in ["country", "max_runway_length_ft", "min_runway_length_ft", "max_landing_fee",
                "hotel", "restaurant"]:
        if filters.get(key):
            profile[key] = filters[key]

    # Boolean keys (just need to be truthy)
    for key in ["has_procedures", "has_aip_data", "has_hard_runway",
                "point_of_entry", "has_avgas", "has_jet_a"]:
        if filters.get(key):
            profile[key] = True

    return profile


# -----------------------------------------------------------------------------
# Tool Description Helpers
# -----------------------------------------------------------------------------

def _tool_description(func: Callable) -> str:
    """Get tool description from docstring (legacy function, kept for compatibility)."""
    return (func.__doc__ or "").strip()


def _get_tool_description(func: Callable, tool_name: str) -> str:
    """Get tool description from config file, falling back to docstring.

    Args:
        func: The tool function (for docstring fallback)
        tool_name: Name of the tool for config lookup

    Returns:
        Tool description text from config file, or docstring if not configured.
    """
    # Lazy import to avoid circular dependency (config imports airport_tools)
    try:
        from shared.aviation_agent.config import get_behavior_config, get_settings
        settings = get_settings()
        config = get_behavior_config(settings.agent_config_name or "default")

        # Try to load from config
        if config:
            description = config.load_tool_description(tool_name)
            if description:
                return description
    except Exception:
        # If config loading fails, fall back to docstring
        pass

    # Fallback to docstring
    return (func.__doc__ or "").strip()


# =============================================================================
# SECTION 5: AIRPORT TOOLS
# =============================================================================

# -----------------------------------------------------------------------------
# Search & Discovery
# -----------------------------------------------------------------------------

def search_airports(
    ctx: ToolContext,
    query: str,
    max_results: int = 5,
    filters: Optional[Dict[str, Any]] = None,
    include_large_airports: bool = False,
    priority_strategy: str = "persona_optimized",
    **kwargs: Any,  # Accept _persona_id injected by ToolRunner
) -> Dict[str, Any]:
    """
    Search for airports by ICAO code, IATA code, airport name, or city name with optional filters (country, procedures, runway, fuel, fees).

    **USE THIS TOOL for direct name/code searches**, not for proximity searches.

    Examples:
    - "LFPG" → use this tool (ICAO code search)
    - "Charles de Gaulle" → use this tool (airport name search)
    - "Paris airports" → use this tool (searches airports with "Paris" in name/city)
    - "CDG" → use this tool (IATA code search)

    **DO NOT use this tool for "near" queries** - use find_airports_near_location instead for proximity searches.

    **By default, large commercial airports are excluded** (not suitable for GA).
    Set include_large_airports=True only if user explicitly asks for large/commercial airports.

    Returns matching airports sorted by priority.
    """
    q = query.upper().strip()
    matches: List[Airport] = []

    # Check if query contains multiple ICAO codes (space-separated 4-letter codes)
    # Filter out common conjunctions like "and", "or", commas
    parts = [p.strip(",") for p in q.split() if p.upper() not in ("AND", "OR", "&", ",")]
    if len(parts) > 1 and all(len(p) == 4 and p.isalpha() for p in parts):
        # Multiple ICAO codes - search for each
        icao_set = set(parts)
        for a in ctx.model.airports:
            if a.ident in icao_set:
                matches.append(a)
                if len(matches) >= len(icao_set):
                    break  # Found all requested airports

        # Skip country detection and standard search
        # Filter and sort using common pipeline
        persona_id = kwargs.pop("_persona_id", None)
        result = _filter_and_sort_airports(
            ctx=ctx,
            airports=matches,
            filters=filters,
            include_large_airports=True,  # Don't filter out large airports when explicitly requested
            priority_strategy=priority_strategy,
            max_results=max(max_results, len(icao_set)),  # Return at least as many as requested
            persona_id=persona_id,
        )

        airport_summaries = [_airport_summary(a) for a in result.airports]
        filter_profile = _build_filter_profile({"search_query": query}, filters)

        return {
            "count": len(airport_summaries),
            "airports": airport_summaries,
            "filter_profile": filter_profile,
            "visualization": {
                "type": "markers",
                "data": airport_summaries
            }
        }

    # Country name to ISO-2 code mapping for common country searches
    country_name_map = {
        "GERMANY": "DE", "FRANCE": "FR", "UNITED KINGDOM": "GB", "UK": "GB",
        "SPAIN": "ES", "ITALY": "IT", "NETHERLANDS": "NL", "BELGIUM": "BE",
        "SWITZERLAND": "CH", "AUSTRIA": "AT", "POLAND": "PL", "PORTUGAL": "PT",
        "GREECE": "GR", "IRELAND": "IE", "SWEDEN": "SE", "NORWAY": "NO",
        "DENMARK": "DK", "FINLAND": "FI", "CZECH REPUBLIC": "CZ", "CZECHIA": "CZ",
        "HUNGARY": "HU", "CROATIA": "HR", "SLOVENIA": "SI", "SLOVAKIA": "SK",
        "ROMANIA": "RO", "BULGARIA": "BG", "TURKEY": "TR", "MALTA": "MT",
        "LUXEMBOURG": "LU", "ICELAND": "IS", "ESTONIA": "EE", "LATVIA": "LV",
        "LITHUANIA": "LT", "CYPRUS": "CY", "SERBIA": "RS", "ALBANIA": "AL",
        "MONTENEGRO": "ME", "NORTH MACEDONIA": "MK", "BOSNIA": "BA",
        "GUERNSEY": "GG", "JERSEY": "JE",
    }

    # Check if query is a country name
    country_code = country_name_map.get(q)
    detected_country = None  # Track if we detected a country for filter_profile

    if country_code:
        # Search by country code
        detected_country = country_code
        for a in ctx.model.airports:
            if (a.iso_country or "").upper() == country_code:
                matches.append(a)
                if len(matches) >= 200:
                    break
    else:
        # Standard search: ICAO, name, IATA, municipality, or ISO country
        for a in ctx.model.airports:
            if (
                (q in a.ident)
                or (a.name and q in a.name.upper())
                or (getattr(a, "iata_code", None) and q in a.iata_code)
                or (a.municipality and q in a.municipality.upper())
                or ((a.iso_country or "").upper() == q)  # Also check ISO country code
            ):
                matches.append(a)
                if len(matches) >= 200:  # Get more candidates before filtering
                    break

    # Filter and sort using common pipeline
    persona_id = kwargs.pop("_persona_id", None)
    result = _filter_and_sort_airports(
        ctx=ctx,
        airports=matches,
        filters=filters,
        include_large_airports=include_large_airports,
        priority_strategy=priority_strategy,
        max_results=max_results,
        persona_id=persona_id,
    )

    # Convert to summaries
    airport_summaries = [_airport_summary(a) for a in result.airports]

    # Generate filter profile for UI synchronization
    # Include detected country so UI can sync the country filter dropdown
    base_profile: Dict[str, Any] = {"search_query": query}
    if detected_country:
        base_profile["country"] = detected_country
    filter_profile = _build_filter_profile(base_profile, filters)

    return {
        "count": len(airport_summaries),
        "airports": airport_summaries[:max_results],  # Limited for LLM
        "filter_profile": filter_profile,
        "visualization": {
            "type": "markers",
            "data": airport_summaries  # Show ALL matching airports on map
        }
    }


def find_airports_near_location(
    ctx: ToolContext,
    location_query: str,
    max_distance_nm: float = 50.0,
    max_results: int = 5,
    filters: Optional[Dict[str, Any]] = None,
    include_large_airports: bool = False,
    priority_strategy: str = "persona_optimized",
    max_hours_notice: Optional[int] = None,  # Filter by notification requirements
    # Optional pre-resolved center (bypasses geocoding) - used by REST API
    center_lat: Optional[float] = None,
    center_lon: Optional[float] = None,
    **kwargs: Any,  # Accept _persona_id injected by ToolRunner
) -> Dict[str, Any]:
    """
    Find airports near a geographic location (ICAO code, free-text location name, city, landmark, or coordinates) within a specified distance.

    **USE THIS TOOL when user asks about airports "near", "around", "close to" a location.**

    Examples:
    - "airports near EGTF" → use this tool with location_query="EGTF"
    - "airports near Paris" → use this tool with location_query="Paris"
    - "airports around Lake Geneva" → use this tool with location_query="Lake Geneva"
    - "airports close to Zurich" → use this tool with location_query="Zurich"
    - "airports near 48.8584, 2.2945" → use this tool with location_query="48.8584, 2.2945"
    - "airports near Vannes with less than 24h notice" → use with max_hours_notice=24

    Process:
    1) If location_query is an ICAO code, uses that airport's coordinates as center
    2) Otherwise geocodes the location via Geoapify (or uses pre-resolved center if provided)
    3) Computes distance from each airport to that point and filters by max_distance_nm
    4) Applies optional filters (fuel, customs, runway, etc.) and priority sorting
    5) If max_hours_notice is set, filters to airports requiring at most that many hours notice

    **By default, large commercial airports are excluded** (not suitable for GA).
    Set include_large_airports=True only if user explicitly asks for large/commercial airports.
    """
    # Use pre-resolved center if provided, otherwise try ICAO lookup then geocode
    if center_lat is not None and center_lon is not None:
        geocode = {
            "lat": center_lat,
            "lon": center_lon,
            "formatted": location_query or "Center"
        }
    else:
        # First try direct ICAO lookup (handles "airports near EGTF" queries)
        icao = location_query.strip().upper()
        airport = ctx.model.airports.get(icao)
        if airport and hasattr(airport, 'navpoint') and airport.navpoint:
            geocode = {
                "lat": airport.navpoint.latitude,
                "lon": airport.navpoint.longitude,
                "formatted": f"{airport.name} ({icao})"
            }
        else:
            # Not found as ICAO - try geocoding as location name
            geocode = _geoapify_geocode(location_query)
            if not geocode:
                return {
                    "found": False,
                    "pretty": f"Could not geocode '{location_query}'. Ensure GEOAPIFY_API_KEY is set and the query is valid."
                }

    center_point = NavPoint(latitude=geocode["lat"], longitude=geocode["lon"], name=geocode["formatted"])

    # Compute distances to all airports and filter by radius
    candidate_airports: List[Airport] = []
    point_distances: Dict[str, float] = {}
    for airport in ctx.model.airports:
        if not getattr(airport, "navpoint", None):
            continue
        try:
            _, distance_nm = airport.navpoint.haversine_distance(center_point)
        except Exception:
            continue
        if distance_nm <= float(max_distance_nm):
            candidate_airports.append(airport)
            point_distances[airport.ident] = float(distance_nm)

    # Filter and sort using common pipeline
    persona_id = kwargs.pop("_persona_id", None)
    result = _filter_and_sort_airports(
        ctx=ctx,
        airports=candidate_airports,
        filters=filters,
        include_large_airports=include_large_airports,
        priority_strategy=priority_strategy,
        priority_context_extra={"point_distances": point_distances},
        max_hours_notice=max_hours_notice,
        max_results=100,
        persona_id=persona_id,
    )

    # Build summaries with distance and notification info
    airports: List[Dict[str, Any]] = []
    for a in result.airports:
        summary = _airport_summary(a)
        summary["distance_nm"] = round(point_distances.get(a.ident, 0.0), 2)
        if a.ident in result.notification_infos:
            summary["notification"] = result.notification_infos[a.ident].to_summary_dict()
        airports.append(summary)

    total_count = len(airports)
    airports_for_llm = airports[:max_results]

    # Generate filter profile for UI synchronization
    filter_profile = _build_filter_profile(
        {"location_query": location_query, "radius_nm": max_distance_nm},
        filters,
        max_hours_notice,
    )

    return {
        "found": True,
        "count": total_count,
        "center": {"lat": geocode["lat"], "lon": geocode["lon"], "label": geocode["formatted"]},
        "airports": airports_for_llm,  # Limited for LLM
        "filter_profile": filter_profile,
        "visualization": {
            "type": "point_with_markers",
            "point": {
                "label": geocode["formatted"],
                "lat": geocode["lat"],
                "lon": geocode["lon"],
            },
            "markers": airports_for_llm,  # Only recommended airports for highlighting
            "radius_nm": max_distance_nm  # For UI to trigger search with same radius
        }
    }


def find_airports_near_route(
    ctx: ToolContext,
    from_location: str,
    to_location: str,
    max_distance_nm: float = 50.0,
    max_results: int = 5,
    filters: Optional[Dict[str, Any]] = None,
    include_large_airports: bool = False,
    priority_strategy: str = "persona_optimized",
    max_hours_notice: Optional[int] = None,  # Filter by notification requirements
    **kwargs: Any,  # Accept _persona_id injected by ToolRunner
) -> Dict[str, Any]:
    """
    List airports within a specified distance from a direct route between two locations, with optional airport filters.

    **USE THIS TOOL when user asks about airports "between" two locations.**

    **IMPORTANT - Pass location names exactly as user provides them, INCLUDING country/region context:**
    - Pass ICAO codes as-is (e.g., "LFPO", "EGKB", "EDDM")
    - Pass location names WITH COUNTRY if user mentions it - DO NOT strip country context
    - The tool will automatically geocode location names and find the nearest airport
    - Examples:
      - "between LFPO and Bromley" → from_location="LFPO", to_location="Bromley"
      - "between Paris and Vik in Iceland" → from_location="Paris", to_location="Vik, Iceland"
      - "Vik, Iceland" or "Vik in Iceland" → to_location="Vik, Iceland" (INCLUDE COUNTRY!)
      - "between LFPO and EDDM" → from_location="LFPO", to_location="EDDM"
      - "border entry between EGTF and LFMD with less than 24h notice" → use with point_of_entry=True, max_hours_notice=24

    **Filters:**
    When user mentions fuel (e.g., AVGAS, Jet-A), customs/border crossing, runway type (paved/hard), IFR procedures, country, or notification requirements, you MUST include the corresponding filter:
    - has_avgas=True for AVGAS
    - has_jet_a=True for Jet-A
    - point_of_entry=True for customs
    - has_hard_runway=True for paved runways
    - has_procedures=True for IFR
    - country='XX' for specific country
    - max_hours_notice=24 for airports with <24h notification (or 48 for <48h, etc.)

    **By default, large commercial airports are excluded** (not suitable for GA).
    Set include_large_airports=True only if user explicitly asks for large/commercial airports.

    Useful for finding fuel stops, alternates, or customs stops along a route.
    """
    # Try to resolve both locations (with fallback to nearest airport via geocoding)
    from_result = _find_nearest_airport_in_db(ctx, from_location)
    to_result = _find_nearest_airport_in_db(ctx, to_location)

    if not from_result:
        return {
            "found": False,
            "error": f"Could not find or geocode departure location '{from_location}'. Please verify the ICAO code or location name.",
            "pretty": f"Could not find airport or location '{from_location}'."
        }

    if not to_result:
        return {
            "found": False,
            "error": f"Could not find or geocode destination location '{to_location}'. Please verify the ICAO code or location name.",
            "pretty": f"Could not find airport or location '{to_location}'."
        }

    from_airport = from_result["airport"]
    to_airport = to_result["airport"]

    # Build substitution notes if geocoding was used
    substitution_notes = []
    if from_result["was_geocoded"]:
        substitution_notes.append(
            f"Note: '{from_result['original_query']}' was geocoded to {from_result['geocoded_location']}. "
            f"Using nearest airport {from_airport.ident} ({from_airport.name}), {from_result['distance_nm']}nm away."
        )
    if to_result["was_geocoded"]:
        substitution_notes.append(
            f"Note: '{to_result['original_query']}' was geocoded to {to_result['geocoded_location']}. "
            f"Using nearest airport {to_airport.ident} ({to_airport.name}), {to_result['distance_nm']}nm away."
        )

    results = ctx.model.find_airports_near_route(
        [from_airport.ident, to_airport.ident],
        max_distance_nm
    )

    # Calculate total route distance for position-based sorting
    total_route_distance_nm = 0.0
    if hasattr(from_airport, 'navpoint') and hasattr(to_airport, 'navpoint'):
        try:
            _, total_route_distance_nm = from_airport.navpoint.haversine_distance(to_airport.navpoint)
        except Exception:
            pass  # Keep as 0.0 if calculation fails

    # Extract airports and build distance map for context
    airport_objects = [item["airport"] for item in results]
    segment_distances = {
        item["airport"].ident: float(item.get("segment_distance_nm") or 0.0) for item in results
    }
    enroute_distances = {
        item["airport"].ident: item.get("enroute_distance_nm")
        for item in results
        if item.get("enroute_distance_nm") is not None
    }

    # Filter and sort using common pipeline
    persona_id = kwargs.pop("_persona_id", None)
    result = _filter_and_sort_airports(
        ctx=ctx,
        airports=airport_objects,
        filters=filters,
        include_large_airports=include_large_airports,
        priority_strategy=priority_strategy,
        priority_context_extra={
            "segment_distances": segment_distances,
            "enroute_distances": enroute_distances,
            "total_route_distance_nm": total_route_distance_nm,
            "sort_by": "halfway",  # Prioritize airports near middle of route
        },
        max_hours_notice=max_hours_notice,
        max_results=100,
        persona_id=persona_id,
    )

    # Build summaries with distance and notification info
    airports: List[Dict[str, Any]] = []
    for airport in result.airports:
        summary = _airport_summary(airport)
        summary["segment_distance_nm"] = segment_distances.get(airport.ident, 0.0)
        if airport.ident in enroute_distances:
            summary["enroute_distance_nm"] = enroute_distances[airport.ident]
        if airport.ident in result.notification_infos:
            summary["notification"] = result.notification_infos[airport.ident].to_summary_dict()
        airports.append(summary)

    total_count = len(airports)
    airports_for_llm = airports[:max_results]

    # Generate filter profile for UI synchronization
    filter_profile = _build_filter_profile(
        {"route_distance": max_distance_nm},
        filters,
        max_hours_notice,
    )

    return {
        "count": total_count,
        "airports": airports_for_llm,  # Limited for LLM
        "filter_profile": filter_profile,  # Filter settings for UI sync
        "substitutions": {
            "from": {
                "original": from_location,
                "resolved": from_airport.ident,
                "was_geocoded": from_result["was_geocoded"],
                "geocoded_location": from_result.get("geocoded_location"),
                "distance_nm": from_result.get("distance_nm", 0.0)
            } if from_result["was_geocoded"] else None,
            "to": {
                "original": to_location,
                "resolved": to_airport.ident,
                "was_geocoded": to_result["was_geocoded"],
                "geocoded_location": to_result.get("geocoded_location"),
                "distance_nm": to_result.get("distance_nm", 0.0)
            } if to_result["was_geocoded"] else None,
        },
        "visualization": {
            "type": "route_with_markers",
            "route": {
                "from": {
                    "icao": from_airport.ident,
                    "name": from_airport.name,
                    "municipality": from_airport.municipality,
                    "lat": getattr(from_airport, "latitude_deg", None),
                    "lon": getattr(from_airport, "longitude_deg", None),
                },
                "to": {
                    "icao": to_airport.ident,
                    "name": to_airport.name,
                    "municipality": to_airport.municipality,
                    "lat": getattr(to_airport, "latitude_deg", None),
                    "lon": getattr(to_airport, "longitude_deg", None),
                }
            },
            "markers": airports_for_llm,  # Only recommended airports for highlighting
            "radius_nm": max_distance_nm  # For UI to trigger search with same radius
        }
    }


def get_airport_details(
    ctx: ToolContext,
    icao_code: str,
    **kwargs: Any,  # Accept _persona_id injected by ToolRunner (not used by this tool)
) -> Dict[str, Any]:
    """Get comprehensive details about a specific airport including runways, procedures, facilities, and AIP information."""
    # Extract and ignore _persona_id (injected by ToolRunner, not used by this tool)
    kwargs.pop("_persona_id", None)

    icao = icao_code.strip().upper()
    a = ctx.model.airports.get(icao)

    if not a:
        return {"found": False, "pretty": f"Airport {icao} not found."}

    standardized = []
    for e in (a.get_standardized_entries() or []):
        if getattr(e, "std_field", None) and getattr(e, "value", None):
            standardized.append({
                "field": e.std_field,
                "value": e.value
            })

    runways = []
    for r in a.runways:
        runways.append({
            "le_ident": r.le_ident,
            "he_ident": r.he_ident,
            "length_ft": r.length_ft,
            "width_ft": r.width_ft,
            "surface": r.surface,
            "lighted": bool(getattr(r, "lighted", False)),
        })

    return {
        "found": True,
        "airport": _airport_summary(a),
        "runways": runways,
        "runway_summary": {
            "count": len(a.runways),
            "longest_ft": getattr(a, "longest_runway_length_ft", None),
            "has_hard_surface": bool(getattr(a, "has_hard_runway", False)),
        },
        "procedures": {"count": len(a.procedures)},
        "aip_data": standardized,
        "visualization": {
            "type": "marker_with_details",
            "marker": {
                "ident": a.ident,
                "lat": getattr(a, "latitude_deg", None),
                "lon": getattr(a, "longitude_deg", None),
                "zoom": 12
            }
        }
    }

# -----------------------------------------------------------------------------
# Multi-Stop Route Planning
# -----------------------------------------------------------------------------
def _find_best_stop_in_range(
    ctx: ToolContext,
    from_airport,
    to_airport,
    max_distance_nm: float,
    corridor_width: float = 150.0,
    excluded_icaos: Optional[List[str]] = None,
    persona_id: Optional[str] = None,
    require_fuel: bool = False,
) -> Optional[Dict[str, Any]]:
    """
    Find the best stop within max_distance_nm from from_airport toward to_airport.
    
    Uses the cost function from design document:
    cost = distance - progress_score - persona_score*50 + fuel_penalty*500 + runway_penalty*1000
    
    Lower cost = better airport for stop.
    
    Args:
        require_fuel: If True, airports without required fuel type get -500 penalty (effectively eliminated).
                     If False, airports without fuel get -50 soft penalty (can still be selected).
    """
    from shared.route_planner import haversine_distance, cross_track_distance
    
    excluded_icaos = excluded_icaos or []
    from_lat, from_lon = from_airport.latitude_deg, from_airport.longitude_deg
    to_lat, to_lon = to_airport.latitude_deg, to_airport.longitude_deg
    
    total_dist = haversine_distance(from_lat, from_lon, to_lat, to_lon)
    
    # Get persona requirements if available
    min_runway_ft = 1500  # Default
    fuel_type_required = None
    if persona_id:
        try:
            from shared.ga_friendliness.config import get_default_personas
            personas = get_default_personas()
            if persona_id in personas.personas:
                persona = personas.personas[persona_id]
                if persona.aircraft:
                    min_runway_ft = persona.aircraft.min_runway_ft
                    fuel_type_required = persona.aircraft.fuel_type
        except Exception:
            pass
    
    best_candidate = None
    best_score = float('-inf')  # Higher is better (we negate cost)
    
    for airport in ctx.model.airports:
        if airport.ident in excluded_icaos or airport.ident in (from_airport.ident, to_airport.ident):
            continue
        if airport.latitude_deg is None or airport.longitude_deg is None:
            continue
        
        dist_from = haversine_distance(from_lat, from_lon, airport.latitude_deg, airport.longitude_deg)
        if dist_from > max_distance_nm or dist_from < 30:  # Min 30nm
            continue
        
        xtd = cross_track_distance(airport.latitude_deg, airport.longitude_deg, from_lat, from_lon, to_lat, to_lon)
        if xtd > corridor_width:
            continue
        
        dist_to_dest = haversine_distance(airport.latitude_deg, airport.longitude_deg, to_lat, to_lon)
        progress = total_dist - dist_to_dest
        
        if progress < 50:
            continue
        
        # ============================================
        # COST FUNCTION FROM DESIGN DOCUMENT
        # ============================================
        # cost = distance - progress - persona_score*50 + fuel_penalty*500 + runway_penalty*1000
        # We maximize: score = progress + persona_score*50 - fuel_penalty*500 - runway_penalty*1000
        
        score = progress  # Base: progress toward destination
        reasons = [f"Leg: {round(dist_from)}nm, remaining: {round(dist_to_dest)}nm to {to_airport.ident}"]
        
        # --- Runway Assessment ---
        runway_length = getattr(airport, "longest_runway_length_ft", 0) or 0
        has_hard_runway = getattr(airport, "has_hard_runway", False)
        
        if runway_length < min_runway_ft:
            # Runway too short - major penalty (effectively eliminates)
            score -= 1000
            reasons.append(f"⚠️ Runway too short: {round(runway_length)}ft < required {min_runway_ft}ft")
        else:
            # Runway adequate
            runway_margin = runway_length - min_runway_ft
            runway_bonus = min(runway_margin / 100, 20)  # Up to +20 for long runway
            score += runway_bonus
            reasons.append(f"✓ Runway: {round(runway_length)}ft")
        
        if has_hard_runway:
            score += 15
            reasons.append("✓ Hard surface")
        
        # --- Fuel Assessment ---
        has_avgas = getattr(airport, "has_avgas", False)
        has_jeta = getattr(airport, "has_jeta", False)
        has_any_fuel = has_avgas or has_jeta
        
        # When require_fuel=True, SKIP airports without fuel entirely
        if require_fuel and not has_any_fuel:
            continue  # Skip this airport - must have fuel
        
        fuel_match = False
        if fuel_type_required:
            if fuel_type_required.lower() == "avgas" and has_avgas:
                fuel_match = True
                score += 30
                reasons.append("✓ AVGAS available")
            elif fuel_type_required.lower() == "jet-a" and has_jeta:
                fuel_match = True
                score += 30
                reasons.append("✓ JET-A available")
            elif has_any_fuel:
                # Has some fuel but not the required type - skip if require_fuel
                if require_fuel:
                    continue  # Skip - wrong fuel type
                score -= 20
                reasons.append(f"⚠️ No {fuel_type_required} (has {'AVGAS' if has_avgas else 'JET-A'})")
            else:
                # No fuel - soft penalty (we already skipped if require_fuel)
                score -= 50
                reasons.append("⚠️ No fuel available")
        else:
            # No specific fuel type required
            if has_avgas:
                score += 30 if require_fuel else 20
                reasons.append("✓ AVGAS available")
            elif has_jeta:
                score += 25 if require_fuel else 15
                reasons.append("✓ JET-A available")
            elif not require_fuel:
                # Only penalize if fuel not required (otherwise we already skipped)
                score -= 50
                reasons.append("⚠️ No fuel available")
        
        # --- Cross-Track Distance (detour penalty) ---
        if xtd > 0:
            detour_penalty = xtd * 0.5  # 0.5 points per nm off course
            score -= detour_penalty
            if xtd > 30:
                reasons.append(f"Detour: {round(xtd)}nm off direct route")
        
        # --- Final Score Check ---
        if score > best_score:
            best_score = score
            best_candidate = {
                "airport": airport,
                "distance_from_prev_nm": round(dist_from, 1),
                "distance_to_dest_nm": round(dist_to_dest, 1),
                "cross_track_nm": round(xtd, 1),
                "score": round(score, 1),
                "reasons": reasons,
            }
    
    return best_candidate


def _auto_plan_all_stops(
    ctx: ToolContext,
    from_airport,
    to_airport,
    num_stops: int,
    max_leg_nm: float,
    persona_id: Optional[str] = None,
    require_fuel: bool = False,
) -> List[Dict[str, Any]]:
    """Find all stops using greedy algorithm with full cost function."""
    stops = []
    current = from_airport
    excluded = [from_airport.ident, to_airport.ident]
    
    from shared.route_planner import haversine_distance
    
    for i in range(num_stops):
        remaining_dist = haversine_distance(
            current.latitude_deg, current.longitude_deg,
            to_airport.latitude_deg, to_airport.longitude_deg
        )
        
        # If close enough to destination, stop adding stops
        if remaining_dist < max_leg_nm * 0.7:
            break
        
        best = _find_best_stop_in_range(
            ctx, current, to_airport, max_leg_nm, 
            excluded_icaos=excluded, persona_id=persona_id, require_fuel=require_fuel
        )
        
        if not best:
            break
        
        stops.append(best)
        excluded.append(best["airport"].ident)
        current = best["airport"]
    
    return stops


def plan_multi_leg_route(
    ctx: ToolContext,
    from_location: str,
    to_location: str,
    num_stops: Optional[int] = None,
    max_leg_distance_nm: Optional[float] = None,
    first_leg_max_nm: Optional[float] = None,
    selected_stop: Optional[str] = None,
    auto_plan: Optional[bool] = None,
    require_fuel: Optional[bool] = None,
    confirmed_stops_count: int = 0,  # Track which stop number we're on
    continuation_token: Optional[str] = None,  # Server-side state token for reliable multi-turn tracking
    filters: Optional[Dict[str, Any]] = None,
    **kwargs: Any,
) -> Dict[str, Any]:
    """
    Plan a multi-stop route between two locations with intermediate fuel/rest stops.

    **USE THIS TOOL when user asks for:**
    - "Route from A to B with 3 stops"
    - "Plan a route with fuel stops"
    - "First stop within 400nm"
    - Multi-leg journey planning
    - User selects a stop by ICAO code (e.g., "LFSD" or "I choose LFSD")

    **Parameters:**
    - num_stops: Desired number of intermediate stops (None = auto-calculate based on distance and persona range)
    - max_leg_distance_nm: Maximum distance per leg (uses persona's aircraft range if not specified)
    - first_leg_max_nm: Override max distance for the first leg only (e.g., "first stop within 400nm")
    - selected_stop: ICAO code of a stop the user selected from candidates. When provided, 
      the tool continues planning from that stop to find the next leg.

    **Multi-turn flow:**
    1. User: "Route EGKL to LFKO with 3 stops" → returns choice: Automatic or Manual
    2. User: "first stop within 200nm" → returns 5 candidates
    3. User: "LFFZ" → call with selected_stop="LFFZ" to continue from that airport

    **Examples:**
    - "Route EGKL to LFKO with 3 stops" → num_stops=3
    - "First stop within 400nm" → first_leg_max_nm=400
    - "LFSD" (selecting from candidates) → selected_stop="LFSD"
    - "I'll stop at LFBL" → selected_stop="LFBL"
    """
    # DEBUG: Log all parameters received - use stderr and logging
    import sys
    import logging
    import base64
    import json as json_module
    logger = logging.getLogger(__name__)
    debug_msg = f"[plan_multi_leg_route] from={from_location}, to={to_location}, num_stops={num_stops}, auto_plan={auto_plan}, selected_stop={selected_stop}"
    print(debug_msg, file=sys.stderr)
    logger.info(debug_msg)
    
    # ========== SERVER-SIDE ROUTE STATE STORAGE ==========
    # Use server-side storage keyed by thread_id for reliable state tracking
    # This is more reliable than continuation_token which depends on LLM passing it correctly
    from shared.route_state import get_route_state_storage
    
    # Extract thread_id from kwargs (injected by ToolRunner)
    thread_id = kwargs.pop("_thread_id", None)
    logger.info(f"[plan_multi_leg_route] thread_id={thread_id}")
    
    # Get or create route state from server-side storage
    route_state_storage = get_route_state_storage()
    route_state = route_state_storage.get(thread_id) if thread_id else None
    
    # If we have a route state and it matches this route, use it
    if route_state:
        logger.info(f"[plan_multi_leg_route] Found existing route state: {route_state.to_dict()}")
        original_num_stops = route_state.original_num_stops
        confirmed_stops_list = route_state.confirmed_stops.copy()
        confirmed_stops_count = route_state.confirmed_stops_count
        original_departure_icao = route_state.original_departure
        # Ignore LLM-passed num_stops and use remaining from state
        num_stops = route_state.remaining_stops
    else:
        # No existing state - this is a new route request or continuation token fallback
        original_num_stops = num_stops  # Track original request
        confirmed_stops_list = []
        original_departure_icao = None
        
        # Try continuation_token as fallback (for backward compatibility)
        if continuation_token:
            try:
                token_data = json_module.loads(base64.b64decode(continuation_token).decode('utf-8'))
                original_num_stops = token_data.get("original_num_stops", num_stops)
                confirmed_stops_count = token_data.get("confirmed_stops_count", confirmed_stops_count)
                confirmed_stops_list = token_data.get("confirmed_stops", [])
                original_departure_icao = token_data.get("original_departure")
                remaining_from_token = original_num_stops - confirmed_stops_count
                if num_stops is None or num_stops > remaining_from_token:
                    num_stops = remaining_from_token
                logger.info(f"[continuation_token] Decoded: original={original_num_stops}, confirmed={confirmed_stops_count}, stops={confirmed_stops_list}, departure={original_departure_icao}")
            except Exception as e:
                logger.warning(f"Failed to decode continuation_token: {e}")
    
    def _create_continuation_token(orig_stops: int, confirmed: int, confirmed_stops: list = None, original_departure: str = None) -> str:
        """Create a base64-encoded continuation token with full route state."""
        token_data = {
            "original_num_stops": orig_stops, 
            "confirmed_stops_count": confirmed,
            "confirmed_stops": confirmed_stops or [],
            "original_departure": original_departure
        }
        return base64.b64encode(json_module.dumps(token_data).encode('utf-8')).decode('ascii')
    
    def _save_route_state(departure: str, destination: str, original_stops: int, confirmed: list = None):
        """Save or update route state in server-side storage."""
        if not thread_id:
            return
        existing = route_state_storage.get(thread_id)
        if existing:
            # Update confirmed stops
            if confirmed:
                for stop in confirmed:
                    if stop not in existing.confirmed_stops:
                        existing.confirm_stop(stop)
        else:
            # Create new state
            state = route_state_storage.create(thread_id, departure, destination, original_stops)
            if confirmed:
                for stop in confirmed:
                    state.confirm_stop(stop)
    
    # Extract persona_id from kwargs (injected by ToolRunner)
    persona_id = kwargs.pop("_persona_id", None)

    # Resolve departure and destination
    from_result = _find_nearest_airport_in_db(ctx, from_location)
    to_result = _find_nearest_airport_in_db(ctx, to_location)

    if not from_result:
        return {
            "found": False,
            "error": f"Could not find departure location '{from_location}'.",
            "pretty": f"Could not find airport or location '{from_location}'."
        }

    if not to_result:
        return {
            "found": False,
            "error": f"Could not find destination location '{to_location}'.",
            "pretty": f"Could not find airport or location '{to_location}'."
        }

    from_airport = from_result["airport"]
    to_airport = to_result["airport"]

    # If a stop was selected, continue planning from that stop
    if selected_stop:
        selected_result = _find_nearest_airport_in_db(ctx, selected_stop)
        if not selected_result:
            return {
                "found": False,
                "error": f"Could not find selected stop '{selected_stop}'.",
                "pretty": f"Could not find airport '{selected_stop}'. Please select from the list or provide a valid ICAO code."
            }
        
        # The selected stop becomes the new departure point
        selected_airport = selected_result["airport"]
        
        # Save stop to server-side storage immediately
        # This ensures state is preserved even if LLM doesn't pass token correctly
        if thread_id:
            if not route_state:
                # Create new route state if not exists
                route_state = route_state_storage.create(
                    thread_id, 
                    original_departure_icao or from_airport.ident, 
                    to_airport.ident, 
                    original_num_stops
                )
            route_state_storage.confirm_stop(thread_id, selected_airport.ident)
            logger.info(f"[plan_multi_leg_route] Saved stop {selected_airport.ident} to server state")
        
        # Calculate remaining distance
        from shared.route_planner import haversine_distance
        remaining_distance = haversine_distance(
            selected_airport.latitude_deg, selected_airport.longitude_deg,
            to_airport.latitude_deg, to_airport.longitude_deg
        )
        
        # Decrement remaining stops
        remaining_stops = (num_stops or 1) - 1
        
        # Check if this is the final stop based on confirmed count
        # This handles the case where LLM passes wrong values
        # Use original_num_stops (from token) which is reliable, not num_stops from LLM
        is_final_stop = (confirmed_stops_count + 1) >= original_num_stops
        
        if remaining_stops <= 0 or remaining_distance < 100 or is_final_stop:
            # Final leg - build complete route summary matching auto mode format
            all_stops = confirmed_stops_list + [selected_airport.ident]
            departure = original_departure_icao or from_airport.ident
            
            # Look up departure airport details
            departure_result = _find_nearest_airport_in_db(ctx, departure)
            departure_airport = departure_result["airport"] if departure_result else None
            
            # Build detailed route output matching auto mode format
            route_lines = []
            route_lines.append(f"✅ **Route planned: {departure} → {to_airport.ident}**\n")
            
            # Calculate total distance
            if departure_airport:
                total_distance = haversine_distance(
                    departure_airport.latitude_deg, departure_airport.longitude_deg,
                    to_airport.latitude_deg, to_airport.longitude_deg
                )
                route_lines.append(f"**Total distance:** {round(total_distance)}nm with {len(all_stops)} stop(s)\n")
            
            route_lines.append("---\n")
            route_lines.append("**Route:**\n")
            
            # Start point
            if departure_airport:
                route_lines.append(f"🛫 **{departure}** ({departure_airport.name})\n")
            else:
                route_lines.append(f"🛫 **{departure}**\n")
            
            # Build detailed info for each stop
            prev_airport = departure_airport
            for i, stop_icao in enumerate(all_stops):
                stop_result = _find_nearest_airport_in_db(ctx, stop_icao)
                if stop_result:
                    stop_apt = stop_result["airport"]
                    
                    # Calculate leg distance
                    if prev_airport:
                        leg_dist = haversine_distance(
                            prev_airport.latitude_deg, prev_airport.longitude_deg,
                            stop_apt.latitude_deg, stop_apt.longitude_deg
                        )
                    else:
                        leg_dist = 0
                    
                    # Calculate remaining distance to destination
                    dist_to_dest = haversine_distance(
                        stop_apt.latitude_deg, stop_apt.longitude_deg,
                        to_airport.latitude_deg, to_airport.longitude_deg
                    )
                    
                    # Get runway info - use same attributes as auto_plan
                    runway_length = getattr(stop_apt, 'longest_runway_length_ft', None) or 0
                    has_hard_runway = getattr(stop_apt, 'has_hard_runway', False)
                    has_fuel = getattr(stop_apt, 'has_avgas', False)
                    
                    # Build stop line
                    runway_info = f" / {round(runway_length)}ft" if runway_length else ""
                    route_lines.append(f"⛽ → **{stop_icao}** ({stop_apt.name}) - {round(leg_dist)}nm{runway_info}\n")
                    route_lines.append(f"  *↳ {round(dist_to_dest)}nm to {to_airport.ident}*\n")
                    route_lines.append(f"  Leg: {round(leg_dist)}nm, remaining: {round(dist_to_dest)}nm to {to_airport.ident}\n")
                    if runway_length:
                        route_lines.append(f"  ✅ Runway: {round(runway_length)}ft\n")
                    if has_hard_runway:
                        route_lines.append(f"  ✅ Hard surface\n")
                    if has_fuel:
                        route_lines.append(f"  ✅ Fuel available\n")
                    else:
                        route_lines.append(f"  ⚠️ No fuel available\n")
                    route_lines.append("\n")
                    
                    prev_airport = stop_apt
                else:
                    route_lines.append(f"⛽ → **{stop_icao}**\n\n")
            
            # Final destination
            route_lines.append(f"🛬 → **{to_airport.ident}** ({to_airport.name}) - {round(remaining_distance)}nm\n")
            
            return {
                "found": True,
                "route_complete": True,
                "stops": all_stops,
                "pretty": "".join(route_lines),
                "visualization": {
                    "type": "route_with_stops",
                    "from": {"ident": departure, "lat": departure_airport.latitude_deg if departure_airport else from_airport.latitude_deg, "lon": departure_airport.longitude_deg if departure_airport else from_airport.longitude_deg},
                    "to": {"ident": to_airport.ident, "lat": to_airport.latitude_deg, "lon": to_airport.longitude_deg},
                    "stops": [{"ident": s} for s in all_stops],
                }
            }
        
        # Need more stops - update context
        return {
            "found": True,
            "needs_next_leg": True,
            "needs_input": True,  # Flag for formatter
            "confirmed_stop": selected_airport.ident,
            "from_icao": selected_airport.ident,
            "to_icao": to_airport.ident,
            "remaining_stops": remaining_stops,
            "remaining_distance_nm": round(remaining_distance, 1),
            # Explicit hint for LLM on how to continue this flow
            "next_call_hint": {
                "tool": "plan_multi_leg_route",
                "required_args": {
                    "from_location": selected_airport.ident,
                    "to_location": to_airport.ident,
                    "num_stops": remaining_stops,
                },
                "user_provides": "first_leg_max_nm (from 'within Xnm') OR auto_plan=true (from 'automatic' or '1')"
            },
            "pretty": (
                f"✅ **Stop {confirmed_stops_count + 1} confirmed: {selected_airport.ident}** ({selected_airport.name})\n\n"
                f"Now finding {remaining_stops} more stop(s) for the {round(remaining_distance)}nm from {selected_airport.ident} to {to_airport.ident}.\n\n"
                f"---\n"
                f"❓ **How would you like to proceed?**\n\n"
                f"**1.** Automatic - let me find the best stops\n"
                f"**2.** Specify distance (e.g., 'within 200nm')\n\n"
                # Hidden context for LLM continuation - include continuation_token for reliable state
                # Include complete route history: all confirmed stops + original departure
                f"[NEXT CALL >>> from_location={selected_airport.ident} | to_location={to_airport.ident} | num_stops={remaining_stops} | confirmed_stops_count={confirmed_stops_count + 1} | "
                f"continuation_token={_create_continuation_token(original_num_stops, confirmed_stops_count + 1, confirmed_stops_list + [selected_airport.ident], original_departure_icao or from_airport.ident)} | "
                f"ALWAYS PASS continuation_token! | USER CHOICE: add auto_plan=True OR first_leg_max_nm=X]"
            ),
            "visualization": {
                "type": "route_with_stops",
                "from": {"ident": from_airport.ident, "lat": from_airport.latitude_deg, "lon": from_airport.longitude_deg},
                "to": {"ident": to_airport.ident, "lat": to_airport.latitude_deg, "lon": to_airport.longitude_deg},
                "stops": [{"ident": selected_airport.ident, "lat": selected_airport.latitude_deg, "lon": selected_airport.longitude_deg}],
            }
        }

    # Calculate total route distance
    from shared.route_planner import haversine_distance
    total_distance = haversine_distance(
        from_airport.latitude_deg, from_airport.longitude_deg,
        to_airport.latitude_deg, to_airport.longitude_deg
    )

    # Get persona's aircraft performance for default leg distance
    default_leg_cap = 400  # Default fallback
    if persona_id:
        try:
            from shared.ga_friendliness.config import get_default_personas
            personas = get_default_personas()
            if persona_id in personas.personas:
                persona = personas.personas[persona_id]
                if persona.aircraft:
                    default_leg_cap = persona.aircraft.leg_cap_nm
        except Exception:
            pass  # Use default

    # Determine effective max leg distance
    effective_max_leg = max_leg_distance_nm or default_leg_cap

    # AUTOMATIC MODE: Find all stops automatically
    if auto_plan and num_stops and num_stops > 0:
        if require_fuel:
            # For fuel stops: use aircraft's full range - find fuel as far as possible
            max_leg = effective_max_leg
        else:
            # For regular stops: divide distance equally with some flexibility
            target_leg = total_distance / (num_stops + 1)
            max_leg = min(target_leg * 1.3, effective_max_leg)  # 30% flexibility
        
        planned_stops = _auto_plan_all_stops(
            ctx, from_airport, to_airport, num_stops, max_leg, 
            persona_id=persona_id, require_fuel=bool(require_fuel)
        )
        
        if not planned_stops:
            return {
                "found": True,
                "stops": [],
                "pretty": (
                    f"Could not find suitable stops for the route from {from_airport.ident} to {to_airport.ident}. "
                    f"The distance is {round(total_distance)}nm with {num_stops} requested stops. "
                    f"Try reducing the number of stops or using manual mode."
                ),
            }
        
        # Build the complete route response
        stops_info = []
        route_parts = []
        total_route_dist = 0
        prev_airport = from_airport
        
        # Calculate all leg distances first to know next stop distances
        all_legs = []
        for i, stop in enumerate(planned_stops):
            apt = stop["airport"]
            dist = stop["distance_from_prev_nm"]
            all_legs.append({"airport": apt, "dist": dist, "stop": stop})
        
        # Add final leg info
        if planned_stops:
            last_apt = planned_stops[-1]["airport"]
            final_dist = haversine_distance(
                last_apt.latitude_deg, last_apt.longitude_deg,
                to_airport.latitude_deg, to_airport.longitude_deg
            )
        else:
            final_dist = total_distance
        
        # Build route parts with next stop info
        route_parts.append(f"🛫 **{from_airport.ident}** ({from_airport.name})")
        
        for i, leg in enumerate(all_legs):
            apt = leg["airport"]
            dist = leg["dist"]
            stop = leg["stop"]
            total_route_dist += dist
            
            # Calculate distance to next stop
            if i + 1 < len(all_legs):
                next_stop = all_legs[i + 1]["airport"]
                dist_to_next = all_legs[i + 1]["dist"]
                next_info = f"→ {dist_to_next}nm to {next_stop.ident}"
            else:
                next_info = f"→ {round(final_dist)}nm to {to_airport.ident}"
            
            # Format reasons on separate lines
            reasons_list = stop.get("reasons", [])
            reasons_formatted = "\n   ".join(reasons_list) if reasons_list else ""
            
            stops_info.append({
                "ident": apt.ident,
                "name": apt.name,
                "leg_distance_nm": dist,
                "has_avgas": getattr(apt, "has_avgas", False),
                "has_hard_runway": getattr(apt, "has_hard_runway", False),
                "longest_runway_ft": getattr(apt, "longest_runway_length_ft", None),
                "score": stop.get("score", 0),
                "reasons": ", ".join(reasons_list),
            })
            
            runway_info = f"{apt.longest_runway_length_ft}ft" if getattr(apt, "longest_runway_length_ft", None) else ""
            route_parts.append(
                f"⛽ → **{apt.ident}** ({apt.name}) - {dist}nm{' / ' + runway_info if runway_info else ''}\n"
                f"   *{next_info}*\n"
                f"   {reasons_formatted}"
            )
        
        total_route_dist += final_dist
        route_parts.append(f"🛬 → **{to_airport.ident}** ({to_airport.name}) - {round(final_dist)}nm")
        
        pretty_lines = [
            f"✅ **Route planned: {from_airport.ident} → {to_airport.ident}**\n",
            f"Total distance: {round(total_route_dist)}nm with {len(planned_stops)} stop(s)\n",
            "\n**Route:**\n",
        ]
        for part in route_parts:
            pretty_lines.append(part)
        
        # Build visualization stops
        viz_stops = [{"ident": s["airport"].ident, "lat": s["airport"].latitude_deg, "lon": s["airport"].longitude_deg} for s in planned_stops]
        
        return {
            "found": True,
            "route_complete": True,
            "from_icao": from_airport.ident,
            "to_icao": to_airport.ident,
            "stops": stops_info,
            "total_distance_nm": round(total_route_dist, 1),
            "pretty": "\n".join(pretty_lines),
            "visualization": {
                "type": "route_with_stops",
                "from": {"ident": from_airport.ident, "lat": from_airport.latitude_deg, "lon": from_airport.longitude_deg},
                "to": {"ident": to_airport.ident, "lat": to_airport.latitude_deg, "lon": to_airport.longitude_deg},
                "stops": viz_stops,
            }
        }

    # If num_stops specified but no leg distance, give user a choice
    if num_stops and num_stops > 0 and not first_leg_max_nm and not max_leg_distance_nm:
        # Calculate suggested target leg for reference
        target_leg = total_distance / (num_stops + 1)
        suggested_leg = min(round(target_leg, 0), effective_max_leg)
        
        return {
            "found": True,
            "needs_user_choice": True,
            "needs_input": True,  # Flag for formatter to know input is required
            "from_icao": from_airport.ident,
            "to_icao": to_airport.ident,
            "total_distance_nm": round(total_distance, 1),
            "requested_stops": num_stops,
            "suggested_first_leg_nm": suggested_leg,
            "persona_leg_cap": default_leg_cap,
            "pretty": (
                f"Planning route from **{from_airport.ident}** ({from_airport.name}) "
                f"to **{to_airport.ident}** ({to_airport.name}) - {round(total_distance)}nm total.\n\n"
                f"You want {num_stops} stops.\n\n"
                f"---\n"
                f"❓ **How would you like to proceed?**\n\n"
                f"1. **Automatic**: I'll find the best stops automatically (suggested first leg ~{suggested_leg}nm)\n"
                f"2. **Manual**: Tell me within what distance you'd like the first stop (e.g., 'first stop within 300nm')"
            ),
            "visualization": {
                "type": "route",
                "from": {"ident": from_airport.ident, "lat": from_airport.latitude_deg, "lon": from_airport.longitude_deg},
                "to": {"ident": to_airport.ident, "lat": to_airport.latitude_deg, "lon": to_airport.longitude_deg},
            }
        }
    
    # If num_stops specified with max_leg_distance (automatic mode), calculate first_leg
    if num_stops and num_stops > 0 and not first_leg_max_nm:
        target_leg = total_distance / (num_stops + 1)
        first_leg_max_nm = min(target_leg * 1.2, effective_max_leg)

    # If first_leg_max_nm specified, find candidates for first stop
    if first_leg_max_nm:
        # Find airports within first_leg_max_nm of departure, on the way to destination
        candidates = []
        corridor_width = 150.0  # nm - wider corridor for GA flexibility

        # Query airports near the departure
        try:
            from_lat = from_airport.latitude_deg
            from_lon = from_airport.longitude_deg
            to_lat = to_airport.latitude_deg
            to_lon = to_airport.longitude_deg

            # Get candidate airports from the database
            from shared.route_planner import cross_track_distance
            for airport in ctx.model.airports:
                if airport.ident in (from_airport.ident, to_airport.ident):
                    continue
                
                # Skip airports without coordinates
                if airport.latitude_deg is None or airport.longitude_deg is None:
                    continue

                # Calculate distance from departure
                dist_from_dep = haversine_distance(
                    from_lat, from_lon,
                    airport.latitude_deg, airport.longitude_deg
                )

                if dist_from_dep > first_leg_max_nm:
                    continue

                # Check cross-track distance (is it "on the way"?)
                xtd = cross_track_distance(
                    airport.latitude_deg, airport.longitude_deg,
                    from_lat, from_lon, to_lat, to_lon
                )

                if xtd > corridor_width:
                    continue

                # Calculate progress toward destination
                dist_to_dest = haversine_distance(
                    airport.latitude_deg, airport.longitude_deg,
                    to_lat, to_lon
                )
                progress = total_distance - dist_to_dest

                # Skip if not making forward progress
                if progress < 50:  # At least 50nm forward
                    continue

                # ============================================
                # FULL COST FUNCTION (same as auto mode)
                # ============================================
                score = progress  # Base: progress toward destination
                reasons = [f"Leg: {round(dist_from_dep)}nm, remaining: {round(dist_to_dest)}nm to {to_airport.ident}"]
                
                # --- Runway Assessment ---
                runway_length = getattr(airport, "longest_runway_length_ft", 0) or 0
                has_hard_runway = getattr(airport, "has_hard_runway", False)
                
                # Get persona's min runway requirement
                min_runway_ft = 1500  # Default
                fuel_type_required = None
                if persona_id:
                    try:
                        from shared.ga_friendliness.config import get_default_personas
                        personas = get_default_personas()
                        if persona_id in personas.personas:
                            persona = personas.personas[persona_id]
                            if persona.aircraft:
                                min_runway_ft = persona.aircraft.min_runway_ft
                                fuel_type_required = persona.aircraft.fuel_type
                    except Exception:
                        pass
                
                if runway_length < min_runway_ft:
                    score -= 1000
                    reasons.append(f"⚠️ Short runway: {round(runway_length)}ft < {min_runway_ft}ft")
                else:
                    runway_margin = runway_length - min_runway_ft
                    runway_bonus = min(runway_margin / 100, 20)
                    score += runway_bonus
                    reasons.append(f"✓ Runway: {round(runway_length)}ft")
                
                if has_hard_runway:
                    score += 15
                    reasons.append("✓ Hard surface")
                
                # --- Fuel Assessment ---
                has_avgas = getattr(airport, "has_avgas", False)
                has_jeta = getattr(airport, "has_jeta", False)
                has_any_fuel = has_avgas or has_jeta
                
                # When require_fuel=True, SKIP airports without fuel
                if require_fuel and not has_any_fuel:
                    continue  # Skip this airport - must have fuel
                
                if fuel_type_required:
                    if fuel_type_required.lower() == "avgas" and has_avgas:
                        score += 30
                        reasons.append("✓ AVGAS")
                    elif fuel_type_required.lower() == "jet-a" and has_jeta:
                        score += 30
                        reasons.append("✓ JET-A")
                    elif has_any_fuel and require_fuel:
                        continue  # Skip - wrong fuel type
                    elif has_any_fuel:
                        score -= 20
                        reasons.append(f"⚠️ No {fuel_type_required}")
                    else:
                        score -= 50
                        reasons.append("⚠️ No fuel")
                else:
                    if has_avgas:
                        score += 30 if require_fuel else 20
                        reasons.append("✓ AVGAS")
                    elif has_jeta:
                        score += 25 if require_fuel else 15
                        reasons.append("✓ JET-A")
                
                # --- Detour Penalty ---
                if xtd > 30:
                    detour_penalty = xtd * 0.5
                    score -= detour_penalty
                    reasons.append(f"Detour: {round(xtd)}nm")

                candidates.append({
                    "airport": airport,
                    "distance_from_departure_nm": round(dist_from_dep, 1),
                    "distance_to_destination_nm": round(dist_to_dest, 1),
                    "progress_nm": round(progress, 1),
                    "cross_track_nm": round(xtd, 1),
                    "score": round(score, 1),
                    "reasons": reasons,
                })

            # Sort by score (best score first - combines progress + runway bonuses)
            candidates.sort(key=lambda x: x["score"], reverse=True)

            # Limit results and build response
            max_candidates = 5
            top_candidates = candidates[:max_candidates]

            if not top_candidates:
                return {
                    "found": True,
                    "stops": [],
                    "pretty": f"No suitable stops found within {first_leg_max_nm}nm of {from_airport.ident} along the route to {to_airport.ident}.",
                }

            # Build response with candidate stops
            stops_info = []
            for c in top_candidates:
                apt = c["airport"]
                reasons_str = ", ".join(c.get("reasons", []))
                stops_info.append({
                    "ident": apt.ident,
                    "name": apt.name,
                    "distance_from_departure_nm": c["distance_from_departure_nm"],
                    "distance_to_destination_nm": c["distance_to_destination_nm"],
                    "has_avgas": getattr(apt, "has_avgas", False),
                    "has_hard_runway": getattr(apt, "has_hard_runway", False),
                    "longest_runway_ft": getattr(apt, "longest_runway_length_ft", None),
                    "score": c.get("score", 0),
                    "reasons": reasons_str,
                })

            pretty_lines = [
                f"**Stop candidates within {first_leg_max_nm}nm of {from_airport.ident}** (ranked by score):\n"
            ]
            for i, s in enumerate(stops_info, 1):
                runway_info = f"{s['longest_runway_ft']}ft" if s["longest_runway_ft"] else ""
                reason_note = f" ✓ *{s['reasons']}*" if s['reasons'] else ""
                pretty_lines.append(
                    f"{i}. **{s['ident']}** ({s['name']}) - {s['distance_from_departure_nm']}nm{' / ' + runway_info if runway_info else ''}{reason_note}"
                )

            remaining_stops = (num_stops or 1) - 1
            dist_remaining = round(top_candidates[0]['distance_to_destination_nm'])
            
            # Map candidate numbers to ICAO codes for the hint
            candidate_map = ", ".join([f"{i+1}={s['ident']}" for i, s in enumerate(stops_info)])
            
            if remaining_stops > 0:
                pretty_lines.append(f"\n---\n❓ **Select a stop** by number (1-{len(stops_info)}) or ICAO code (e.g., '{stops_info[0]['ident']}').")
                pretty_lines.append(f"After selection, we'll find {remaining_stops} more stop(s) for the remaining {dist_remaining}nm to {to_airport.ident}.")
            else:
                pretty_lines.append(f"\n---\n❓ **Which stop would you like?** Enter a number (1-{len(stops_info)}) or ICAO code.\nFrom there it's {dist_remaining}nm direct to {to_airport.ident}.")
            
            # Add hidden context for LLM continuation - include continuation_token for reliable state
            # IMPORTANT: Pass current num_stops, NOT remaining_stops. The stop confirmation code handles decrement.
            token = _create_continuation_token(original_num_stops, confirmed_stops_count, confirmed_stops_list, original_departure_icao or from_airport.ident)
            continue_hint = f"\n[NEXT CALL >>> from_location={from_airport.ident} | to_location={to_airport.ident} | num_stops={num_stops} | confirmed_stops_count={confirmed_stops_count} | continuation_token={token} | selected_stop=USER_CHOICE | Mapping: {candidate_map}]"
            pretty_lines.append(continue_hint)
            print(f"[DEBUG] Added NEXT CALL hint: num_stops={num_stops}, token={token}")  # Debug

            return {
                "found": True,
                "needs_selection": True,
                "needs_input": True,  # Flag for formatter - don't say "results shown on map"
                "from_icao": from_airport.ident,
                "to_icao": to_airport.ident,
                "remaining_stops": remaining_stops,
                "constraint": {"first_leg_max_nm": first_leg_max_nm},
                "stops": stops_info,
                "pretty": "\n".join(pretty_lines),
                "visualization": {
                    "type": "route_with_stops",
                    "from": {"ident": from_airport.ident, "lat": from_airport.latitude_deg, "lon": from_airport.longitude_deg},
                    "to": {"ident": to_airport.ident, "lat": to_airport.latitude_deg, "lon": to_airport.longitude_deg},
                    "candidates": [{"ident": s["ident"], "lat": c["airport"].latitude_deg, "lon": c["airport"].longitude_deg} for s, c in zip(stops_info, top_candidates)],
                }
            }

        except Exception as e:
            import traceback
            import logging
            logger = logging.getLogger(__name__)
            logger.error(f"Error in plan_multi_leg_route: {e}")
            logger.error(traceback.format_exc())
            print(f"ERROR in plan_multi_leg_route: {e}")  # Debug print
            print(traceback.format_exc())
            return {
                "found": False,
                "error": str(e),
                "pretty": f"Error finding stop candidates: {e}"
            }

    # Default: return route info with suggested leg distance
    suggested_stops = max(0, int(total_distance / effective_max_leg) - 1)

    return {
        "found": True,
        "from_icao": from_airport.ident,
        "from_name": from_airport.name,
        "to_icao": to_airport.ident,
        "to_name": to_airport.name,
        "total_distance_nm": round(total_distance, 1),
        "effective_max_leg_nm": effective_max_leg,
        "suggested_stops": suggested_stops,
        "pretty": (
            f"Route from **{from_airport.ident}** ({from_airport.name}) to **{to_airport.ident}** ({to_airport.name})\n"
            f"- Total distance: {round(total_distance)}nm\n"
            f"- Max leg distance: {effective_max_leg}nm (from persona)\n"
            f"- Suggested stops: {suggested_stops}\n\n"
            f"Would you like me to find stop options? You can specify:\n"
            f"- 'First stop within Xnm'\n"
            f"- 'Plan {suggested_stops} stops'"
        ),
        "visualization": {
            "type": "route",
            "from": {"ident": from_airport.ident, "lat": from_airport.latitude_deg, "lon": from_airport.longitude_deg},
            "to": {"ident": to_airport.ident, "lat": to_airport.latitude_deg, "lon": to_airport.longitude_deg},
        }
    }


# -----------------------------------------------------------------------------
# Notification Requirements
# -----------------------------------------------------------------------------

def get_notification_for_airport(
    ctx: ToolContext,
    icao: str,
    day_of_week: Optional[str] = None,
    **kwargs: Any,  # Accept _persona_id injected by ToolRunner (not used by this tool)
) -> Dict[str, Any]:
    """
    Get customs/immigration notification requirements for a specific airport.

    Use when user asks about notification requirements, customs, or when to
    notify for a specific airport.
    """
    # Extract and ignore _persona_id (injected by ToolRunner, not used by this tool)
    kwargs.pop("_persona_id", None)

    if not ctx.notification_service:
        return {
            "found": False,
            "icao": icao.upper(),
            "error": "Notification service not available.",
            "pretty": f"Notification service not available. Cannot look up {icao.upper()}."
        }
    return ctx.notification_service.get_notification_for_airport(icao, day_of_week)


# =============================================================================
# SECTION 6: RULES TOOLS
# =============================================================================

# -----------------------------------------------------------------------------
# Country Rules
# -----------------------------------------------------------------------------

def answer_rules_question(
    ctx: ToolContext,
    country_code: str,
    question: str,
    tags: Optional[List[str]] = None,
    use_rag: bool = True,
) -> Dict[str, Any]:
    """
    Answer a specific question about aviation rules for a country.
    Uses semantic search (RAG) to find the most relevant Q&A pairs.

    Args:
        country_code: ISO-2 country code (e.g., FR, GB)
        question: The user's actual question
        tags: Optional tags to filter results (used as fallback if RAG unavailable)
        use_rag: Use RAG semantic search (default: True). Falls back to tags if False or RAG unavailable.
    """
    country_code = country_code.upper()
    rules_manager = ctx.ensure_rules_manager()

    # Try RAG-based retrieval first
    if use_rag and ctx.rules_rag:
        try:
            results = ctx.rules_rag.retrieve_rules(
                query=question,
                countries=[country_code],
                top_k=5,
                similarity_threshold=0.3,
            )

            if results:
                # Format results for display
                formatted_lines = []
                for r in results:
                    q = r.get('question_text', '')
                    a = r.get('answer_html', r.get('answer', ''))
                    score = r.get('similarity', 0)
                    formatted_lines.append(f"**Q: {q}**\nA: {a}\n(relevance: {score:.2f})")

                return {
                    "found": True,
                    "country_code": country_code,
                    "count": len(results),
                    "retrieval_mode": "rag",
                    "rules": results,
                    "formatted_text": "\n\n".join(formatted_lines),
                }
        except Exception as e:
            import logging
            logging.getLogger(__name__).warning(f"RAG retrieval failed, falling back to tags: {e}")

    # Fallback to tag-based retrieval
    rules = rules_manager.get_rules_for_country(
        country_code=country_code,
        tags=tags
    )

    if not rules:
        available = ", ".join(rules_manager.get_available_countries())
        return {
            "found": False,
            "country_code": country_code,
            "count": 0,
            "retrieval_mode": "tags",
            "message": f"No rules found for {country_code}. Available countries: {available}"
        }

    formatted_text = rules_manager.format_rules_for_display(rules, group_by_category=True)

    return {
        "found": True,
        "country_code": country_code,
        "count": len(rules),
        "retrieval_mode": "tags",
        "rules": rules[:20],  # Limit for tag-based (less targeted)
        "formatted_text": formatted_text,
    }


def browse_rules(
    ctx: ToolContext,
    country_code: str,
    tags: Optional[List[str]] = None,
    offset: int = 0,
    limit: int = 10,
) -> Dict[str, Any]:
    """
    Browse/list aviation rules for a country with pagination.
    Use this when user wants to see all rules in a category, not answer a specific question.

    Args:
        country_code: ISO-2 country code (e.g., FR, GB)
        tags: Optional tags to filter rules (e.g., ['flight_plan', 'transponder'])
        offset: Starting index for pagination (default: 0)
        limit: Maximum rules to return (default: 10, max: 50)
    """
    country_code = country_code.upper()
    limit = min(limit, 50)  # Cap at 50

    rules_manager = ctx.ensure_rules_manager()
    all_rules = rules_manager.get_rules_for_country(
        country_code=country_code,
        tags=tags
    )

    if not all_rules:
        available = ", ".join(rules_manager.get_available_countries())
        return {
            "found": False,
            "country_code": country_code,
            "total": 0,
            "message": f"No rules found for {country_code}. Available countries: {available}"
        }

    total = len(all_rules)
    paginated_rules = all_rules[offset:offset + limit]
    has_more = (offset + limit) < total

    formatted_text = rules_manager.format_rules_for_display(paginated_rules, group_by_category=True)
    categories = list({r.get('category', 'General') for r in paginated_rules})

    return {
        "found": True,
        "country_code": country_code,
        "total": total,
        "offset": offset,
        "limit": limit,
        "count": len(paginated_rules),
        "has_more": has_more,
        "rules": paginated_rules,
        "formatted_text": formatted_text,
        "categories": categories,
        "next_offset": offset + limit if has_more else None,
    }


# -----------------------------------------------------------------------------
# Comparison
# -----------------------------------------------------------------------------

def compare_rules_between_countries(
    ctx: ToolContext,
    countries: List[str],
    tags: Optional[List[str]] = None,
    use_embeddings: bool = True,
) -> Dict[str, Any]:
    """
    Compare aviation rules and regulations between countries (iso-2 codes eg FR,GB,DE).
    Can be filtered by tags like flight_plan, transponder, airspace, etc.

    This tool returns DATA only - synthesis is done by the formatter node.
    Returns a _tool_type="comparison" marker for formatter routing.
    """
    countries = [c.upper() for c in countries]

    # Try embedding-based comparison first (smarter - detects semantic differences)
    # NOTE: Tool returns DATA only - synthesis is done by formatter
    if use_embeddings and ctx.comparison_service:
        try:
            result = ctx.comparison_service.compare_countries(
                countries=countries,
                tags=tags,
                synthesize=False,  # Never synthesize in tool - formatter does this
            )

            # Build differences for response
            differences = result.differences if result.differences else []

            # Build rules_context for formatter (pre-formatted for synthesis prompt)
            rules_context_lines = []
            for i, diff in enumerate(differences, 1):
                rules_context_lines.append(f"\n### {i}. {diff.get('question_text', 'Unknown question')}")
                rules_context_lines.append(f"Tags: {', '.join(diff.get('tags', []))}")
                rules_context_lines.append(f"Semantic difference score: {diff.get('difference_score', 0):.2f}")
                rules_context_lines.append("")
                for cc, answer in diff.get("answers", {}).items():
                    rules_context_lines.append(f"**{cc}**: {answer}")
                rules_context_lines.append("")

            countries_str = ", ".join(countries)
            return {
                "found": True,
                "countries": countries,
                "tags": tags,
                "total_questions": result.total_questions,
                "questions_analyzed": result.questions_analyzed,
                "filtered_by_embedding": result.filtered_by_embedding,
                "differences": differences,
                "rules_context": "\n".join(rules_context_lines),  # For formatter synthesis
                "total_differences": len(differences),
                "message": f"Comparison between {countries_str} complete.",
                # Mark this as a comparison tool for formatter routing
                "_tool_type": "comparison",
            }
        except Exception as e:
            # Log and fall back to simple comparison
            import logging
            logging.getLogger(__name__).warning(
                f"Embedding comparison failed, falling back to text: {e}"
            )

    # Fall back to simple text-based comparison (only supports 2 countries)
    rules_manager = ctx.ensure_rules_manager()
    if len(countries) >= 2:
        comparison = rules_manager.compare_rules_between_countries(
            country1=countries[0],
            country2=countries[1],
        )
    else:
        comparison = {"differences": []}

    diff_count = len(comparison.get('differences', []))

    # Build rules_context from text-based comparison for formatter
    rules_context_lines = []
    for i, diff in enumerate(comparison.get('differences', []), 1):
        rules_context_lines.append(f"\n### {i}. {diff.get('question_text', 'Unknown')}")
        for cc, rule in diff.get('rules', {}).items():
            rules_context_lines.append(f"**{cc}**: {rule}")
        rules_context_lines.append("")

    countries_str = ", ".join(countries)
    return {
        "found": True,
        "countries": countries,
        "tags": tags,
        "comparison": comparison,
        "differences": comparison.get('differences', []),
        "rules_context": "\n".join(rules_context_lines),  # For formatter synthesis
        "total_differences": diff_count,
        "filtered_by_embedding": False,
        "message": f"Comparison between {countries_str} complete.",
        "_tool_type": "comparison",
    }


def _compare_rules_between_countries_tool(
    ctx: ToolContext,
    countries: List[str],
    tags: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """
    Wrapper that adds a human readable summary field expected by UI clients.
    Used as the actual handler in the tool registry.
    """
    result = compare_rules_between_countries(
        ctx, countries, tags=tags
    )
    if result.get("formatted_summary") and "pretty" not in result:
        result["pretty"] = result["formatted_summary"]
    return result


# =============================================================================
# SECTION 7: TOOL REGISTRY
# =============================================================================

def _build_shared_tool_specs() -> OrderedDictType[str, ToolSpec]:
    """
    Create the ordered manifest of shared tools.

    All tools have expose_to_llm=True and are available to the aviation agent and MCP server.

    AIRPORT TOOLS:
    - search_airports
    - find_airports_near_location
    - find_airports_near_route
    - get_airport_details
    - get_notification_for_airport

    RULES TOOLS:
    - answer_rules_question
    - browse_rules
    - compare_rules_between_countries
    """
    return OrderedDict([
        # -----------------------------------------------------------------
        # AIRPORT SEARCH & DISCOVERY
        # -----------------------------------------------------------------
        (
            "search_airports",
            {
                "name": "search_airports",
                "handler": search_airports,
                "description": _get_tool_description(search_airports, "search_airports"),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "Airport name, ICAO/IATA code, or city (e.g., 'Paris', 'LFPG').",
                        },
                        "max_results": {
                            "type": "integer",
                            "description": "Maximum number of airports to return. Default is 5. Use higher values (e.g., 10, 20) when user asks for 'all airports', 'more airports', or specifies a number.",
                            "default": 5,
                        },
                        "filters": {
                            "type": "object",
                            "description": "IMPORTANT: Use filters object to filter airports by characteristics mentioned in user's request. Examples: {'has_avgas': True} for AVGAS fuel, {'point_of_entry': True} for customs, {'has_hard_runway': True} for paved runways, {'has_procedures': True} for IFR, {'country': 'FR'} for country. ALWAYS include filters when user specifies characteristics.",
                        },
                        "include_large_airports": {
                            "type": "boolean",
                            "description": "Include large commercial airports (e.g., Heathrow, CDG, JFK). Default is False - large airports are excluded as they are not suitable for GA. Set to True ONLY if user explicitly asks for large/commercial/major airports.",
                            "default": False,
                        },
                        "priority_strategy": {
                            "type": "string",
                            "description": "Priority sorting strategy (e.g., persona_optimized).",
                            "default": "persona_optimized",
                        },
                    },
                    "required": ["query"],
                },
                "expose_to_llm": True,
            },
        ),
        (
            "find_airports_near_location",
            {
                "name": "find_airports_near_location",
                "handler": find_airports_near_location,
                "description": _get_tool_description(find_airports_near_location, "find_airports_near_location"),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "location_query": {
                            "type": "string",
                            "description": "Free-text location: city name (e.g., 'Paris', 'Zurich'), landmark (e.g., 'Lake Geneva'), address (e.g., 'Nice, France'), or coordinates (e.g., '48.8584, 2.2945'). DO NOT use ICAO codes here - use find_airports_near_route for ICAO-based route searches.",
                        },
                        "max_distance_nm": {
                            "type": "number",
                            "description": "Max distance from the location in nautical miles.",
                            "default": 50.0,
                        },
                        "max_results": {
                            "type": "integer",
                            "description": "Maximum number of airports to return. Default is 5. Use higher values (e.g., 10, 20) when user asks for 'all airports', 'more airports', or specifies a number.",
                            "default": 5,
                        },
                        "filters": {
                            "type": "object",
                            "description": "Airport filters (fuel, customs, runway length, etc.).",
                        },
                        "include_large_airports": {
                            "type": "boolean",
                            "description": "Include large commercial airports (e.g., Heathrow, CDG, JFK). Default is False - large airports are excluded as they are not suitable for GA. Set to True ONLY if user explicitly asks for large/commercial/major airports.",
                            "default": False,
                        },
                        "priority_strategy": {
                            "type": "string",
                            "description": "Priority sorting strategy (e.g., persona_optimized).",
                            "default": "persona_optimized",
                        },
                        "max_hours_notice": {
                            "type": "integer",
                            "description": "Filter by notification requirements. Only include airports that require at most this many hours of prior notice (e.g., 24 for airports with less than 24h notice, 48 for less than 48h).",
                        },
                    },
                    "required": ["location_query"],
                },
                "expose_to_llm": True,
            },
        ),
        (
            "find_airports_near_route",
            {
                "name": "find_airports_near_route",
                "handler": find_airports_near_route,
                "description": _get_tool_description(find_airports_near_route, "find_airports_near_route"),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "from_location": {
                            "type": "string",
                            "description": "Departure location - pass EXACTLY as user provides it INCLUDING any country/region context. Can be ICAO code (e.g., 'LFPO') OR location name with country (e.g., 'Bromley, UK', 'Paris, France', 'Vik, Iceland'). DO NOT convert location names to ICAO codes. ALWAYS include country if user mentions it.",
                        },
                        "to_location": {
                            "type": "string",
                            "description": "Destination location - pass EXACTLY as user provides it INCLUDING any country/region context. Can be ICAO code (e.g., 'EDDM') OR location name with country (e.g., 'Vik, Iceland', 'Nice, France'). DO NOT convert location names to ICAO codes. ALWAYS include country if user mentions it.",
                        },
                        "max_distance_nm": {
                            "type": "number",
                            "description": "Max distance from route centerline in nautical miles.",
                            "default": 50.0,
                        },
                        "max_results": {
                            "type": "integer",
                            "description": "Maximum number of airports to return. Default is 5. Use higher values (e.g., 10, 20) when user asks for 'all airports', 'more airports', or specifies a number.",
                            "default": 5,
                        },
                        "filters": {
                            "type": "object",
                            "description": "IMPORTANT: Use filters object to filter airports by characteristics mentioned in user's request. Examples: {'has_avgas': True} for AVGAS fuel, {'point_of_entry': True} for customs, {'has_hard_runway': True} for paved runways, {'has_procedures': True} for IFR, {'country': 'FR'} for country. ALWAYS include filters when user specifies characteristics like fuel type, customs, runway type, etc.",
                        },
                        "include_large_airports": {
                            "type": "boolean",
                            "description": "Include large commercial airports (e.g., Heathrow, CDG, JFK). Default is False - large airports are excluded as they are not suitable for GA. Set to True ONLY if user explicitly asks for large/commercial/major airports.",
                            "default": False,
                        },
                        "priority_strategy": {
                            "type": "string",
                            "description": "Priority sorting strategy (e.g., persona_optimized).",
                            "default": "persona_optimized",
                        },
                        "max_hours_notice": {
                            "type": "integer",
                            "description": "Filter by notification requirements. Only include airports that require at most this many hours of prior notice (e.g., 24 for airports with less than 24h notice, 48 for less than 48h). Use when user asks for airports with specific notification constraints.",
                        },
                    },
                    "required": ["from_location", "to_location"],
                },
                "expose_to_llm": True,
            },
        ),
        (
            "plan_multi_leg_route",
            {
                "name": "plan_multi_leg_route",
                "handler": plan_multi_leg_route,
                "description": _get_tool_description(plan_multi_leg_route, "plan_multi_leg_route"),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "from_location": {
                            "type": "string",
                            "description": "Departure airport ICAO code or location name (e.g., 'EGKL', 'Paris').",
                        },
                        "to_location": {
                            "type": "string",
                            "description": "Destination airport ICAO code or location name (e.g., 'LFKO', 'Corsica').",
                        },
                        "num_stops": {
                            "type": "integer",
                            "description": "Number of intermediate stops requested (e.g., '3 stops' → num_stops=3). Auto-calculates if not specified.",
                        },
                        "max_leg_distance_nm": {
                            "type": "number",
                            "description": "Maximum distance per leg in nm. Uses persona's aircraft range if not specified.",
                        },
                        "first_leg_max_nm": {
                            "type": "number",
                            "description": "Maximum distance for next leg (e.g., 'within 200nm' → first_leg_max_nm=200). NEVER use together with selected_stop. Use ONLY when user specifies distance like 'within Xnm'.",
                        },
                        "selected_stop": {
                            "type": "string",
                            "description": "ICAO code the user picked from candidate list. Use ONLY when user selects by ICAO or number (e.g., 'LFMN' or '3'). NEVER use when user says 'within Xnm' or 'automatic'.",
                        },
                        "auto_plan": {
                            "type": "boolean",
                            "description": "Set true when user says 'automatic' or '1'. NEVER use together with selected_stop. Do not set when user says 'within Xnm'.",
                        },
                        "require_fuel": {
                            "type": "boolean",
                            "description": "Set to true when user specifically needs FUEL stops (e.g., 'fuel stops', 'refueling stops'). When true, airports without fuel are eliminated. Default false for rest/lunch stops.",
                        },
                        "confirmed_stops_count": {
                            "type": "integer",
                            "description": "Number of stops already confirmed in multi-turn flow. Extract from '[CONTINUE: ...confirmed_stops_count=N]' in previous message. Default 0 for new routes.",
                        },
                        "filters": {
                            "type": "object",
                            "description": "Airport filters for stops (fuel type, runway, customs, etc.).",
                        },
                    },
                    "required": ["from_location", "to_location"],
                },
                "expose_to_llm": True,
            },
        ),
        (
            "get_airport_details",
            {
                "name": "get_airport_details",
                "handler": get_airport_details,
                "description": _get_tool_description(get_airport_details, "get_airport_details"),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "icao_code": {
                            "type": "string",
                            "description": "Airport ICAO code (e.g., LFPG).",
                        },
                    },
                    "required": ["icao_code"],
                },
                "expose_to_llm": True,
            },
        ),
        # -----------------------------------------------------------------
        # NOTIFICATION
        # -----------------------------------------------------------------
        (
            "get_notification_for_airport",
            {
                "name": "get_notification_for_airport",
                "handler": get_notification_for_airport,
                "description": _get_tool_description(get_notification_for_airport, "get_notification_for_airport"),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "icao": {
                            "type": "string",
                            "description": "Airport ICAO code (e.g., LFRG, LFPT).",
                        },
                        "day_of_week": {
                            "type": "string",
                            "description": "Optional day to get specific rules for (e.g., Saturday, Monday).",
                        },
                    },
                    "required": ["icao"],
                },
                "expose_to_llm": True,
            },
        ),
        # -----------------------------------------------------------------
        # RULES
        # -----------------------------------------------------------------
        (
            "answer_rules_question",
            {
                "name": "answer_rules_question",
                "handler": answer_rules_question,
                "description": _get_tool_description(answer_rules_question, "answer_rules_question"),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "country_code": {
                            "type": "string",
                            "description": "ISO-2 country code (e.g., FR, GB).",
                        },
                        "question": {
                            "type": "string",
                            "description": "The user's question about aviation rules.",
                        },
                        "tags": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "Optional tags to help filter results (e.g., ['flight_plan', 'transponder']).",
                        },
                    },
                    "required": ["country_code", "question"],
                },
                "expose_to_llm": True,
            },
        ),
        (
            "browse_rules",
            {
                "name": "browse_rules",
                "handler": browse_rules,
                "description": _get_tool_description(browse_rules, "browse_rules"),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "country_code": {
                            "type": "string",
                            "description": "ISO-2 country code (e.g., FR, GB).",
                        },
                        "tags": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "Optional tags to filter rules (e.g., ['flight_plan', 'transponder']).",
                        },
                        "offset": {
                            "type": "integer",
                            "description": "Starting index for pagination (default: 0).",
                        },
                        "limit": {
                            "type": "integer",
                            "description": "Maximum rules to return (default: 10, max: 50).",
                        },
                    },
                    "required": ["country_code"],
                },
                "expose_to_llm": True,
            },
        ),
        (
            "compare_rules_between_countries",
            {
                "name": "compare_rules_between_countries",
                "handler": _compare_rules_between_countries_tool,
                "description": _get_tool_description(compare_rules_between_countries, "compare_rules_between_countries"),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "countries": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "List of ISO-2 country codes to compare (e.g., ['FR', 'GB', 'DE']).",
                        },
                        "tags": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "Optional list of tags to filter (e.g., ['flight_plan', 'transponder']).",
                        },
                    },
                    "required": ["countries"],
                },
                "expose_to_llm": True,
            },
        ),
    ])


# Module-level tool registry (built once at import time)
_SHARED_TOOL_SPECS: OrderedDictType[str, ToolSpec] = _build_shared_tool_specs()


def get_shared_tool_specs() -> OrderedDictType[str, ToolSpec]:
    """
    Return the shared tool manifest.

    The mapping is ordered to keep registration deterministic.
    Tools are organized into categories - see _build_shared_tool_specs() for details.

    Returns:
        OrderedDict mapping tool names to ToolSpec dicts
    """
    return _SHARED_TOOL_SPECS.copy()
