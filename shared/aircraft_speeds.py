"""
Aircraft Cruise Speed Reference Data
====================================

Provides typical cruise speeds for common general aviation aircraft.
Used by flight distance/time calculation tools.

Usage:
    from shared.aircraft_speeds import resolve_cruise_speed, get_aircraft_info

    # Resolve speed from aircraft type
    speed, source = resolve_cruise_speed(aircraft_type="c172")
    # Returns: (120, "typical Cessna 172 cruise (~110-130 kts)")

    # Or with explicit speed (takes precedence)
    speed, source = resolve_cruise_speed(cruise_speed_kts=140)
    # Returns: (140, "provided")
"""
from __future__ import annotations

import re
from typing import Optional, Tuple, TypedDict


class AircraftSpeedInfo(TypedDict):
    """Information about an aircraft's cruise speed."""
    name: str           # Full aircraft name
    cruise_kts: int     # Typical cruise speed in knots
    range: str          # Speed range (e.g., "110-130")


# Curated list of common GA aircraft with typical cruise speeds
# Sources: POH data, manufacturer specs, pilot reports
AIRCRAFT_CRUISE_SPEEDS: dict[str, AircraftSpeedInfo] = {
    # Cessna single-engine
    "c150": {"name": "Cessna 150", "cruise_kts": 105, "range": "100-110"},
    "c152": {"name": "Cessna 152", "cruise_kts": 110, "range": "105-115"},
    "c172": {"name": "Cessna 172", "cruise_kts": 120, "range": "110-130"},
    "c182": {"name": "Cessna 182", "cruise_kts": 145, "range": "140-155"},
    "c206": {"name": "Cessna 206", "cruise_kts": 150, "range": "145-160"},
    "c210": {"name": "Cessna 210", "cruise_kts": 170, "range": "165-180"},

    # Piper single-engine
    "pa28": {"name": "Piper PA-28 Cherokee", "cruise_kts": 125, "range": "115-135"},
    "pa32": {"name": "Piper PA-32 Cherokee Six", "cruise_kts": 150, "range": "140-160"},
    "pa46": {"name": "Piper PA-46 Malibu", "cruise_kts": 210, "range": "200-220"},

    # Piper twins
    "pa34": {"name": "Piper PA-34 Seneca", "cruise_kts": 180, "range": "170-190"},
    "pa44": {"name": "Piper PA-44 Seminole", "cruise_kts": 160, "range": "155-170"},

    # Cirrus
    "sr20": {"name": "Cirrus SR20", "cruise_kts": 155, "range": "150-165"},
    "sr22": {"name": "Cirrus SR22", "cruise_kts": 170, "range": "165-180"},
    "sr22t": {"name": "Cirrus SR22T", "cruise_kts": 180, "range": "175-190"},

    # Diamond
    "da40": {"name": "Diamond DA40", "cruise_kts": 130, "range": "125-140"},
    "da42": {"name": "Diamond DA42", "cruise_kts": 170, "range": "165-180"},
    "da62": {"name": "Diamond DA62", "cruise_kts": 180, "range": "175-190"},

    # Socata/Daher
    "tb10": {"name": "Socata TB10 Tobago", "cruise_kts": 130, "range": "125-140"},
    "tb20": {"name": "Socata TB20 Trinidad", "cruise_kts": 155, "range": "150-165"},
    "tbm": {"name": "Daher TBM", "cruise_kts": 290, "range": "280-330"},
    "tbm850": {"name": "Daher TBM 850", "cruise_kts": 300, "range": "290-320"},
    "tbm900": {"name": "Daher TBM 900", "cruise_kts": 320, "range": "310-330"},

    # Robin
    "dr400": {"name": "Robin DR400", "cruise_kts": 125, "range": "120-135"},
    "dr401": {"name": "Robin DR401", "cruise_kts": 125, "range": "120-135"},

    # Beechcraft
    "be35": {"name": "Beechcraft Bonanza", "cruise_kts": 165, "range": "160-175"},
    "be36": {"name": "Beechcraft Bonanza 36", "cruise_kts": 170, "range": "165-180"},
    "be58": {"name": "Beechcraft Baron", "cruise_kts": 195, "range": "190-205"},
    "c90": {"name": "Beechcraft King Air C90", "cruise_kts": 250, "range": "240-260"},
    "b200": {"name": "Beechcraft King Air 200", "cruise_kts": 280, "range": "270-290"},

    # Mooney
    "m20": {"name": "Mooney M20", "cruise_kts": 160, "range": "150-175"},
    "m20j": {"name": "Mooney M20J", "cruise_kts": 165, "range": "160-175"},
    "m20r": {"name": "Mooney M20R Ovation", "cruise_kts": 185, "range": "180-195"},

    # Grumman/American General
    "aa5": {"name": "Grumman AA-5", "cruise_kts": 130, "range": "125-140"},
    "aa5b": {"name": "Grumman AA-5B Tiger", "cruise_kts": 140, "range": "135-150"},

    # Other common types
    "rv6": {"name": "Van's RV-6", "cruise_kts": 170, "range": "160-180"},
    "rv7": {"name": "Van's RV-7", "cruise_kts": 175, "range": "165-185"},
    "rv8": {"name": "Van's RV-8", "cruise_kts": 185, "range": "175-195"},
    "rv10": {"name": "Van's RV-10", "cruise_kts": 175, "range": "165-185"},
    "lancair": {"name": "Lancair", "cruise_kts": 200, "range": "180-220"},

    # Light Sport / Ultralight
    "ct": {"name": "Flight Design CT", "cruise_kts": 110, "range": "100-120"},
    "ctls": {"name": "Flight Design CTLS", "cruise_kts": 115, "range": "105-120"},
    "sportcruiser": {"name": "SportCruiser", "cruise_kts": 110, "range": "100-115"},
    "tecnam": {"name": "Tecnam P2008", "cruise_kts": 115, "range": "110-125"},

    # Training aircraft
    "aquila": {"name": "Aquila A210", "cruise_kts": 120, "range": "115-130"},
    "katana": {"name": "Diamond Katana", "cruise_kts": 110, "range": "105-120"},
}

