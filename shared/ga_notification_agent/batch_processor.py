"""
Batch processor for extracting notification requirements.

Processes airports from airports.db and stores detailed results in ga_notifications.db.
This module writes FACTUAL extracted data (the "truth" from AIP).

For the CLI tool, see tools/build_ga_notifications.py
For scoring/hassle computation, see scorer.py (writes to ga_persona.db)
"""

import sqlite3
import json
import logging
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, Optional, List

from .config import get_notification_config, NotificationAgentConfig
from .parser import NotificationParser
from .models import ParsedNotificationRules

logger = logging.getLogger(__name__)


class NotificationBatchProcessor:
    """
    Process notification requirements for airports using NotificationParser.

    Uses the unified NotificationParser for extraction (regex + optional LLM fallback).
    Stores detailed results in ga_notifications.db for the NotificationService to query.

    Configuration is loaded from configs/ga_notification_agent/default.json.
    """

    def __init__(
        self,
        output_db_path: Path,
        config: Optional[NotificationAgentConfig] = None,
        config_name: str = "default",
    ):
        """
        Initialize batch processor.

        Args:
            output_db_path: Path to output database (ga_notifications.db)
            config: Pre-loaded config (optional)
            config_name: Name of config to load if config not provided
        """
        if config is None:
            config = get_notification_config(config_name)

        self._config = config
        self.output_db_path = Path(output_db_path)

        # Initialize parser with config
        self._parser = NotificationParser(config=config)

        # Initialize database
        self._init_db()

    def _init_db(self) -> None:
        """Initialize the output database schema."""
        conn = sqlite3.connect(self.output_db_path)
        conn.execute('''
            CREATE TABLE IF NOT EXISTS ga_notification_requirements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                icao TEXT NOT NULL UNIQUE,
                rule_type TEXT,
                notification_type TEXT,
                hours_notice INTEGER,
                operating_hours_start TEXT,
                operating_hours_end TEXT,
                weekday_rules TEXT,
                schengen_rules TEXT,
                contact_info TEXT,
                summary TEXT,
                raw_text TEXT,
                confidence REAL,
                extraction_method TEXT,
                created_utc TEXT
            )
        ''')

        # Schema migration: add extraction_method if missing (old schema had llm_response)
        cursor = conn.execute("PRAGMA table_info(ga_notification_requirements)")
        columns = {row[1] for row in cursor}
        if "extraction_method" not in columns:
            conn.execute("ALTER TABLE ga_notification_requirements ADD COLUMN extraction_method TEXT")
            logger.info("Migrated schema: added extraction_method column")

        conn.commit()
        conn.close()

    def _parsed_to_db_record(
        self, icao: str, parsed: ParsedNotificationRules
    ) -> Dict[str, Any]:
        """Convert ParsedNotificationRules to database record format."""
        if not parsed.rules:
            return {
                "icao": icao,
                "rule_type": None,
                "notification_type": None,
                "hours_notice": None,
                "weekday_rules": None,
                "schengen_rules": None,
                "summary": parsed.get_summary() if parsed.rules else "No rules found",
                "raw_text": parsed.raw_text,
                "confidence": 0.0,
                "extraction_method": "none",
            }

        # Aggregate rules into a single record
        # Take the dominant rule type
        rule_types = [r.rule_type.value for r in parsed.rules]
        dominant_rule_type = max(set(rule_types), key=rule_types.count)

        # Determine notification type from rules
        # Priority: actionable types > not_available (unless ALL are not_available)
        # Filter out NOT_AVAILABLE rules that only apply to specific flight types
        actionable_rules = [
            r for r in parsed.rules
            if r.notification_type.value != "not_available"
        ]

        if actionable_rules:
            # Use actionable rules to determine dominant type
            notification_types = [r.notification_type.value for r in actionable_rules]
            dominant_notif_type = max(set(notification_types), key=notification_types.count)
            # Get max hours from actionable rules
            hours_notices = [r.hours_notice for r in actionable_rules if r.hours_notice]
        else:
            # All rules are not_available
            notification_types = [r.notification_type.value for r in parsed.rules]
            dominant_notif_type = "not_available"
            hours_notices = []

        # Max hours notice across relevant rules
        max_hours = max(hours_notices) if hours_notices else None

        # Build weekday rules dict
        weekday_rules = {}
        for rule in parsed.rules:
            if rule.weekday_start is not None:
                days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                start = days[rule.weekday_start]
                end = days[rule.weekday_end] if rule.weekday_end is not None else start
                key = f"{start}-{end}" if start != end else start
                if rule.includes_holidays:
                    key += "/HOL"
                value = f"{rule.hours_notice}h" if rule.hours_notice else rule.notification_type.value
                weekday_rules[key] = value

        # Build Schengen rules
        schengen_rules = {
            "schengen_only": any(r.schengen_only for r in parsed.rules),
            "non_schengen_only": any(r.non_schengen_only for r in parsed.rules),
        }

        # Average confidence
        avg_confidence = sum(r.confidence for r in parsed.rules) / len(parsed.rules)

        # Extraction method
        methods = [r.extraction_method or "regex" for r in parsed.rules]
        method = "llm" if "llm" in methods else "regex"

        return {
            "icao": icao,
            "rule_type": dominant_rule_type,
            "notification_type": dominant_notif_type,
            "hours_notice": max_hours,
            "weekday_rules": weekday_rules if weekday_rules else None,
            "schengen_rules": schengen_rules if any(schengen_rules.values()) else None,
            "summary": parsed.get_summary(),
            "raw_text": parsed.raw_text,
            "confidence": avg_confidence,
            "extraction_method": method,
        }

    def save_result(self, icao: str, result: Dict[str, Any]) -> None:
        """Save extraction result to database."""
        conn = sqlite3.connect(self.output_db_path)

        conn.execute('''
            INSERT OR REPLACE INTO ga_notification_requirements
            (icao, rule_type, notification_type, hours_notice,
             operating_hours_start, operating_hours_end,
             weekday_rules, schengen_rules, contact_info,
             summary, raw_text, confidence, extraction_method, created_utc)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            icao,
            result.get("rule_type"),
            result.get("notification_type"),
            result.get("hours_notice"),
            result.get("operating_hours_start"),
            result.get("operating_hours_end"),
            json.dumps(result.get("weekday_rules")) if result.get("weekday_rules") else None,
            json.dumps(result.get("schengen_rules")) if result.get("schengen_rules") else None,
            json.dumps(result.get("contact_info")) if result.get("contact_info") else None,
            result.get("summary"),
            result.get("raw_text"),
            result.get("confidence"),
            result.get("extraction_method"),
            datetime.now(timezone.utc).isoformat()
        ))
        conn.commit()
        conn.close()

    def _get_existing_data(self) -> Dict[str, str]:
        """Get existing ICAO -> raw_text mapping from output database."""
        if not self.output_db_path.exists():
            return {}

        conn = sqlite3.connect(self.output_db_path)
        cursor = conn.execute("SELECT icao, raw_text FROM ga_notification_requirements")
        existing = {row[0]: row[1] for row in cursor}
        conn.close()
        return existing

    def process_airports(
        self,
        airports_db_path: Path,
        icao_prefixes: Optional[List[str]] = None,
        icaos: Optional[List[str]] = None,
        limit: Optional[int] = None,
        delay: float = 0.5,
        mode: str = "full",
    ) -> Dict[str, Any]:
        """
        Process airports from source database.

        Args:
            airports_db_path: Path to airports.db
            icao_prefixes: Filter by ICAO prefixes (e.g., ["LF", "EG"] for France, UK)
            icaos: Specific ICAOs to process (overrides prefixes)
            limit: Max airports to process
            delay: Delay between LLM calls (seconds)
            mode: Processing mode:
                - "full": Process all matching airports (default)
                - "incremental": Skip airports already in output DB
                - "changed": Only process airports where AIP text changed
                - "force": Process all, even if unchanged (same as full)

        Returns:
            Dict with processing statistics
        """
        # Get airports to process from source
        conn = sqlite3.connect(airports_db_path)
        conn.row_factory = sqlite3.Row

        query = "SELECT airport_icao, value FROM aip_entries WHERE std_field_id = 302 AND value IS NOT NULL"
        params: List[Any] = []

        if icaos:
            placeholders = ",".join("?" for _ in icaos)
            query += f" AND airport_icao IN ({placeholders})"
            params.extend(icaos)
        elif icao_prefixes:
            prefix_conditions = " OR ".join("airport_icao LIKE ?" for _ in icao_prefixes)
            query += f" AND ({prefix_conditions})"
            params.extend(f"{p}%" for p in icao_prefixes)

        query += " ORDER BY airport_icao"

        if limit:
            query += " LIMIT ?"
            params.append(limit)

        cursor = conn.execute(query, params)
        airports = [(row["airport_icao"], row["value"]) for row in cursor]
        conn.close()

        original_count = len(airports)
        unchanged_count = 0

        # Apply mode filtering
        if mode == "incremental":
            # Skip airports that already exist in output DB
            existing = self._get_existing_data()
            airports = [(icao, text) for icao, text in airports if icao not in existing]
            logger.info(f"Incremental mode: {original_count} → {len(airports)} airports (skipped {original_count - len(airports)} existing)")

        elif mode == "changed":
            # Only process airports where AIP text changed
            existing = self._get_existing_data()
            changed_airports = []
            for icao, text in airports:
                if icao not in existing:
                    # New airport
                    changed_airports.append((icao, text))
                elif existing[icao] != text:
                    # Text changed
                    changed_airports.append((icao, text))
                    logger.debug(f"{icao}: AIP text changed, will reprocess")
                else:
                    unchanged_count += 1
            airports = changed_airports
            logger.info(f"Changed mode: {original_count} → {len(airports)} airports ({unchanged_count} unchanged, skipped)")

        # mode == "full" or "force": process all

        logger.info(f"Processing {len(airports)} airports...")

        success = 0
        failed = 0
        skipped = 0

        for i, (icao, text) in enumerate(airports):
            logger.info(f"[{i+1}/{len(airports)}] {icao}...")

            try:
                # Parse using NotificationParser
                parsed = self._parser.parse(icao, text)

                # Convert to DB record format
                result = self._parsed_to_db_record(icao, parsed)

                # Save to database
                self.save_result(icao, result)

                if result.get("confidence", 0) > 0:
                    success += 1
                    logger.info(f"  ✓ {result.get('notification_type')} ({result.get('confidence'):.2f})")
                else:
                    skipped += 1
                    logger.info(f"  ○ No rules found")

            except Exception as e:
                failed += 1
                logger.error(f"  ✗ Failed: {e}")

            # Delay between processing (mainly for LLM rate limiting)
            if delay and i < len(airports) - 1:
                time.sleep(delay)

        return {
            "total": len(airports),
            "success": success,
            "failed": failed,
            "skipped": skipped,
            "unchanged": unchanged_count,
        }
