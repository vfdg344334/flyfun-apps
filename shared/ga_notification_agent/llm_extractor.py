"""
LLM-based notification extractor.

Uses hybrid approach: LLM for understanding + regex for validation.
"""

import os
import json
import httpx
import logging
from typing import List, Optional, Dict, Any
from dataclasses import dataclass, asdict
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

logger = logging.getLogger(__name__)


@dataclass
class ExtractedRule:
    """Single extracted notification rule."""
    rule_type: str  # ppr, customs, immigration
    notification_type: str  # hours, h24, on_request, business_day, as_ad_hours, not_available
    hours_notice: Optional[int] = None
    weekday_start: Optional[int] = None  # 0=Monday, 6=Sunday
    weekday_end: Optional[int] = None
    operating_hours_start: Optional[str] = None  # e.g., "0600"
    operating_hours_end: Optional[str] = None  # e.g., "2000"
    specific_time: Optional[str] = None
    schengen_only: bool = False
    non_schengen_only: bool = False
    includes_holidays: bool = False
    summary: str = ""


@dataclass
class ExtractedNotification:
    """Complete extraction result for an airport."""
    icao: str
    rules: List[ExtractedRule]
    operating_hours: Optional[str] = None
    contact_phone: Optional[str] = None
    contact_email: Optional[str] = None
    summary: str = ""
    confidence: float = 0.0
    raw_text: str = ""


class LLMNotificationExtractor:
    """
    Extract notification requirements using LLM.
    
    Uses an OpenAI-compatible API. Configure via environment variables:
    - LLM_API_BASE: API endpoint (e.g., https://api.example.com/v1/chat/completions)
    - LLM_MODEL: Model name to use
    - LLM_API_KEY: API key for authentication
    """
    
    SYSTEM_PROMPT = """You are an aviation expert extracting structured notification requirements from AIP (Aeronautical Information Publication) text.

Extract ALL notification rules from the customs/immigration text. Return a JSON object with this structure:

{
    "rules": [
        {
            "rule_type": "customs" or "immigration" or "ppr",
            "notification_type": "h24" or "hours" or "on_request" or "business_day" or "as_ad_hours" or "not_available",
            "hours_notice": null or integer (24, 48, etc.),
            "weekday_start": null or 0-6 (0=Monday, 6=Sunday),
            "weekday_end": null or 0-6,
            "operating_hours_start": null or "HHMM" (e.g., "0600"),
            "operating_hours_end": null or "HHMM" (e.g., "2000"),
            "specific_time": null or "HHMM" (deadline time),
            "schengen_only": false or true,
            "non_schengen_only": false or true,
            "includes_holidays": false or true,
            "summary": "brief description of this rule"
        }
    ],
    "operating_hours": "overall operating hours if mentioned, e.g., '0600-2000'",
    "contact_phone": "phone number if mentioned",
    "contact_email": "email if mentioned",
    "summary": "brief overall summary",
    "confidence": 0.0 to 1.0
}

Key patterns to recognise:
- H24 = available 24 hours, no prior notice needed
- HS = as schedule, HX = as hours (similar to as_ad_hours)
- O/R = on request
- PPR = prior permission required
- PN = prior notice
- "24 HR" = 24 hours notice
- "last working day" = business_day notification
- Times in parentheses like "0600 (0500)" often indicate UTC vs local time

Be precise and extract ALL rules, including different rules for weekdays vs weekends, and Schengen vs non-Schengen flights."""

    def __init__(self, api_key: str = None, api_base: str = None, model: str = None):
        self.api_base = api_base or os.environ.get("LLM_API_BASE")
        self.model = model or os.environ.get("LLM_MODEL")
        self.api_key = api_key or os.environ.get("LLM_API_KEY")
        
        if not self.api_base:
            raise ValueError("LLM_API_BASE not set")
        if not self.model:
            raise ValueError("LLM_MODEL not set")
        if not self.api_key:
            raise ValueError("LLM_API_KEY not set")
    
    def extract(self, icao: str, text: str) -> ExtractedNotification:
        """Extract structured notification rules from text."""
        if not text or not text.strip():
            return ExtractedNotification(
                icao=icao,
                rules=[],
                summary="Empty text",
                confidence=0.0,
                raw_text=text or ""
            )
        
        prompt = f"""Airport: {icao}
Customs/Immigration text:
{text}

Extract all notification rules as JSON."""

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
            
            data = response.json()
            content = data["choices"][0]["message"]["content"]
            
            # Parse JSON response - handle markdown code blocks
            content = content.strip()
            if content.startswith("```json"):
                content = content[7:]
            if content.startswith("```"):
                content = content[3:]
            if content.endswith("```"):
                content = content[:-3]
            content = content.strip()
            
            # Parse JSON response
            parsed = json.loads(content)
            
            # Convert to dataclass
            rules = []
            for r in parsed.get("rules", []):
                rules.append(ExtractedRule(
                    rule_type=r.get("rule_type", "customs"),
                    notification_type=r.get("notification_type", "unknown"),
                    hours_notice=r.get("hours_notice"),
                    weekday_start=r.get("weekday_start"),
                    weekday_end=r.get("weekday_end"),
                    operating_hours_start=r.get("operating_hours_start"),
                    operating_hours_end=r.get("operating_hours_end"),
                    specific_time=r.get("specific_time"),
                    schengen_only=r.get("schengen_only", False),
                    non_schengen_only=r.get("non_schengen_only", False),
                    includes_holidays=r.get("includes_holidays", False),
                    summary=r.get("summary", "")
                ))
            
            return ExtractedNotification(
                icao=icao,
                rules=rules,
                operating_hours=parsed.get("operating_hours"),
                contact_phone=parsed.get("contact_phone"),
                contact_email=parsed.get("contact_email"),
                summary=parsed.get("summary", ""),
                confidence=parsed.get("confidence", 0.8),
                raw_text=text
            )
            
        except Exception as e:
            logger.error(f"LLM extraction failed for {icao}: {e}")
            return ExtractedNotification(
                icao=icao,
                rules=[],
                summary=f"Extraction failed: {e}",
                confidence=0.0,
                raw_text=text
            )


