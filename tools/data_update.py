#!/usr/bin/env python3
"""
FlyFun Data Update Script

Consolidates all data update commands for different update schedules:
  - initial:  Full build from scratch (run once on new setup)
  - aip:      Update when AIP data changes (run on AIRAC cycle, ~28 days)
  - reviews:  Update GA friendliness from reviews (run weekly/monthly)
  - autorouter: Run autorouter on airports with AIP entries for given countries

Usage:
    python tools/data_update.py initial           # Full initial build
    python tools/data_update.py aip               # Update AIP data only
    python tools/data_update.py reviews           # Update reviews/GA friendliness
    python tools/data_update.py autorouter ED LO  # Run autorouter for countries

Environment:
    Set OPENAI_API_KEY for LLM-based review processing
    Set AIRPORTS_DB to override default database path
"""

import argparse
import gzip
import json
import logging
import os
import sqlite3
import subprocess
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

# =============================================================================
# PATH CONFIGURATION
# =============================================================================

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent

# Database paths
AIRPORTS_DB = Path(os.environ.get("AIRPORTS_DB", PROJECT_ROOT / "data" / "airports.db"))
GA_PERSONA_DB = PROJECT_ROOT / "data" / "ga_persona.db"
WORLDAIRPORTS_DB = PROJECT_ROOT / "data" / "world_airports.db"

# Airfield.directory export (for reviews) - intermediate files in tmp/
AIRFIELD_EXPORT_URL = "https://airfield-directory-pirep-export.s3.amazonaws.com/airfield-directory-pireps-export-latest.json.gz"
AIRFIELD_EXPORT_RAW = PROJECT_ROOT / "tmp" / "airfield_export_raw.json.gz"
AIRFIELD_EXPORT = PROJECT_ROOT / "tmp" / "airfield_export.json"

# Cache directory
CACHE_DIR = PROJECT_ROOT / "cache"

# =============================================================================
# LOGGING SETUP
# =============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="[%(levelname)s] %(asctime)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)


def log_section(title: str) -> None:
    """Print a section header."""
    print()
    print("=" * 64)
    print(f" {title}")
    print("=" * 64)


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================


def run_command(args: list[str], check: bool = True) -> subprocess.CompletedProcess:
    """Run a command and return the result."""
    logger.info(f"Running: {' '.join(args)}")
    return subprocess.run(args, cwd=PROJECT_ROOT, check=check)