# Aliases for common name variations
AIRCRAFT_ALIASES: dict[str, str] = {
    # Cessna variations
    "cessna150": "c150",
    "cessna152": "c152",
    "cessna172": "c172",
    "skyhawk": "c172",
    "cessna182": "c182",
    "skylane": "c182",
    "cessna206": "c206",
    "stationair": "c206",
    "cessna210": "c210",
    "centurion": "c210",

    # Piper variations
    "cherokee": "pa28",
    "warrior": "pa28",
    "archer": "pa28",
    "arrow": "pa28",
    "seneca": "pa34",
    "seminole": "pa44",
    "malibu": "pa46",

    # Cirrus variations
    "cirrus": "sr22",
    "sr22turbo": "sr22t",

    # Diamond variations
    "diamond": "da40",
    "diamondstar": "da40",
    "twinstar": "da42",

    # Socata variations
    "tobago": "tb10",
    "trinidad": "tb20",

    # Robin variations
    "robin": "dr400",

    # Beechcraft variations
    "bonanza": "be36",
    "baron": "be58",
    "kingair": "b200",

    # Mooney variations
    "mooney": "m20j",
    "ovation": "m20r",

    # Other variations
    "tiger": "aa5b",
    "rv": "rv7",
}


def normalize_aircraft_type(aircraft_type: str) -> str:
    """
    Normalize an aircraft type string to a lookup key.

    Handles various input formats:
    - "Cessna 172" -> "c172"
    - "C-172" -> "c172"
    - "cessna172" -> "c172"
    - "skyhawk" -> "c172" (via alias)

    Args:
        aircraft_type: User-provided aircraft type string

    Returns:
        Normalized key for lookup in AIRCRAFT_CRUISE_SPEEDS
    """
    # Lowercase and remove common separators
    normalized = aircraft_type.lower().strip()
    normalized = re.sub(r'[-_\s]+', '', normalized)

    # Direct match first
    if normalized in AIRCRAFT_CRUISE_SPEEDS:
        return normalized

    # Check aliases
    if normalized in AIRCRAFT_ALIASES:
        return AIRCRAFT_ALIASES[normalized]

    # Try to extract model number patterns
    # "cessna172" -> "c172", "piper28" -> "pa28"
    patterns = [
        (r'cessna(\d+)', r'c\1'),
        (r'piper(\d+)', r'pa\1'),
        (r'pa(\d+)', r'pa\1'),
        (r'sr(\d+[a-z]?)', r'sr\1'),
        (r'da(\d+)', r'da\1'),
        (r'tb(\d+)', r'tb\1'),
        (r'dr(\d+)', r'dr\1'),
        (r'rv(\d+)', r'rv\1'),
        (r'be(\d+)', r'be\1'),
        (r'm(\d+[a-z]?)', r'm\1'),
    ]

    for pattern, replacement in patterns:
        match = re.search(pattern, normalized)
        if match:
            extracted = re.sub(pattern, replacement, match.group())
            if extracted in AIRCRAFT_CRUISE_SPEEDS:
                return extracted

    # No match found
    return normalized


def get_aircraft_info(aircraft_type: str) -> Optional[AircraftSpeedInfo]:
    """
    Get aircraft information by type.

    Args:
        aircraft_type: Aircraft type (e.g., "c172", "Cessna 172", "skyhawk")

    Returns:
        AircraftSpeedInfo dict or None if not found
    """
    key = normalize_aircraft_type(aircraft_type)
    return AIRCRAFT_CRUISE_SPEEDS.get(key)


def resolve_cruise_speed(
    cruise_speed_kts: Optional[float] = None,
    aircraft_type: Optional[str] = None,
) -> Tuple[Optional[float], Optional[str]]:
    """
    Resolve cruise speed from explicit value or aircraft type lookup.

    Priority:
    1. Explicit cruise_speed_kts (if provided)
    2. Aircraft type lookup
    3. None (if neither provided or aircraft not found)

    Args:
        cruise_speed_kts: Explicit cruise speed in knots
        aircraft_type: Aircraft type for speed lookup

    Returns:
        Tuple of (speed_kts, source_description)
        - speed_kts: The resolved speed, or None if unknown
        - source_description: How the speed was determined, e.g.:
          - "provided"
          - "typical Cessna 172 cruise (~110-130 kts)"
          - None (if speed unknown)
    """
    # Explicit speed takes precedence
    if cruise_speed_kts is not None:
        return float(cruise_speed_kts), "provided"

    # Try aircraft type lookup
    if aircraft_type:
        info = get_aircraft_info(aircraft_type)
        if info:
            source = f"typical {info['name']} cruise (~{info['range']} kts)"
            return float(info['cruise_kts']), source

    return None, None


def format_time(hours: float) -> str:
    """
    Format flight time in hours to a human-readable string.

    Args:
        hours: Flight time in decimal hours

    Returns:
        Formatted string like "4h 35m" or "45m"
    """
    total_minutes = int(round(hours * 60))
    h = total_minutes // 60
    m = total_minutes % 60

    if h == 0:
        return f"{m}m"
    elif m == 0:
        return f"{h}h"
    else:
        return f"{h}h {m}m"
