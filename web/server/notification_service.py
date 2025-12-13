"""
Notification Service - Provides parsed notification summaries.

Integrates with ga_notifications.db for French airports.
"""

import sqlite3
import os
from typing import Optional, Dict, Any
from pathlib import Path
import logging

logger = logging.getLogger(__name__)


class NotificationService:
    """Service to lookup parsed notification requirements."""
    
    def __init__(self, db_path: str = None):
        if db_path is None:
            from shared.aviation_agent.config import get_ga_notifications_db_path
            db_path = get_ga_notifications_db_path()
        self.db_path = db_path
        self._check_db()
    
    def _check_db(self):
        """Check if database exists."""
        if not os.path.exists(self.db_path):
            logger.warning(f"Notification database not found: {self.db_path}")
            self.db_available = False
        else:
            self.db_available = True
            logger.info(f"Notification database loaded: {self.db_path}")
    
    def get_notification_summary(self, icao: str) -> Optional[Dict[str, Any]]:
        """
        Get parsed notification summary for an airport.
        
        Returns dict with summary, contact_info, confidence, etc.
        Returns None if not found or database unavailable.
        """
        if not self.db_available:
            return None
        
        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            
            cursor = conn.execute('''
                SELECT 
                    icao, rule_type, notification_type, hours_notice,
                    operating_hours_start, operating_hours_end,
                    weekday_rules, schengen_rules, contact_info,
                    summary, confidence
                FROM ga_notification_requirements
                WHERE icao = ?
            ''', (icao.upper(),))
            
            row = cursor.fetchone()
            conn.close()
            
            if row:
                return {
                    "icao": row["icao"],
                    "rule_type": row["rule_type"],
                    "notification_type": row["notification_type"],
                    "hours_notice": row["hours_notice"],
                    "operating_hours_start": row["operating_hours_start"],
                    "operating_hours_end": row["operating_hours_end"],
                    "weekday_rules": row["weekday_rules"],
                    "schengen_rules": row["schengen_rules"],
                    "contact_info": row["contact_info"],
                    "summary": row["summary"],
                    "confidence": row["confidence"],
                    "parsed": True
                }
            return None
            
        except Exception as e:
            logger.error(f"Error fetching notification for {icao}: {e}")
            return None
    
    def has_parsed_notification(self, icao: str) -> bool:
        """Check if airport has a parsed notification summary."""
        return self.get_notification_summary(icao) is not None


# Global instance
_notification_service: Optional[NotificationService] = None


def get_notification_service() -> NotificationService:
    """Get or create the notification service singleton."""
    global _notification_service
    if _notification_service is None:
        _notification_service = NotificationService()
    return _notification_service