def ensure_directories() -> None:
    """Ensure required directories exist."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    AIRPORTS_DB.parent.mkdir(parents=True, exist_ok=True)
    AIRFIELD_EXPORT.parent.mkdir(parents=True, exist_ok=True)


def download_reviews() -> bool:
    """Download latest airfield.directory PIREPs and filter for human-only reviews."""
    log_section("Downloading Airfield.directory Reviews")

    # Download latest export
    logger.info(f"Downloading from: {AIRFIELD_EXPORT_URL}")
    try:
        urllib.request.urlretrieve(AIRFIELD_EXPORT_URL, AIRFIELD_EXPORT_RAW)
    except Exception as e:
        logger.error(f"Download failed: {e}")
        return False

    if not AIRFIELD_EXPORT_RAW.exists():
        logger.error("Download failed - file not created")
        return False

    size_mb = AIRFIELD_EXPORT_RAW.stat().st_size / (1024 * 1024)
    logger.info(f"Downloaded: {size_mb:.1f} MB")

    # Filter out AI-generated PIREPs, keep only human reviews
    logger.info("Filtering for human-only reviews (ai_generated != true)...")

    try:
        with gzip.open(AIRFIELD_EXPORT_RAW, "rt", encoding="utf-8") as f:
            data = json.load(f)

        # Filter: keep only reviews where ai_generated is not true
        filtered_pireps = {}
        for airport_id, reviews in data.get("pireps", {}).items():
            human_reviews = {
                review_id: review
                for review_id, review in reviews.items()
                if not review.get("ai_generated", False)
            }
            if human_reviews:
                filtered_pireps[airport_id] = human_reviews

        filtered_data = {"pireps": filtered_pireps}

        with open(AIRFIELD_EXPORT, "w", encoding="utf-8") as f:
            json.dump(filtered_data, f)

    except Exception as e:
        logger.error(f"Filtering failed: {e}")
        return False

    if not AIRFIELD_EXPORT.exists() or AIRFIELD_EXPORT.stat().st_size == 0:
        logger.error("Filtering failed or produced empty output")
        return False

    # Count airports and reviews
    airport_count = len(filtered_pireps)
    review_count = sum(len(reviews) for reviews in filtered_pireps.values())

    logger.info(f"Filtered export: {airport_count} airports, {review_count} human reviews")
    logger.info(f"Saved to: {AIRFIELD_EXPORT}")

    return True


# =============================================================================
# UPDATE FUNCTIONS
# =============================================================================


def update_aip_data() -> None:
    """Update AIP data from web sources."""
    log_section("Updating AIP Data")

    args = ["python", "tools/aipexport.py"]

    # If database exists, use it as base
    if AIRPORTS_DB.exists():
        logger.info(f"Using existing database as base: {AIRPORTS_DB}")
        args.extend(["--database", str(AIRPORTS_DB)])

    # Enable web sources (France, UK, Norway)
    args.extend(["--france-web", "--uk-web", "--norway-web"])

    # WorldAirports for metadata enrichment
    if WORLDAIRPORTS_DB.exists():
        args.extend([
            "--worldairports",
            "--worldairports-db", str(WORLDAIRPORTS_DB),
            "--worldairports-filter", "required",
        ])

    # Output to database
    args.extend(["--database-storage", str(AIRPORTS_DB)])

    # Cache directory
    args.extend(["-c", str(CACHE_DIR)])

    run_command(args)
    logger.info("AIP data update complete")

    # Show recent changes
    log_section("Recent AIP Changes")
    try:
        run_command(
            ["python", "tools/aipchange.py", "--since", "today", "--summary"],
            check=False,
        )
    except Exception:
        logger.info("No changes to display")


def update_reviews() -> None:
    """Update GA friendliness from reviews."""
    log_section("Updating GA Friendliness / Reviews")

    # Step 1: Download latest reviews
    if not download_reviews():
        raise RuntimeError("Failed to download reviews")

    args = ["python", "tools/build_ga_friendliness.py"]

    # Output database
    args.extend(["--output", str(GA_PERSONA_DB)])

    # Use airports.db for AIP-derived fields
    if AIRPORTS_DB.exists():
        args.extend(["--airports-db", str(AIRPORTS_DB)])

    # Source: the filtered human-only export
    if AIRFIELD_EXPORT.exists():
        logger.info(f"Using filtered export file: {AIRFIELD_EXPORT}")
        args.extend(["--export", str(AIRFIELD_EXPORT)])
    else:
        raise RuntimeError("Download/filtering failed - no export file available")

    # Incremental mode: skip already-processed airports
    args.append("--incremental")

    # Cache directory
    args.extend(["--cache-dir", str(CACHE_DIR / "ga_friendliness")])

    run_command(args)
    logger.info("Reviews update complete")


def update_aip_fields_only() -> None:
    """Fast update: only AIP-derived fields in ga_persona.db."""
    log_section("Updating AIP Fields in GA Persona DB (fast)")

    if not AIRPORTS_DB.exists():
        raise RuntimeError(f"airports.db not found: {AIRPORTS_DB}")

    args = [
        "python", "tools/build_ga_friendliness.py",
        "--aip-only",
        "--airports-db", str(AIRPORTS_DB),
        "--output", str(GA_PERSONA_DB),
    ]

    run_command(args)
    logger.info("AIP fields update complete")


def run_autorouter(prefixes: list[str]) -> None:
    """Run autorouter on all airports with AIP entries matching given prefixes."""
    if not prefixes:
        print("Usage: autorouter <icao_prefix> [prefix2] [prefix3] ...")
        print("Example: autorouter ED           (for Germany)")
        print("Example: autorouter ED LO EB LE  (multiple countries)")
        print()
        print("Common prefixes:")
        print("  ED - Germany    EG - UK        EH - Netherlands")
        print("  EI - Ireland    EL - Luxembourg EB - Belgium")
        print("  LF - France     LI - Italy     LS - Switzerland")
        print("  LO - Austria    LZ - Slovakia  LE - Spain")
        sys.exit(1)

    log_section(f"Running Autorouter for: {' '.join(prefixes)}")

    if not AIRPORTS_DB.exists():
        raise RuntimeError(f"airports.db not found: {AIRPORTS_DB}")

    # Build SQL query for all prefixes
    conditions = " OR ".join(f"airport_icao LIKE '{p}%'" for p in prefixes)
    query = f"SELECT DISTINCT airport_icao FROM aip_entries WHERE {conditions} ORDER BY airport_icao"

    # Query airports
    with sqlite3.connect(AIRPORTS_DB) as conn:
        cursor = conn.execute(query)
        airports = [row[0] for row in cursor.fetchall()]

    if not airports:
        raise RuntimeError(f"No airports found with AIP entries matching: {' '.join(prefixes)}")

    logger.info(f"Found {len(airports)} airports with AIP entries")

    # Build args for aipexport.py with autorouter
    args = [
        "python", "tools/aipexport.py",
        "--autorouter",
        "--database", str(AIRPORTS_DB),
        "--database-storage", str(AIRPORTS_DB),
        "-c", str(CACHE_DIR),
    ]

    # Add all airport ICAOs
    args.extend(airports)

    run_command(args)

    log_section("Autorouter Complete")
    logger.info(f"Processed: {len(airports)} airports")


def initial_build() -> None:
    """Full initial build from scratch."""
    log_section("INITIAL BUILD - Full Setup")

    logger.info("This will build all data from scratch")
    logger.info("  - AIP data from France, UK, Norway web sources")
    logger.info("  - GA friendliness database")

    # Step 1: Build AIP data
    update_aip_data()

    # Step 2: Build GA friendliness
    update_reviews()

    log_section("INITIAL BUILD COMPLETE")
    logger.info(f"Databases created:")
    logger.info(f"  - {AIRPORTS_DB}")
    logger.info(f"  - {GA_PERSONA_DB}")


# =============================================================================
# MAIN
# =============================================================================


def main() -> None:
    parser = argparse.ArgumentParser(
        description="FlyFun Data Update Script",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Modes:
  initial      Full build from scratch (first time setup)
  aip          Update AIP data only (run on AIRAC cycle, ~28 days)
  reviews      Update GA friendliness/reviews (run weekly/monthly)
  aip-fields   Fast AIP-only update to ga_persona.db
  autorouter   Run autorouter on airports with AIP for given country prefixes

Examples:
  python tools/data_update.py initial
  python tools/data_update.py aip
  python tools/data_update.py reviews
  python tools/data_update.py aip-fields
  python tools/data_update.py autorouter ED
  python tools/data_update.py autorouter ED LO EB LE
        """,
    )

    parser.add_argument(
        "mode",
        choices=["initial", "aip", "reviews", "aip-fields", "autorouter"],
        help="Update mode to run",
    )
    parser.add_argument(
        "args",
        nargs="*",
        help="Additional arguments (e.g., ICAO prefixes for autorouter)",
    )

    args = parser.parse_args()

    ensure_directories()

    if args.mode == "initial":
        initial_build()
    elif args.mode == "aip":
        update_aip_data()
        # Also sync AIP fields to ga_persona.db
        if GA_PERSONA_DB.exists():
            update_aip_fields_only()
    elif args.mode == "reviews":
        update_reviews()
    elif args.mode == "aip-fields":
        update_aip_fields_only()
    elif args.mode == "autorouter":
        run_autorouter(args.args)


if __name__ == "__main__":
    main()
