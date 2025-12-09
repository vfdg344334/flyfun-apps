"""
Batch processor for extracting notification requirements.

Processes all airports and stores results in SQLite database.
"""

import os
import sqlite3
import json
import httpx
import time
import logging
from datetime import datetime
from typing import List, Tuple, Optional, Dict, Any
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

logger = logging.getLogger(__name__)


class NotificationBatchProcessor:
    """Process notification requirements for airports using LLM.
    
    Configure via environment variables:
    - LLM_API_BASE: API endpoint (e.g., https://api.example.com/v1/chat/completions)
    - LLM_MODEL: Model name to use
    - LLM_API_KEY: API key for authentication
    """
    
    SYSTEM_PROMPT = '''You are an aviation expert. Extract notification requirements and return JSON.

The "summary" field MUST be formatted exactly like this for UI display:
Line 1: Weekday rules | Weekend rules  
Line 2: Schengen info (if applicable) | Hours: HH:MM-HH:MM
Line 3: 📞 phone number (if available)
Line 4: 📧 email address (if available)

Example summary:
"Mon-Fri: 24h notice | Sat-Sun/HOL: 48h notice
Non-Schengen only | Hours: 07:00-19:00
📞 09 70 27 51 53
📧 bse-saint-malo@douane.finances.gouv.fr"

Return JSON:
{
    "reasoning": "Step-by-step analysis",
    "rule_type": "customs" or "immigration",
    "notification_type": "hours" or "h24" or "on_request" or "business_day" or "as_ad_hours",
    "hours_notice": max hours required (integer or null),
    "operating_hours_start": "HHMM" or null,
    "operating_hours_end": "HHMM" or null,
    "weekday_rules": {"Mon-Fri": "...", "Sat-Sun": "..."},
    "schengen_rules": {"schengen_only": bool, "non_schengen_only": bool},
    "contact_info": {"phone": "...", "email": "..."},
    "summary": "Formatted multi-line summary for UI (include schengen info)",
    "confidence": 0.0-1.0
}'''
    
    def __init__(self, output_db_path: str, api_key: str = None, api_base: str = None, model: str = None):
        self.api_base = api_base or os.environ.get("LLM_API_BASE")
        self.model = model or os.environ.get("LLM_MODEL")
        self.api_key = api_key or os.environ.get("LLM_API_KEY")
        
        if not self.api_base:
            raise ValueError("LLM_API_BASE not set")
        if not self.model:
            raise ValueError("LLM_MODEL not set")
        if not self.api_key:
            raise ValueError("LLM_API_KEY not set")
        
        self.output_db_path = output_db_path
        self._init_db()
    
    def _init_db(self):
        """Initialize the output database."""
        conn = sqlite3.connect(self.output_db_path)
        conn.execute('''
            CREATE TABLE IF NOT EXISTS ga_notification_requirements (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                icao TEXT NOT NULL,
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
                llm_response TEXT,
                created_utc TEXT,
                UNIQUE(icao, rule_type)
            )
        ''')
        conn.commit()
        conn.close()
    
    def extract_one(self, icao: str, text: str) -> Dict[str, Any]:
        """Extract notification requirements for one airport."""
        prompt = f"Airport: {icao}\nText: {text}"
        
        try:
            response = httpx.post(
                self.api_base,
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": "application/json"
                },
                json={
                    "model": self.model,
                    "messages": [
                        {"role": "system", "content": self.SYSTEM_PROMPT},
                        {"role": "user", "content": prompt}
                    ],
                    "temperature": 0
                },
                timeout=60.0
            )
            response.raise_for_status()
            
            llm_response = response.json()["choices"][0]["message"]["content"]
            
            # Parse JSON
            content = llm_response
            if "```" in content:
                content = content.split("```")[1]
                if content.startswith("json"):
                    content = content[4:]
            parsed = json.loads(content.strip())
            parsed["llm_response"] = llm_response
            parsed["raw_text"] = text
            return parsed
            
        except Exception as e:
            logger.error(f"Failed to extract {icao}: {e}")
            return {
                "rule_type": None,
                "notification_type": None,
                "hours_notice": None,
                "operating_hours_start": None,
                "operating_hours_end": None,
                "weekday_rules": None,
                "schengen_rules": None,
                "contact_info": None,
                "summary": f"Extraction failed: {e}",
                "raw_text": text,
                "confidence": 0.0,
                "llm_response": str(e)
            }
    
    def save_result(self, icao: str, result: Dict[str, Any]):
        """Save extraction result to database."""
        conn = sqlite3.connect(self.output_db_path)
        
        conn.execute('''
            INSERT OR REPLACE INTO ga_notification_requirements 
            (icao, rule_type, notification_type, hours_notice, 
             operating_hours_start, operating_hours_end,
             weekday_rules, schengen_rules, contact_info,
             summary, raw_text, confidence, llm_response, created_utc)
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
            result.get("llm_response"),
            datetime.utcnow().isoformat()
        ))
        conn.commit()
        conn.close()
    
    def process_airports(
        self, 
        airports_db_path: str, 
        icao_prefix: str = None,
        limit: int = None,
        delay: float = 0.5
    ) -> Dict[str, Any]:
        """Process airports from source database."""
        
        # Get airports to process
        conn = sqlite3.connect(airports_db_path)
        conn.row_factory = sqlite3.Row
        
        query = "SELECT airport_icao, value FROM aip_entries WHERE std_field_id = 302 AND value IS NOT NULL"
        params = []
        
        if icao_prefix:
            query += " AND airport_icao LIKE ?"
            params.append(f"{icao_prefix}%")
        
        query += " ORDER BY airport_icao"
        
        if limit:
            query += " LIMIT ?"
            params.append(limit)
        
        cursor = conn.execute(query, params)
        airports = [(row["airport_icao"], row["value"]) for row in cursor]
        conn.close()
        
        print(f"Processing {len(airports)} airports...")
        
        success = 0
        failed = 0
        
        for i, (icao, text) in enumerate(airports):
            print(f"[{i+1}/{len(airports)}] {icao}...", end=" ")
            
            result = self.extract_one(icao, text)
            self.save_result(icao, result)
            
            if result.get("confidence", 0) > 0:
                success += 1
                print(f"✓ {result.get('notification_type')} ({result.get('confidence'):.2f})")
            else:
                failed += 1
                print(f"✗ Failed")
            
            if delay and i < len(airports) - 1:
                time.sleep(delay)
        
        return {
            "total": len(airports),
            "success": success,
            "failed": failed
        }


def process_french_airports():
    """Process all French airports (LF* prefix)."""
    airports_db = "/home/qian/dev/022_Home/flyfun-apps/web/server/airports.db"
    output_db = "/tmp/ga_notifications.db"
    
    # Will read LLM_API_BASE, LLM_MODEL, LLM_API_KEY from environment
    processor = NotificationBatchProcessor(output_db)
    stats = processor.process_airports(airports_db, icao_prefix="LF", delay=0.3)
    
    print(f"\n=== Summary ===")
    print(f"Total: {stats['total']}")
    print(f"Success: {stats['success']}")
    print(f"Failed: {stats['failed']}")
    print(f"Output: {output_db}")


if __name__ == "__main__":
    process_french_airports()
