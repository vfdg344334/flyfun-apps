"""
Notification rule parser with waterfall logic.

Extracts structured notification rules from AIP customs/immigration text.
Uses a waterfall approach:
    1. Quick regex patterns for simple cases (free, fast)
    2. Complexity detection
    3. LLM extraction for complex cases (OpenAI API)
"""

import re
import os
import logging
from typing import List, Optional, Tuple, Dict, Any
from dataclasses import dataclass

from .models import (
    NotificationRule,
    RuleType,
    NotificationType,
    ParsedNotificationRules,
)

logger = logging.getLogger(__name__)


@dataclass
class ParseResult:
    """Result from regex parsing step."""
    rules: List[NotificationRule]
    confidence: float
    is_complete: bool
    complexity_indicators: List[str]


class NotificationParser:
    """
    Parse notification requirements from AIP text using waterfall logic.
    
    Waterfall:
        1. Try quick regex patterns (H24, O/R, simple PPR hours)
        2. Check complexity indicators
        3. If complex and LLM enabled, use OpenAI for extraction
    """
    
    # === REGEX PATTERNS ===
    
    # Simple patterns (high confidence, complete)
    H24_PATTERN = re.compile(r'\bH24\b', re.IGNORECASE)
    
    ON_REQUEST_PATTERN = re.compile(
        r'\b(?:O/R|on\s+request|by\s+(?:prior\s+)?arrangement|sur\s+demande)\b',
        re.IGNORECASE
    )
    
    AS_AD_HOURS_PATTERN = re.compile(
        r'\b(?:as\s+AD\s+(?:hours?|HR)|AD\s+OPR\s+HR|HR\s+AD)\b',
        re.IGNORECASE
    )
    
    # Hours patterns
    HOURS_PATTERN = re.compile(
        r'(?:(?:PPR|PN|PPR\s*PN)\s*(?:MNM\s+)?(\d+)\s*(?:HR?S?|HOURS?))|'
        r'(?:(\d+)\s*(?:HR?S?|HOURS?)\s*(?:PPR|PN)\s*(?:MNM)?)|'
        r'(?:(\d+)\s*(?:HR?S?|HOURS?)\s+(?:prior\s+)?(?:notice|advance|PN))',
        re.IGNORECASE
    )
    
    # Weekday-specific patterns
    # Improved to handle: "MON-FRI : PPR PN 24 HR", "MON-FRI : 0700-1900 with PN 24 HR"
    WEEKDAY_HOURS_PATTERN = re.compile(
        r'(MON(?:DAY)?|TUE(?:SDAY)?|WED(?:NESDAY)?|THU(?:RSDAY)?|FRI(?:DAY)?|'
        r'SAT(?:URDAY)?|SUN(?:DAY)?|WEEK-?END|WEEK-?DAYS?)'
        r'(?:\s*[-–,]\s*(MON(?:DAY)?|TUE(?:SDAY)?|WED(?:NESDAY)?|THU(?:RSDAY)?|'
        r'FRI(?:DAY)?|SAT(?:URDAY)?|SUN(?:DAY)?|HOL(?:IDAYS?)?))?'
        r'(?:\s*(?:and\s+)?(?:public\s+)?HOL(?:IDAYS?)?)?'  # Optional HOL suffix
        r'\s*[,:]\s*'
        r'(?:\d{4}\s*[-–]\s*\d{4}\s*)?'  # Optional operating hours like 0700-1900
        r'(?:with\s+)?'  # Optional "with"
        r'(?:PPR\s*)?(?:PN\s+)?'  # PPR and/or PN
        r'(\d+)\s*(?:HR?S?|HOURS?)',  # Hours (required in this pattern)
        re.IGNORECASE
    )
    
    # Business day pattern
    BUSINESS_DAY_PATTERN = re.compile(
        r'(?:last\s+)?(?:working|business)\s+day\s+(?:before\s+)?(\d{4})?',
        re.IGNORECASE
    )
    
    # Specific time pattern (before 1100, before 1600)
    BEFORE_TIME_PATTERN = re.compile(
        r'before\s+(\d{4})\s*(?:local)?',
        re.IGNORECASE
    )
    
    # Previous day pattern
    PREVIOUS_DAY_PATTERN = re.compile(
        r'(?:previous|the)\s+day\s+(?:before\s+)?(\d{4})?',
        re.IGNORECASE
    )
    
    # === COMPLEXITY INDICATORS ===
    
    # Patterns that indicate complex rules needing LLM
    COMPLEXITY_PATTERNS = {
        'multiple_day_ranges': re.compile(
            r'(MON|TUE|WED|THU|FRI|SAT|SUN).*?(MON|TUE|WED|THU|FRI|SAT|SUN).*?'
            r'(MON|TUE|WED|THU|FRI|SAT|SUN)',
            re.IGNORECASE
        ),
        'schengen_conditions': re.compile(
            r'\b(?:schengen|within\s+schengen|outside\s+schengen|'
            r'extra[- ]?schengen|non[- ]?schengen)\b',
            re.IGNORECASE
        ),
        'prohibited': re.compile(
            r'\b(?:prohibited|not\s+(?:permitted|allowed|authorized)|interdit)\b',
            re.IGNORECASE
        ),
        'specific_times': re.compile(
            r'before\s+\d{4}|until\s+\d{4}|by\s+\d{4}',
            re.IGNORECASE
        ),
        'opening_closing': re.compile(
            r'\b(?:opening|closing)\s+hours?\b',
            re.IGNORECASE
        ),
        'multiple_conditions': re.compile(
            r'(?:if|when|during|except|unless|provided)',
            re.IGNORECASE
        ),
        'long_text': None,  # Checked separately
    }
    
    # Day name mapping
    DAY_MAP = {
        'mon': 0, 'monday': 0,
        'tue': 1, 'tuesday': 1,
        'wed': 2, 'wednesday': 2,
        'thu': 3, 'thursday': 3,
        'fri': 4, 'friday': 4,
        'sat': 5, 'saturday': 5,
        'sun': 6, 'sunday': 6,
        'weekday': (0, 4), 'weekdays': (0, 4),
        'week-end': (5, 6), 'weekend': (5, 6), 'weekends': (5, 6),
    }
    
    # Complexity threshold - if more than this many indicators, use LLM
    COMPLEXITY_THRESHOLD = 2
    
    def __init__(
        self,
        use_llm_fallback: bool = False,
        llm_model: str = "gpt-4o-mini",
        llm_api_key: Optional[str] = None,
    ):
        """
        Initialize parser.
        
        Args:
            use_llm_fallback: Enable LLM for complex cases
            llm_model: OpenAI model to use
            llm_api_key: API key (defaults to OPENAI_API_KEY env var)
        """
        self.use_llm_fallback = use_llm_fallback
        self.llm_model = llm_model
        self.llm_api_key = llm_api_key or os.environ.get("OPENAI_API_KEY")
        self._openai_client = None
    
    def parse(self, icao: str, text: str, std_field_id: int = 302) -> ParsedNotificationRules:
        """
        Parse notification rules using waterfall logic.
        
        Waterfall:
            1. Quick regex patterns for simple cases
            2. Check complexity indicators
            3. If complex and LLM enabled, use OpenAI
        """
        if not text or not text.strip():
            return ParsedNotificationRules(
                icao=icao,
                raw_text=text or "",
                source_std_field_id=std_field_id,
                parse_warnings=["Empty text"],
            )
        
        text = text.strip()
        
        # STEP 1: Try quick regex patterns
        parse_result = self._try_quick_patterns(text)
        
        # If high confidence and complete, we're done
        if parse_result.is_complete and parse_result.confidence >= 0.85:
            logger.debug(f"{icao}: Quick pattern matched with confidence {parse_result.confidence}")
            return ParsedNotificationRules(
                icao=icao,
                rules=parse_result.rules,
                raw_text=text,
                source_std_field_id=std_field_id,
            )
        
        # STEP 2: Check complexity
        complexity_indicators = self._detect_complexity(text)
        complexity_score = len(complexity_indicators)
        
        logger.debug(f"{icao}: Complexity score {complexity_score}, indicators: {complexity_indicators}")
        
        # If not too complex, return partial regex results
        if complexity_score <= self.COMPLEXITY_THRESHOLD and parse_result.rules:
            return ParsedNotificationRules(
                icao=icao,
                rules=parse_result.rules,
                raw_text=text,
                source_std_field_id=std_field_id,
                parse_warnings=[f"Partial parse (complexity={complexity_score})"],
            )
        
        # STEP 3: Use LLM for complex cases
        if self.use_llm_fallback and complexity_score > self.COMPLEXITY_THRESHOLD:
            logger.info(f"{icao}: Using LLM for complex notification (indicators: {complexity_indicators})")
            llm_rules = self._parse_with_llm(icao, text)
            
            if llm_rules:
                return ParsedNotificationRules(
                    icao=icao,
                    rules=llm_rules,
                    raw_text=text,
                    source_std_field_id=std_field_id,
                )
        
        # Fallback: return whatever we have
        warnings = []
        if not parse_result.rules:
            warnings.append("Could not parse notification rules")
        if complexity_score > self.COMPLEXITY_THRESHOLD and not self.use_llm_fallback:
            warnings.append(f"Complex text (score={complexity_score}), LLM disabled")
        
        return ParsedNotificationRules(
            icao=icao,
            rules=parse_result.rules,
            raw_text=text,
            source_std_field_id=std_field_id,
            parse_warnings=warnings,
        )
    
    def _try_quick_patterns(self, text: str) -> ParseResult:
        """
        Try quick regex patterns for simple cases.
        
        Returns ParseResult with confidence and completeness.
        Only marks as "complete" if text is short and simple.
        """
        rules: List[NotificationRule] = []
        
        # Pre-check: if text is long or has complexity markers, don't return early
        is_simple_text = len(text) < 100
        has_multiple_days = len(re.findall(r'\b(MON|TUE|WED|THU|FRI|SAT|SUN)\b', text, re.IGNORECASE)) >= 3
        has_schengen = bool(re.search(r'\bschengen\b', text, re.IGNORECASE))
        has_prohibited = bool(re.search(r'\bprohibited\b', text, re.IGNORECASE))
        
        text_is_complex = has_multiple_days or has_schengen or has_prohibited or len(text) > 200
        
        # Check H24 - simplest case (only complete if short text)
        if self.H24_PATTERN.search(text):
            rules.append(NotificationRule(
                rule_type=RuleType.CUSTOMS,
                notification_type=NotificationType.H24,
                raw_text=text,
                confidence=0.95,
            ))
            is_complete = is_simple_text and not text_is_complex
            return ParseResult(rules=rules, confidence=0.95, is_complete=is_complete, complexity_indicators=[])
        
        # Check simple "on request" (without hours) - only complete if simple text
        if self.ON_REQUEST_PATTERN.search(text) and not self.HOURS_PATTERN.search(text):
            # Don't mark as complete if text is complex
            if not text_is_complex:
                rules.append(NotificationRule(
                    rule_type=RuleType.CUSTOMS,
                    notification_type=NotificationType.ON_REQUEST,
                    raw_text=text,
                    confidence=0.90,
                ))
                return ParseResult(rules=rules, confidence=0.90, is_complete=is_simple_text, complexity_indicators=[])
            # Text is complex - don't return early, continue to more detailed parsing
        
        # Check "as AD hours" - only complete if simple text
        if self.AS_AD_HOURS_PATTERN.search(text) and not self.HOURS_PATTERN.search(text):
            if not text_is_complex:
                rules.append(NotificationRule(
                    rule_type=RuleType.CUSTOMS,
                    notification_type=NotificationType.AS_AD_HOURS,
                    raw_text=text,
                    confidence=0.90,
                ))
                return ParseResult(rules=rules, confidence=0.90, is_complete=is_simple_text, complexity_indicators=[])
        
        # Try weekday-specific rules
        weekday_rules = self._extract_weekday_rules(text)
        if weekday_rules:
            rules.extend(weekday_rules)
        
        # Try simple hours rules
        if not rules:
            hours_rules = self._extract_hours_rules(text)
            if hours_rules:
                rules.extend(hours_rules)
        
        # Try business day rules
        business_rules = self._extract_business_day_rules(text)
        if business_rules:
            rules.extend(business_rules)
        
        # Apply Schengen context to all rules
        rules = self._apply_schengen_context(rules, text)
        
        # Calculate confidence based on what we found
        if rules:
            avg_confidence = sum(r.confidence for r in rules) / len(rules)
            # Complete if we found rules and text is short/simple
            is_complete = len(text) < 150 and len(rules) <= 2
            return ParseResult(
                rules=rules,
                confidence=avg_confidence,
                is_complete=is_complete,
                complexity_indicators=[],
            )
        
        return ParseResult(rules=[], confidence=0.0, is_complete=False, complexity_indicators=[])
    
    def _detect_complexity(self, text: str) -> List[str]:
        """Detect complexity indicators in the text."""
        indicators = []
        
        for name, pattern in self.COMPLEXITY_PATTERNS.items():
            if name == 'long_text':
                if len(text) > 300:
                    indicators.append('long_text')
            elif pattern and pattern.search(text):
                indicators.append(name)
        
        # Check for multiple distinct day ranges
        day_mentions = re.findall(
            r'\b(MON|TUE|WED|THU|FRI|SAT|SUN)\b',
            text, re.IGNORECASE
        )
        if len(set(d.upper() for d in day_mentions)) >= 4:
            indicators.append('many_day_references')
        
        return indicators
    
    def _detect_schengen_context(self, text: str) -> Tuple[bool, bool]:
        """
        Detect Schengen flight context from text.
        
        Returns:
            (schengen_only, non_schengen_only) tuple
        """
        # Check for non-Schengen indicators (extra-Schengen, non-Schengen, outside Schengen)
        non_schengen_pattern = re.compile(
            r'\b(?:extra[- ]?schengen|non[- ]?schengen|outside\s+schengen)\b',
            re.IGNORECASE
        )
        
        # Check for Schengen-only indicators (within Schengen, Schengen flights only)
        schengen_pattern = re.compile(
            r'\b(?:within\s+schengen|schengen\s+(?:flights?\s+)?only)\b',
            re.IGNORECASE
        )
        
        is_non_schengen = bool(non_schengen_pattern.search(text))
        is_schengen = bool(schengen_pattern.search(text))
        
        # If both are mentioned, it's likely a complex case with separate rules
        if is_non_schengen and is_schengen:
            return (False, False)  # Let individual rules handle it
        
        return (is_schengen, is_non_schengen)
    
    def _apply_schengen_context(
        self, rules: List[NotificationRule], text: str
    ) -> List[NotificationRule]:
        """Apply Schengen context to all rules if detected in text."""
        schengen_only, non_schengen_only = self._detect_schengen_context(text)
        
        if not schengen_only and not non_schengen_only:
            return rules
        
        # Apply to all rules that don't already have Schengen set
        for rule in rules:
            if not rule.schengen_only and not rule.non_schengen_only:
                rule.schengen_only = schengen_only
                rule.non_schengen_only = non_schengen_only
        
        return rules
    
    def _parse_day(self, day_str: str) -> Tuple[Optional[int], Optional[int], bool]:
        """Parse day string into start/end day numbers."""
        day_str = day_str.lower().strip()
        includes_holidays = 'hol' in day_str
        day_str = re.sub(r'\s*(?:and\s+)?hol(?:idays?)?', '', day_str, flags=re.IGNORECASE).strip()
        
        if day_str in self.DAY_MAP:
            result = self.DAY_MAP[day_str]
            if isinstance(result, tuple):
                return result[0], result[1], includes_holidays
            return result, None, includes_holidays
        
        return None, None, includes_holidays
    
    def _extract_weekday_rules(self, text: str) -> List[NotificationRule]:
        """Extract weekday-specific rules."""
        rules = []
        
        for match in self.WEEKDAY_HOURS_PATTERN.finditer(text):
            day_start_str = match.group(1)
            day_end_str = match.group(2)
            hours_str = match.group(3)
            matched_text = match.group(0)
            
            start_day, end_day_from_start, includes_hol = self._parse_day(day_start_str)
            
            if day_end_str:
                end_day, _, hol2 = self._parse_day(day_end_str)
                includes_hol = includes_hol or hol2
                # If day_end_str was just "HOL" (no actual day), use the range from day_start
                if end_day is None and hol2:
                    end_day = end_day_from_start
            else:
                end_day = end_day_from_start
            
            # Also check the full matched text for HOL references
            if not includes_hol and re.search(r'\bHOL(?:IDAYS?)?\b', matched_text, re.IGNORECASE):
                includes_hol = True
            
            hours = int(hours_str) if hours_str else None
            
            rule = NotificationRule(
                rule_type=RuleType.PPR,
                notification_type=NotificationType.HOURS if hours else NotificationType.ON_REQUEST,
                hours_notice=hours,
                weekday_start=start_day,
                weekday_end=end_day,
                includes_holidays=includes_hol,
                raw_text=matched_text,
                confidence=0.80,
            )
            rules.append(rule)
        
        return rules
    
    def _extract_hours_rules(self, text: str) -> List[NotificationRule]:
        """Extract simple hours-based rules."""
        rules = []
        seen_hours = set()
        
        for match in self.HOURS_PATTERN.finditer(text):
            hours = None
            for group_num in [1, 2, 3]:
                if match.group(group_num):
                    hours = int(match.group(group_num))
                    break
            
            if hours is None or hours in seen_hours:
                continue
            
            seen_hours.add(hours)
            rules.append(NotificationRule(
                rule_type=RuleType.PPR,
                notification_type=NotificationType.HOURS,
                hours_notice=hours,
                raw_text=match.group(0),
                confidence=0.80,
            ))
        
        return rules
    
    def _extract_business_day_rules(self, text: str) -> List[NotificationRule]:
        """Extract business day rules."""
        rules = []
        
        for match in self.BUSINESS_DAY_PATTERN.finditer(text):
            time_str = match.group(1)
            rules.append(NotificationRule(
                rule_type=RuleType.PPR,
                notification_type=NotificationType.BUSINESS_DAY,
                business_day_offset=-1,
                specific_time=time_str,
                raw_text=match.group(0),
                confidence=0.75,
            ))
        
        return rules
    
    def _parse_with_llm(self, icao: str, text: str) -> List[NotificationRule]:
        """
        Use OpenAI API to parse complex notification text.
        
        Uses structured output with Pydantic for reliable parsing.
        """
        if not self.llm_api_key:
            logger.warning("LLM API key not configured, skipping LLM extraction")
            return []
        
        try:
            from openai import OpenAI
            from pydantic import BaseModel, Field
            from typing import Literal
        except ImportError:
            logger.warning("OpenAI package not available")
            return []
        
        # Define the output schema
        class ExtractedRule(BaseModel):
            """A single notification rule extracted from the text."""
            rule_type: Literal["ppr", "customs", "immigration"] = Field(
                description="Type of notification requirement"
            )
            notification_type: Literal["hours", "business_day", "on_request", "h24", "prohibited"] = Field(
                description="How the notification timing is specified"
            )
            hours_notice: Optional[int] = Field(
                None, description="Hours notice required (e.g., 24, 48)"
            )
            weekday_start: Optional[int] = Field(
                None, description="Start of weekday range (0=Monday, 6=Sunday)"
            )
            weekday_end: Optional[int] = Field(
                None, description="End of weekday range (0=Monday, 6=Sunday)"
            )
            specific_time: Optional[str] = Field(
                None, description="Specific time cutoff (e.g., '1100', '1600')"
            )
            business_day_offset: Optional[int] = Field(
                None, description="Days before (-1 = last business day, -2 = two business days before)"
            )
            schengen_only: bool = Field(
                False, description="Rule only applies to Schengen flights"
            )
            non_schengen_only: bool = Field(
                False, description="Rule only applies to non-Schengen flights"
            )
            is_prohibited: bool = Field(
                False, description="True if this type of flight is prohibited"
            )
            summary: str = Field(
                description="Brief human-readable summary of this rule"
            )
        
        class ExtractedRules(BaseModel):
            """All notification rules extracted from the text."""
            rules: List[ExtractedRule] = Field(
                description="List of notification rules found in the text"
            )
            overall_summary: str = Field(
                description="Brief overall summary of notification requirements"
            )
        
        # Initialize client
        if self._openai_client is None:
            self._openai_client = OpenAI(api_key=self.llm_api_key)
        
        prompt = f"""Extract notification requirements from this airport customs/immigration text.

Airport: {icao}
Text: {text}

Extract ALL notification rules, including:
- Different rules for different days (weekdays vs weekends)
- Different rules for Schengen vs non-Schengen flights
- Specific time cutoffs (e.g., "before 1100")
- Business day requirements (e.g., "last working day")
- Prohibited operations

For weekdays: Monday=0, Tuesday=1, Wednesday=2, Thursday=3, Friday=4, Saturday=5, Sunday=6

If flights are prohibited for certain conditions, include a rule with is_prohibited=True."""

        try:
            response = self._openai_client.beta.chat.completions.parse(
                model=self.llm_model,
                messages=[
                    {"role": "system", "content": "You are an aviation expert extracting structured notification requirements from AIP (Aeronautical Information Publication) text. Be precise and extract ALL rules mentioned."},
                    {"role": "user", "content": prompt}
                ],
                response_format=ExtractedRules,
                temperature=0,
            )
            
            extracted = response.choices[0].message.parsed
            
            if not extracted or not extracted.rules:
                logger.warning(f"{icao}: LLM returned no rules")
                return []
            
            # Convert to NotificationRule objects
            rules = []
            for r in extracted.rules:
                # Map notification type
                if r.is_prohibited:
                    notif_type = NotificationType.NOT_AVAILABLE
                elif r.notification_type == "hours":
                    notif_type = NotificationType.HOURS
                elif r.notification_type == "business_day":
                    notif_type = NotificationType.BUSINESS_DAY
                elif r.notification_type == "on_request":
                    notif_type = NotificationType.ON_REQUEST
                elif r.notification_type == "h24":
                    notif_type = NotificationType.H24
                else:
                    notif_type = NotificationType.UNKNOWN
                
                # Map rule type
                if r.rule_type == "ppr":
                    rule_type = RuleType.PPR
                elif r.rule_type == "immigration":
                    rule_type = RuleType.IMMIGRATION
                else:
                    rule_type = RuleType.CUSTOMS
                
                rules.append(NotificationRule(
                    rule_type=rule_type,
                    notification_type=notif_type,
                    hours_notice=r.hours_notice,
                    weekday_start=r.weekday_start,
                    weekday_end=r.weekday_end,
                    specific_time=r.specific_time,
                    business_day_offset=r.business_day_offset,
                    schengen_only=r.schengen_only,
                    non_schengen_only=r.non_schengen_only,
                    raw_text=r.summary,
                    confidence=0.85,
                    extraction_method="llm",
                ))
            
            logger.info(f"{icao}: LLM extracted {len(rules)} rules")
            return rules
            
        except Exception as e:
            logger.error(f"{icao}: LLM extraction failed: {e}")
            return []
    
    def parse_batch(
        self,
        airports: List[Tuple[str, str]],
        std_field_id: int = 302,
    ) -> List[ParsedNotificationRules]:
        """Parse notification rules for multiple airports."""
        return [
            self.parse(icao, text, std_field_id)
            for icao, text in airports
        ]
