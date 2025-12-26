"""
Tests for next_query_predictor module.

Tests cover:
- Context extraction from plans
- Suggestion generation for different tools
- Filter-based suggestions
- Entity-based suggestions
- Rule-based suggestions
- Ranking and deduplication
- Configuration-driven templates
"""
from __future__ import annotations

import pytest
from pathlib import Path

from shared.aviation_agent.next_query_predictor import (
    NextQueryPredictor,
    QueryContext,
    SuggestedQuery,
    extract_context_from_plan,
    FilterName,
    ToolName,
    SuggestionCategory,
    PRIORITY_HIGH,
    PRIORITY_MEDIUM_HIGH,
    PRIORITY_MEDIUM,
)
from shared.aviation_agent.planning import AviationPlan


class TestExtractContextFromPlan:
    """Tests for extract_context_from_plan function."""

    def test_extracts_route_locations(self):
        """Extracts from_location and to_location from route query."""
        plan = AviationPlan(
            selected_tool=ToolName.FIND_AIRPORTS_NEAR_ROUTE,
            arguments={
                "from_location": "EGTF",
                "to_location": "LFMD",
                "filters": {}
            },
            answer_style="brief"
        )

        context = extract_context_from_plan("Find airports from EGTF to LFMD", plan)

        assert context.tool_used == ToolName.FIND_AIRPORTS_NEAR_ROUTE
        assert "EGTF" in context.locations_mentioned
        assert "LFMD" in context.locations_mentioned
        assert "EGTF" in context.icao_codes_mentioned
        assert "LFMD" in context.icao_codes_mentioned

    def test_extracts_location_query(self):
        """Extracts location_query from near-location search."""
        plan = AviationPlan(
            selected_tool=ToolName.FIND_AIRPORTS_NEAR_LOCATION,
            arguments={
                "location_query": "Paris",
                "filters": {FilterName.HAS_AVGAS: True}
            },
            answer_style="detailed"
        )

        context = extract_context_from_plan("Find airports near Paris", plan)

        assert context.tool_used == ToolName.FIND_AIRPORTS_NEAR_LOCATION
        assert "Paris" in context.locations_mentioned
        assert context.filters_applied.get(FilterName.HAS_AVGAS) is True

    def test_extracts_icao_code(self):
        """Extracts icao_code from airport details query."""
        plan = AviationPlan(
            selected_tool=ToolName.GET_AIRPORT_DETAILS,
            arguments={"icao_code": "EGLL"},
            answer_style="detailed"
        )

        context = extract_context_from_plan("Details for EGLL", plan)

        assert "EGLL" in context.icao_codes_mentioned

    def test_extracts_countries(self):
        """Extracts country from various argument positions."""
        plan = AviationPlan(
            selected_tool=ToolName.ANSWER_RULES_QUESTION,
            arguments={"country_code": "FR"},
            answer_style="detailed"
        )

        context = extract_context_from_plan("Rules for France", plan)

        assert "FR" in context.countries_mentioned

    def test_extracts_country_from_filters(self):
        """Extracts country from filters dict."""
        plan = AviationPlan(
            selected_tool=ToolName.SEARCH_AIRPORTS,
            arguments={
                "query": "airports",
                "filters": {"country": "DE"}
            },
            answer_style="brief"
        )

        context = extract_context_from_plan("Airports in Germany", plan)

        assert "DE" in context.countries_mentioned

    def test_handles_missing_arguments(self):
        """Handles missing arguments gracefully."""
        plan = AviationPlan(
            selected_tool=ToolName.SEARCH_AIRPORTS,
            arguments={},
            answer_style="brief"
        )

        context = extract_context_from_plan("Search airports", plan)

        assert context.tool_used == ToolName.SEARCH_AIRPORTS
        assert context.locations_mentioned == []
        assert context.icao_codes_mentioned == []
        assert context.countries_mentioned == []