def test_samples(n: int = 10):
    """Test LLM extraction on n sample entries."""
    import sqlite3
    
    # Connect to database
    db_path = "/home/qian/dev/022_Home/flyfun-apps/web/server/airports.db"
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    
    # Get samples
    cursor = conn.execute("""
        SELECT airport_icao, value 
        FROM aip_entries 
        WHERE std_field_id = 302 AND value IS NOT NULL
        ORDER BY RANDOM()
        LIMIT ?
    """, (n,))
    
    samples = [(row["airport_icao"], row["value"]) for row in cursor]
    conn.close()
    
    # Initialize extractor - will read from environment variables
    extractor = LLMNotificationExtractor()
    
    # Process samples
    results = []
    for icao, text in samples:
        print(f"\n{'='*60}")
        print(f"[{icao}] Raw text:")
        print(text[:300] + ("..." if len(text) > 300 else ""))
        print("-" * 40)
        
        result = extractor.extract(icao, text)
        results.append(result)
        
        print(f"Extracted {len(result.rules)} rules (confidence: {result.confidence:.2f})")
        print(f"Summary: {result.summary}")
        
        for i, rule in enumerate(result.rules, 1):
            print(f"  Rule {i}: {rule.notification_type}", end="")
            if rule.hours_notice:
                print(f" ({rule.hours_notice}h)", end="")
            if rule.weekday_start is not None:
                days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                day_range = f"{days[rule.weekday_start]}"
                if rule.weekday_end is not None:
                    day_range += f"-{days[rule.weekday_end]}"
                print(f" [{day_range}]", end="")
            if rule.schengen_only:
                print(" [Schengen]", end="")
            if rule.non_schengen_only:
                print(" [Non-Schengen]", end="")
            print(f" - {rule.summary}")
        
        if result.operating_hours:
            print(f"  Operating hours: {result.operating_hours}")
        if result.contact_phone:
            print(f"  Phone: {result.contact_phone}")
    
    print(f"\n{'='*60}")
    print(f"Processed {len(results)} samples")
    print(f"Total rules extracted: {sum(len(r.rules) for r in results)}")
    avg_confidence = sum(r.confidence for r in results) / len(results) if results else 0
    print(f"Average confidence: {avg_confidence:.2f}")
    
    return results


if __name__ == "__main__":
    test_samples(10)
