#!/usr/bin/env python3
"""
CLI tool for building GA notification requirements database.

Extracts structured notification rules from AIP customs/immigration text
and stores them in ga_notifications.db.

This tool produces FACTUAL data extracted from AIP:
- ga_notifications.db: Detailed, structured notification rules (immutable truth)

For subjective scoring (hassle scores), see build_ga_friendliness.py which writes
to ga_persona.db.

Usage:
    # Full rebuild (all airports with AIP data)
    python tools/build_ga_notifications.py

    # Filter by country prefixes
    python tools/build_ga_notifications.py --prefixes LF,EG,ED

    # Filter by specific airports
    python tools/build_ga_notifications.py --icaos LFRG,LFPT,EGLL

    # Incremental: skip airports already in output DB
    python tools/build_ga_notifications.py --incremental

    # Changed-only: only process airports where AIP text changed
    python tools/build_ga_notifications.py --changed

    # Force rebuild specific airports (even if unchanged)
    python tools/build_ga_notifications.py --icaos LFRG --force

Configuration:
    Uses configs/ga_notification_agent/default.json for behavior settings.
    Set OPENAI_API_KEY environment variable for LLM fallback on complex rules.
"""

import argparse
import logging
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from shared.ga_notification_agent import NotificationParser
from shared.ga_notification_agent.batch_processor import NotificationBatchProcessor
from shared.ga_notification_agent.config import get_notification_config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Build GA notification requirements database from AIP data",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    # Source options
    source_group = parser.add_argument_group("Source options")
    source_group.add_argument(
        "--airports-db",
        type=Path,
        default=Path("data/airports.db"),
        help="Path to airports.db source database (default: data/airports.db)",
    )

    # Output options
    output_group = parser.add_argument_group("Output options")
    output_group.add_argument(
        "--output", "-o",
        type=Path,
        default=Path("data/ga_notifications.db"),
        help="Output database path (default: data/ga_notifications.db)",
    )

    # Filter options
    filter_group = parser.add_argument_group("Filter options")
    filter_group.add_argument(
        "--prefixes",
        type=str,
        help="Comma-separated ICAO prefixes (e.g., LF,EG,ED for France, UK, Germany)",
    )
    filter_group.add_argument(
        "--prefix",
        type=str,
        help="Single ICAO prefix filter (e.g., LF for France) - deprecated, use --prefixes",
    )
    filter_group.add_argument(
        "--icaos",
        type=str,
        help="Comma-separated list of specific ICAOs to process",
    )
    filter_group.add_argument(
        "--limit",
        type=int,
        help="Maximum number of airports to process",
    )

    # Processing options
    proc_group = parser.add_argument_group("Processing options")
    proc_group.add_argument(
        "--incremental", "-i",
        action="store_true",
        help="Skip airports already in output DB (fast, but misses AIP updates)",
    )
    proc_group.add_argument(
        "--changed", "-c",
        action="store_true",
        help="Only process airports where AIP text changed since last run",
    )
    proc_group.add_argument(
        "--force", "-f",
        action="store_true",
        help="Force reprocessing even if data unchanged (use with --icaos)",
    )
    proc_group.add_argument(
        "--delay",
        type=float,
        default=0.5,
        help="Delay between processing (seconds, default: 0.5)",
    )
    proc_group.add_argument(
        "--config",
        type=str,
        default="default",
        help="Config name to use (default: default)",
    )

    # LLM options
    llm_group = parser.add_argument_group("LLM options")
    llm_group.add_argument(
        "--no-llm",
        action="store_true",
        help="Disable LLM fallback (regex-only parsing)",
    )
    llm_group.add_argument(
        "--llm-model",
        type=str,
        help="Override LLM model from config",
    )

    # Output options
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Verbose output",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be processed without writing to database",
    )

    return parser.parse_args()


def main() -> int:
    """Main entry point."""
    args = parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Validate source database
    if not args.airports_db.exists():
        logger.error(f"Airports database not found: {args.airports_db}")
        return 1

    # Parse ICAOs if specified
    icaos = None
    if args.icaos:
        icaos = [icao.strip().upper() for icao in args.icaos.split(",")]

    # Parse prefixes (support both --prefixes and deprecated --prefix)
    prefixes = None
    if args.prefixes:
        prefixes = [p.strip().upper() for p in args.prefixes.split(",")]
    elif args.prefix:
        prefixes = [args.prefix.strip().upper()]

    # Validate conflicting options
    if args.incremental and args.changed:
        logger.error("Cannot use both --incremental and --changed")
        return 1
    if args.force and not icaos:
        logger.warning("--force has no effect without --icaos")

    # Load config
    config = get_notification_config(args.config)

    # Override LLM settings if requested
    if args.no_llm:
        config.parsing.use_llm_fallback = False
    if args.llm_model:
        config.llm.model = args.llm_model

    # Determine processing mode
    if args.force:
        mode = "force"
    elif args.changed:
        mode = "changed"
    elif args.incremental:
        mode = "incremental"
    else:
        mode = "full"

    logger.info(f"Source database: {args.airports_db}")
    logger.info(f"Output database: {args.output}")
    logger.info(f"Config: {args.config}")
    logger.info(f"LLM fallback: {config.parsing.use_llm_fallback}")
    logger.info(f"Mode: {mode}")
    if prefixes:
        logger.info(f"ICAO prefixes: {prefixes}")
    if icaos:
        logger.info(f"Specific ICAOs: {icaos}")
    if args.limit:
        logger.info(f"Limit: {args.limit}")

    if args.dry_run:
        logger.info("DRY RUN MODE - no database writes")
        # For dry run, just count what would be processed
        import sqlite3
        conn = sqlite3.connect(args.airports_db)
        conn.row_factory = sqlite3.Row

        query = "SELECT COUNT(*) FROM aip_entries WHERE std_field_id = 302 AND value IS NOT NULL"
        params = []

        if icaos:
            placeholders = ",".join("?" for _ in icaos)
            query = f"SELECT COUNT(*) FROM aip_entries WHERE std_field_id = 302 AND value IS NOT NULL AND airport_icao IN ({placeholders})"
            params.extend(icaos)
        elif prefixes:
            prefix_conditions = " OR ".join("airport_icao LIKE ?" for _ in prefixes)
            query += f" AND ({prefix_conditions})"
            params.extend(f"{p}%" for p in prefixes)

        cursor = conn.execute(query, params)
        count = cursor.fetchone()[0]
        conn.close()

        logger.info(f"Would process {count} airports")
        return 0

    # Ensure output directory exists
    args.output.parent.mkdir(parents=True, exist_ok=True)

    # Create processor
    processor = NotificationBatchProcessor(
        output_db_path=args.output,
        config=config,
    )

    # Process airports
    try:
        stats = processor.process_airports(
            airports_db_path=args.airports_db,
            icao_prefixes=prefixes,
            icaos=icaos,
            limit=args.limit,
            delay=args.delay,
            mode=mode,
        )

        # Print summary
        print("\n" + "=" * 60)
        print("BUILD SUMMARY")
        print("=" * 60)
        print(f"Total airports: {stats['total']}")
        print(f"Successful: {stats['success']}")
        print(f"Failed: {stats['failed']}")
        print(f"Skipped (no rules): {stats['skipped']}")
        if stats.get('unchanged'):
            print(f"Unchanged (skipped): {stats['unchanged']}")
        print(f"Output: {args.output}")

        return 0 if stats['failed'] == 0 else 1

    except Exception as e:
        logger.exception(f"Build failed: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