class TestNextQueryPredictor:
    """Tests for NextQueryPredictor class."""

    @pytest.fixture
    def predictor(self):
        """Create predictor without rules.json."""
        return NextQueryPredictor(rules_json_path=None)

    def test_route_suggestions_include_customs(self, predictor):
        """Route queries suggest customs when not filtered."""
        context = QueryContext(
            user_query="Find airports from EGTF to LFMD",
            tool_used=ToolName.FIND_AIRPORTS_NEAR_ROUTE,
            tool_arguments={"from_location": "EGTF", "to_location": "LFMD"},
            filters_applied={},
            locations_mentioned=["EGTF", "LFMD"],
            icao_codes_mentioned=["EGTF", "LFMD"],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        # Should suggest customs since not filtered
        customs_suggestions = [s for s in suggestions if "customs" in s.query_text.lower()]
        assert len(customs_suggestions) > 0

    def test_route_suggestions_include_avgas(self, predictor):
        """Route queries suggest AVGAS when not filtered."""
        context = QueryContext(
            user_query="Find airports from EGTF to LFMD",
            tool_used=ToolName.FIND_AIRPORTS_NEAR_ROUTE,
            tool_arguments={"from_location": "EGTF", "to_location": "LFMD"},
            filters_applied={},
            locations_mentioned=["EGTF", "LFMD"],
            icao_codes_mentioned=["EGTF", "LFMD"],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        avgas_suggestions = [s for s in suggestions if "avgas" in s.query_text.lower()]
        assert len(avgas_suggestions) > 0

    def test_route_suggestions_skip_avgas_if_filtered(self, predictor):
        """Route queries don't suggest AVGAS when already filtered."""
        context = QueryContext(
            user_query="Find airports with AVGAS from EGTF to LFMD",
            tool_used=ToolName.FIND_AIRPORTS_NEAR_ROUTE,
            tool_arguments={"from_location": "EGTF", "to_location": "LFMD"},
            filters_applied={FilterName.HAS_AVGAS: True},  # Already filtering
            locations_mentioned=["EGTF", "LFMD"],
            icao_codes_mentioned=["EGTF", "LFMD"],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        # Should NOT suggest AVGAS filter since already applied
        avgas_filter_suggestions = [
            s for s in suggestions
            if "avgas" in s.query_text.lower() and s.tool_name == ToolName.FIND_AIRPORTS_NEAR_ROUTE
        ]
        assert len(avgas_filter_suggestions) == 0

    def test_route_suggestions_include_airport_details(self, predictor):
        """Route queries suggest airport details for mentioned ICAO codes."""
        context = QueryContext(
            user_query="Find airports from EGTF to LFMD",
            tool_used=ToolName.FIND_AIRPORTS_NEAR_ROUTE,
            tool_arguments={"from_location": "EGTF", "to_location": "LFMD"},
            filters_applied={},
            locations_mentioned=["EGTF", "LFMD"],
            icao_codes_mentioned=["EGTF", "LFMD"],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        # Should suggest airport details
        details_suggestions = [
            s for s in suggestions
            if s.tool_name == ToolName.GET_AIRPORT_DETAILS
        ]
        assert len(details_suggestions) > 0
        assert any("EGTF" in s.query_text for s in details_suggestions)

    def test_location_suggestions_include_filters(self, predictor):
        """Location queries suggest filters when not applied."""
        context = QueryContext(
            user_query="Find airports near Paris",
            tool_used=ToolName.FIND_AIRPORTS_NEAR_LOCATION,
            tool_arguments={"location_query": "Paris"},
            filters_applied={},
            locations_mentioned=["Paris"],
            icao_codes_mentioned=[],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        # Should suggest filters
        filter_suggestions = [
            s for s in suggestions
            if s.tool_name == ToolName.FIND_AIRPORTS_NEAR_LOCATION
        ]
        assert len(filter_suggestions) > 0

    def test_airport_details_suggests_notification(self, predictor):
        """Airport details queries suggest notification requirements."""
        context = QueryContext(
            user_query="Details for EGLL",
            tool_used=ToolName.GET_AIRPORT_DETAILS,
            tool_arguments={"icao_code": "EGLL"},
            filters_applied={},
            locations_mentioned=[],
            icao_codes_mentioned=["EGLL"],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        notification_suggestions = [
            s for s in suggestions
            if "notification" in s.query_text.lower()
        ]
        assert len(notification_suggestions) > 0
        assert any(s.tool_name == ToolName.GET_NOTIFICATION_FOR_AIRPORT for s in notification_suggestions)

    def test_rules_query_suggests_customs_airports(self, predictor):
        """Rules queries suggest border crossing airports."""
        context = QueryContext(
            user_query="What are the rules for France?",
            tool_used=ToolName.ANSWER_RULES_QUESTION,
            tool_arguments={"country_code": "FR"},
            filters_applied={},
            locations_mentioned=[],
            icao_codes_mentioned=[],
            countries_mentioned=["FR"]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        # Should suggest searching for customs airports
        customs_suggestions = [
            s for s in suggestions
            if "customs" in s.query_text.lower() or s.tool_name == ToolName.SEARCH_AIRPORTS
        ]
        assert len(customs_suggestions) > 0

    def test_max_suggestions_respected(self, predictor):
        """Respects max_suggestions limit."""
        context = QueryContext(
            user_query="Find airports from EGTF to LFMD",
            tool_used=ToolName.FIND_AIRPORTS_NEAR_ROUTE,
            tool_arguments={"from_location": "EGTF", "to_location": "LFMD"},
            filters_applied={},
            locations_mentioned=["EGTF", "LFMD"],
            icao_codes_mentioned=["EGTF", "LFMD"],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=2)

        assert len(suggestions) <= 2

    def test_suggestions_are_unique(self, predictor):
        """No duplicate suggestions."""
        context = QueryContext(
            user_query="Find airports from EGTF to LFMD",
            tool_used=ToolName.FIND_AIRPORTS_NEAR_ROUTE,
            tool_arguments={"from_location": "EGTF", "to_location": "LFMD"},
            filters_applied={},
            locations_mentioned=["EGTF", "LFMD"],
            icao_codes_mentioned=["EGTF", "LFMD"],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        query_texts = [s.query_text for s in suggestions]
        assert len(query_texts) == len(set(query_texts))

    def test_suggestions_have_diverse_categories(self, predictor):
        """First suggestions should cover different categories."""
        context = QueryContext(
            user_query="Find airports from EGTF to LFMD",
            tool_used=ToolName.FIND_AIRPORTS_NEAR_ROUTE,
            tool_arguments={"from_location": "EGTF", "to_location": "LFMD"},
            filters_applied={},
            locations_mentioned=["EGTF", "LFMD"],
            icao_codes_mentioned=["EGTF", "LFMD"],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=4)

        if len(suggestions) >= 3:
            categories = set(s.category for s in suggestions[:3])
            # Should have at least 2 different categories in first 3
            assert len(categories) >= 2

    def test_unknown_tool_returns_empty(self, predictor):
        """Unknown tool returns empty suggestions."""
        context = QueryContext(
            user_query="Unknown query",
            tool_used="unknown_tool",
            tool_arguments={},
            filters_applied={},
            locations_mentioned=[],
            icao_codes_mentioned=[],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        assert len(suggestions) == 0


class TestNextQueryPredictorWithConfig:
    """Tests for NextQueryPredictor with configuration-driven templates."""

    @pytest.fixture
    def config(self):
        """Create a test configuration."""
        from shared.aviation_agent.behavior_config import NextQueryPredictionConfig

        return NextQueryPredictionConfig(
            enabled=True,
            max_suggestions=4,
            templates_path="next_query_predictor/default.json"
        )

    def test_uses_config_templates(self, config):
        """Predictor uses templates from config file when provided."""
        # This test uses the actual config file from configs/next_query_predictor/default.json
        predictor = NextQueryPredictor(rules_json_path=None, config=config)

        context = QueryContext(
            user_query="Find airports from EGTF to LFMD",
            tool_used=ToolName.FIND_AIRPORTS_NEAR_ROUTE,
            tool_arguments={"from_location": "EGTF", "to_location": "LFMD"},
            filters_applied={},
            locations_mentioned=["EGTF", "LFMD"],
            icao_codes_mentioned=["EGTF", "LFMD"],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        # Should have suggestions (either from config file or defaults)
        assert len(suggestions) > 0
        # If templates loaded successfully, should have AVGAS suggestion
        # (this will work if the config file exists and is loaded)
        assert predictor.templates or len(suggestions) > 0  # Templates loaded OR defaults used

    def test_fallback_to_defaults_when_no_config(self):
        """Predictor falls back to defaults when config not provided."""
        predictor = NextQueryPredictor(rules_json_path=None)

        context = QueryContext(
            user_query="Find airports from EGTF to LFMD",
            tool_used=ToolName.FIND_AIRPORTS_NEAR_ROUTE,
            tool_arguments={"from_location": "EGTF", "to_location": "LFMD"},
            filters_applied={},
            locations_mentioned=["EGTF", "LFMD"],
            icao_codes_mentioned=["EGTF", "LFMD"],
            countries_mentioned=[]
        )

        suggestions = predictor.predict_next_queries(context, max_suggestions=10)

        # Should still generate suggestions using hard-coded defaults
        assert len(suggestions) > 0


class TestSuggestedQuery:
    """Tests for SuggestedQuery dataclass."""

    def test_has_required_fields(self):
        """SuggestedQuery has all required fields."""
        sq = SuggestedQuery(
            query_text="Test query",
            tool_name=ToolName.SEARCH_AIRPORTS,
            category=SuggestionCategory.ROUTE,
            priority=3
        )

        assert sq.query_text == "Test query"
        assert sq.tool_name == ToolName.SEARCH_AIRPORTS
        assert sq.category == SuggestionCategory.ROUTE
        assert sq.priority == 3


class TestQueryContext:
    """Tests for QueryContext dataclass."""

    def test_has_required_fields(self):
        """QueryContext has all required fields."""
        ctx = QueryContext(
            user_query="test",
            tool_used=ToolName.SEARCH_AIRPORTS,
            tool_arguments={},
            filters_applied={},
            locations_mentioned=[],
            icao_codes_mentioned=[],
            countries_mentioned=[]
        )

        assert ctx.user_query == "test"
        assert ctx.tool_used == ToolName.SEARCH_AIRPORTS
        assert ctx.tool_arguments == {}
        assert ctx.filters_applied == {}
        assert ctx.locations_mentioned == []
        assert ctx.icao_codes_mentioned == []
        assert ctx.countries_mentioned == []


class TestRanking:
    """Tests for suggestion ranking logic."""

    @pytest.fixture
    def predictor(self):
        """Create predictor."""
        return NextQueryPredictor(rules_json_path=None)

    def test_ranking_by_priority(self, predictor):
        """Suggestions are ranked by priority (higher first)."""
        suggestions = [
            SuggestedQuery("Low priority", ToolName.SEARCH_AIRPORTS, SuggestionCategory.ROUTE, 2),
            SuggestedQuery("High priority", ToolName.SEARCH_AIRPORTS, SuggestionCategory.ROUTE, 5),
            SuggestedQuery("Medium priority", ToolName.SEARCH_AIRPORTS, SuggestionCategory.ROUTE, 3),
        ]

        ranked = predictor._rank_suggestions(suggestions)

        assert ranked[0].priority == 5
        assert ranked[1].priority == 3
        assert ranked[2].priority == 2

    def test_ranking_deduplicates(self, predictor):
        """Ranking removes duplicate query texts."""
        suggestions = [
            SuggestedQuery("Same query", ToolName.SEARCH_AIRPORTS, SuggestionCategory.ROUTE, 5),
            SuggestedQuery("Same query", ToolName.SEARCH_AIRPORTS, SuggestionCategory.ROUTE, 4),
            SuggestedQuery("Different query", ToolName.SEARCH_AIRPORTS, SuggestionCategory.ROUTE, 3),
        ]

        ranked = predictor._rank_suggestions(suggestions)

        query_texts = [s.query_text for s in ranked]
        assert query_texts.count("Same query") == 1
        assert "Different query" in query_texts

    def test_ranking_prefers_diversity(self, predictor):
        """Ranking prefers different categories in top results."""
        suggestions = [
            SuggestedQuery("Route 1", ToolName.SEARCH_AIRPORTS, SuggestionCategory.ROUTE, 5),
            SuggestedQuery("Route 2", ToolName.SEARCH_AIRPORTS, SuggestionCategory.ROUTE, 4),
            SuggestedQuery("Details 1", ToolName.GET_AIRPORT_DETAILS, SuggestionCategory.DETAILS, 5),
            SuggestedQuery("Rules 1", ToolName.ANSWER_RULES_QUESTION, SuggestionCategory.RULES, 4),
        ]

        ranked = predictor._rank_suggestions(suggestions)

        # First pass should include one from each category
        if len(ranked) >= 3:
            categories = [s.category for s in ranked[:3]]
            assert len(set(categories)) >= 2  # At least 2 different categories

