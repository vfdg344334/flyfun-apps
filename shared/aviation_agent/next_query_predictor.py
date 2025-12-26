#!/usr/bin/env python3
"""
Next Query Predictor - Rule-based prediction of follow-up queries.

Predicts relevant follow-up queries based on:
- User query text
- Tool selected by planner
- Tool arguments (including filters)

Does NOT use tool results - predictions are purely intent-based.
"""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

from .planning import AviationPlan

logger = logging.getLogger(__name__)


@dataclass
class QueryContext:
    """Context from current query execution - NO RESULTS."""
    user_query: str
    tool_used: str
    tool_arguments: Dict[str, Any]
    filters_applied: Dict[str, Any]

    # Derived from arguments only
    locations_mentioned: List[str]
    icao_codes_mentioned: List[str]
    countries_mentioned: List[str]


@dataclass
class SuggestedQuery:
    """A suggested follow-up query."""
    query_text: str
    tool_name: str
    category: str  # "rules", "route", "details", "pricing"
    priority: int  # 1-5, higher = more relevant


def extract_context_from_plan(
    user_query: str,
    plan: AviationPlan
) -> QueryContext:
    """Extract context from query and plan only (NO RESULTS)."""

    args = plan.arguments
    filters = args.get("filters", {})

    # Extract locations from arguments
    locations = []
    if "from_location" in args:
        locations.append(args["from_location"])
    if "to_location" in args:
        locations.append(args["to_location"])
    if "location_query" in args:
        locations.append(args["location_query"])

    # Extract ICAO codes (4 uppercase letters)
    icao_codes = []
    if "icao_code" in args:
        icao_codes.append(args["icao_code"])
    for loc in locations:
        if loc and len(loc) == 4 and loc.isupper():
            icao_codes.append(loc)

    # Extract countries from arguments
    countries = []
    if "country" in args:
        countries.append(args["country"])
    if "country_code" in args:
        countries.append(args["country_code"])
    if "country1" in args:
        countries.append(args["country1"])
    if "country2" in args:
        countries.append(args["country2"])
    if "country" in filters:
        countries.append(filters["country"])

    return QueryContext(
        user_query=user_query,
        tool_used=plan.selected_tool,
        tool_arguments=args,
        filters_applied=filters,
        locations_mentioned=locations,
        icao_codes_mentioned=icao_codes,
        countries_mentioned=countries
    )


class NextQueryPredictor:
    """Predicts relevant follow-up queries based on current context."""

    def __init__(self, rules_json_path: Optional[Path] = None):
        """
        Initialize predictor with rule-based templates.

        Args:
            rules_json_path: Optional path to rules.json for loading actual rule questions
        """
        self.rules_by_category: Dict[str, List[str]] = {}
        self.rules_by_country: Dict[str, List[str]] = {}

        # Load rules.json if provided
        if rules_json_path:
            rules_path = Path(rules_json_path)
            if rules_path.exists():
                self._load_rules(rules_path)
                if self.rules_by_category:
                    logger.info(f"NextQueryPredictor initialized with {len(self.rules_by_category)} rule categories from {rules_path}")
                else:
                    logger.warning(f"NextQueryPredictor: rules.json loaded but no categories found in {rules_path}")
            else:
                logger.warning(f"NextQueryPredictor: rules.json not found at {rules_path}")

        if not self.rules_by_category:
            logger.info("NextQueryPredictor initialized (rule-based, no rules.json loaded)")

    def _load_rules(self, rules_json_path: Path):
        """Load rule questions from rules.json."""
        try:
            with open(rules_json_path, 'r', encoding='utf-8') as f:
                rules_data = json.load(f)

            # Handle both flat array format and nested format
            if isinstance(rules_data, list):
                # Flat format: [{"country_code": "GB", "question_id": "...", ...}, ...]
                rules_list = rules_data
            elif isinstance(rules_data, dict) and "questions" in rules_data:
                # Nested format: {"questions": [...]}
                # Extract questions without expanding by country (we only need unique questions)
                rules_list = rules_data.get("questions", [])
            else:
                logger.warning(f"Invalid rules.json format: expected list or dict with 'questions' key")
                return

            # Group questions by category
            for rule in rules_list:
                question = rule.get('question_text', '')
                category = rule.get('category', 'Unknown')

                if not question or category == 'ignore':
                    continue

                # Store by category (unique questions only)
                if category not in self.rules_by_category:
                    self.rules_by_category[category] = []
                if question not in self.rules_by_category[category]:
                    self.rules_by_category[category].append(question)

                # For nested format, also store by country
                if isinstance(rule.get('answers_by_country'), dict):
                    for country in rule['answers_by_country'].keys():
                        if country not in self.rules_by_country:
                            self.rules_by_country[country] = []
                        if question not in self.rules_by_country[country]:
                            self.rules_by_country[country].append(question)
                # For flat format
                elif 'country_code' in rule:
                    country = rule['country_code']
                    if country not in self.rules_by_country:
                        self.rules_by_country[country] = []
                    if question not in self.rules_by_country[country]:
                        self.rules_by_country[country].append(question)

            logger.debug(f"Loaded {sum(len(q) for q in self.rules_by_category.values())} unique rule questions from {len(rules_list)} entries")
        except Exception as e:
            logger.warning(f"Failed to load rules.json: {e}")

    def predict_next_queries(
        self,
        context: QueryContext,
        max_suggestions: int = 4
    ) -> List[SuggestedQuery]:
        """
        Generate follow-up query suggestions using rule-based templates.

        Args:
            context: Query context (query + plan, no results)
            max_suggestions: Maximum number of suggestions to return

        Returns:
            List of suggested queries, ranked by priority
        """
        suggestions = []

        # Apply tool-specific templates
        if context.tool_used == "find_airports_near_route":
            suggestions.extend(self._route_tool_suggestions(context))
        elif context.tool_used == "find_airports_near_location":
            suggestions.extend(self._location_tool_suggestions(context))
        elif context.tool_used == "search_airports":
            suggestions.extend(self._search_tool_suggestions(context))
        elif context.tool_used == "get_airport_details":
            suggestions.extend(self._airport_details_suggestions(context))
        elif context.tool_used in ["answer_rules_question", "browse_rules", "compare_rules_between_countries"]:
            suggestions.extend(self._rules_tool_suggestions(context))

        # Rank and return top suggestions
        ranked = self._rank_suggestions(suggestions)
        return ranked[:max_suggestions]

    def _route_tool_suggestions(self, context: QueryContext) -> List[SuggestedQuery]:
        """Suggestions for route planning queries."""
        suggestions = []

        # Suggest adding filters if not already applied
        if not context.filters_applied.get("has_avgas"):
            suggestions.append(SuggestedQuery(
                query_text="Show me airports with AVGAS along this route",
                tool_name="find_airports_near_route",
                category="route",
                priority=4
            ))

        if not context.filters_applied.get("point_of_entry"):
            suggestions.append(SuggestedQuery(
                query_text="Which airports have customs facilities on this route?",
                tool_name="find_airports_near_route",
                category="route",
                priority=5
            ))

        # Suggest airport details for first ICAO code
        if context.icao_codes_mentioned:
            icao = context.icao_codes_mentioned[0]
            suggestions.append(SuggestedQuery(
                query_text=f"What are the procedures at {icao}?",
                tool_name="get_airport_details",
                category="details",
                priority=3
            ))

            # Pricing tool removed - suggest airport details instead
            suggestions.append(SuggestedQuery(
                query_text=f"Tell me more about {icao}",
                tool_name="get_airport_details",
                category="details",
                priority=3
            ))

        # ALWAYS suggest rules for route queries (not just cross-country)
        # Routes typically involve multiple countries or international flight
        suggestions.extend(self._get_route_rule_suggestions(context))

        return suggestions

    def _get_route_rule_suggestions(self, context: QueryContext) -> List[SuggestedQuery]:
        """
        Get rule suggestions for route queries.

        Provides variety by selecting one question from each relevant category.
        Works for ALL route queries, not just cross-country.
        """
        suggestions = []

        # If we have loaded rules from rules.json, use actual questions
        if self.rules_by_category:
            # Define category priorities for route queries
            # Each tuple: (category_name, priority, max_questions)
            category_priorities = [
                ('International', 5, 1),  # Most relevant for routes
                ('VFR', 4, 1),            # Common for GA routes
                ('Airspace', 4, 1),       # Important for route planning
                ('Flight Rules', 4, 1),   # General flight planning
                ('IFR', 3, 1),            # Relevant for some routes
                ('Airfields', 3, 1),      # Airport-related rules
            ]

            for category, priority, max_count in category_priorities:
                questions = self.rules_by_category.get(category, [])
                if questions:
                    # Take first N questions from this category
                    for question in questions[:max_count]:
                        suggestions.append(SuggestedQuery(
                            query_text=question,
                            tool_name="answer_rules_question",
                            category="rules",
                            priority=priority
                        ))
        else:
            # Fallback to generic questions if rules.json not loaded
            suggestions.append(SuggestedQuery(
                query_text="What are the customs rules for countries along this route?",
                tool_name="answer_rules_question",
                category="rules",
                priority=4
            ))
            suggestions.append(SuggestedQuery(
                query_text="Do I need to file a flight plan for this route?",
                tool_name="answer_rules_question",
                category="rules",
                priority=4
            ))

        return suggestions

    def _location_tool_suggestions(self, context: QueryContext) -> List[SuggestedQuery]:
        """Suggestions for location-based searches."""
        suggestions = []

        location = context.tool_arguments.get("location_query", "this location")

        # Suggest adding filters
        if not context.filters_applied.get("has_hard_runway"):
            suggestions.append(SuggestedQuery(
                query_text=f"Show airports with hard runways near {location}",
                tool_name="find_airports_near_location",
                category="route",
                priority=3
            ))

        if not context.filters_applied.get("has_avgas"):
            suggestions.append(SuggestedQuery(
                query_text=f"Show airports with AVGAS near {location}",
                tool_name="find_airports_near_location",
                category="route",
                priority=4
            ))

        # Suggest country rules if country mentioned
        if context.countries_mentioned:
            country = context.countries_mentioned[0]
            suggestions.append(SuggestedQuery(
                query_text=f"What are the landing requirements for {country}?",
                tool_name="answer_rules_question",
                category="rules",
                priority=4
            ))

        return suggestions

    def _search_tool_suggestions(self, context: QueryContext) -> List[SuggestedQuery]:
        """Suggestions for airport search queries."""
        suggestions = []

        # Suggest adding filters
        if not context.filters_applied.get("point_of_entry"):
            suggestions.append(SuggestedQuery(
                query_text="Show only airports with customs facilities",
                tool_name="search_airports",
                category="route",
                priority=3
            ))

        # Suggest country rules if country in filters
        if context.countries_mentioned:
            country = context.countries_mentioned[0]
            suggestions.append(SuggestedQuery(
                query_text=f"What are the VFR rules for {country}?",
                tool_name="answer_rules_question",
                category="rules",
                priority=4
            ))

        return suggestions

    def _airport_details_suggestions(self, context: QueryContext) -> List[SuggestedQuery]:
        """Suggestions after viewing airport details."""
        suggestions = []

        icao = context.tool_arguments.get("icao_code")
        if not icao:
            return suggestions

        # Suggest notification requirements
        suggestions.append(SuggestedQuery(
            query_text=f"What are the notification requirements for {icao}?",
            tool_name="get_notification_for_airport",
            category="details",
            priority=4
        ))

        # Suggest country rules
        if context.countries_mentioned:
            country = context.countries_mentioned[0]
            suggestions.append(SuggestedQuery(
                query_text=f"What are the customs rules for {country}?",
                tool_name="answer_rules_question",
                category="rules",
                priority=3
            ))

        return suggestions


    def _rules_tool_suggestions(self, context: QueryContext) -> List[SuggestedQuery]:
        """Suggestions after viewing rules."""
        suggestions = []

        # Suggest customs airports
        if context.countries_mentioned:
            country = context.countries_mentioned[0]
            suggestions.append(SuggestedQuery(
                query_text=f"Which airports have customs in {country}?",
                tool_name="search_airports",
                category="route",
                priority=5
            ))

            # Suggest VFR rules if not already viewing them
            if "vfr" not in context.user_query.lower():
                suggestions.append(SuggestedQuery(
                    query_text=f"What are the VFR weather minimums for {country}?",
                    tool_name="answer_rules_question",
                    category="rules",
                    priority=4
                ))

        # Suggest comparison if only one country
        if len(context.countries_mentioned) == 1:
            suggestions.append(SuggestedQuery(
                query_text="Compare rules with neighboring countries",
                tool_name="compare_rules_between_countries",
                category="rules",
                priority=3
            ))

        return suggestions

    def _rank_suggestions(self, suggestions: List[SuggestedQuery]) -> List[SuggestedQuery]:
        """
        Rank suggestions by priority and diversity.

        Ensures variety by preferring different categories and tools.
        """
        if not suggestions:
            return []

        # Sort by priority (descending)
        sorted_suggestions = sorted(suggestions, key=lambda s: s.priority, reverse=True)

        # Deduplicate by query text
        seen_queries = set()
        unique_suggestions = []
        for suggestion in sorted_suggestions:
            if suggestion.query_text not in seen_queries:
                seen_queries.add(suggestion.query_text)
                unique_suggestions.append(suggestion)

        # Prefer diversity in categories
        ranked = []
        seen_categories = set()

        # First pass: one from each category
        for suggestion in unique_suggestions:
            if suggestion.category not in seen_categories:
                ranked.append(suggestion)
                seen_categories.add(suggestion.category)

        # Second pass: fill remaining slots
        for suggestion in unique_suggestions:
            if suggestion not in ranked:
                ranked.append(suggestion)

        return ranked
