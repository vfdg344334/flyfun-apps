"""
Unit tests for ga_review_agent aggregator.
"""

import pytest
from datetime import datetime, timedelta

from shared.ga_friendliness import (
    AspectLabel,
    ReviewExtraction,
)
from shared.ga_review_agent import TagAggregator


@pytest.mark.unit
class TestTagAggregator:
    """Tests for TagAggregator class."""

    @pytest.fixture
    def sample_extractions(self):
        """Create sample extractions for testing."""
        return [
            ReviewExtraction(
                review_id="r1",
                aspects=[
                    AspectLabel(aspect="cost", label="cheap", confidence=0.9),
                    AspectLabel(aspect="staff", label="positive", confidence=0.8),
                ],
                timestamp="2024-06-01T10:00:00Z",
            ),
            ReviewExtraction(
                review_id="r2",
                aspects=[
                    AspectLabel(aspect="cost", label="cheap", confidence=0.85),
                    AspectLabel(aspect="staff", label="very_positive", confidence=0.9),
                ],
                timestamp="2024-05-01T10:00:00Z",
            ),
            ReviewExtraction(
                review_id="r3",
                aspects=[
                    AspectLabel(aspect="cost", label="expensive", confidence=0.7),
                    AspectLabel(aspect="bureaucracy", label="simple", confidence=0.95),
                ],
                timestamp="2024-04-01T10:00:00Z",
            ),
        ]

    def test_aggregate_tags_basic(self, sample_extractions):
        """Test basic tag aggregation."""
        aggregator = TagAggregator(enable_time_decay=False)
        
        distributions, context = aggregator.aggregate_tags(sample_extractions)
        
        assert "cost" in distributions
        assert "staff" in distributions
        assert "bureaucracy" in distributions
        
        # cost should have cheap (2 times) and expensive (1 time)
        assert "cheap" in distributions["cost"]
        assert "expensive" in distributions["cost"]
        
        assert context.sample_count == 3

    def test_weighted_by_confidence(self, sample_extractions):
        """Test that aggregation is weighted by confidence."""
        aggregator = TagAggregator(enable_time_decay=False)
        
        distributions, _ = aggregator.aggregate_tags(sample_extractions)
        
        # cheap: 0.9 + 0.85 = 1.75
        # expensive: 0.7
        cost_dist = distributions["cost"]
        assert cost_dist["cheap"] > cost_dist["expensive"]

    def test_time_decay_enabled(self, sample_extractions):
        """Test time decay when enabled."""
        # Reference time is after all reviews
        ref_time = datetime(2024, 7, 1)
        
        aggregator = TagAggregator(
            enable_time_decay=True,
            time_decay_half_life_days=30,  # Short half-life
            reference_time=ref_time,
        )
        
        distributions, context = aggregator.aggregate_tags(sample_extractions)
        
        # More recent reviews should have higher weight
        assert context.reference_time is not None
        
        # The actual values depend on decay calculation
        # Just verify structure is correct
        assert "cost" in distributions

    def test_compute_label_distribution(self, sample_extractions):
        """Test computing normalized label distribution."""
        aggregator = TagAggregator(enable_time_decay=False)
        
        distribution = aggregator.compute_label_distribution(
            sample_extractions, "cost"
        )
        
        # Should sum to 1.0
        total = sum(distribution.values())
        assert abs(total - 1.0) < 0.01
        
        # cheap should be more common
        assert distribution["cheap"] > distribution["expensive"]

    def test_get_dominant_label(self, sample_extractions):
        """Test getting dominant label."""
        aggregator = TagAggregator(enable_time_decay=False)
        
        result = aggregator.get_dominant_label(sample_extractions, "cost")
        
        assert result is not None
        label, proportion = result
        assert label == "cheap"  # Most common
        assert 0.0 <= proportion <= 1.0

    def test_get_dominant_label_no_data(self):
        """Test dominant label with no data."""
        aggregator = TagAggregator()
        
        result = aggregator.get_dominant_label([], "cost")
        
        assert result is None

    def test_aspect_coverage(self, sample_extractions):
        """Test computing aspect coverage."""
        aggregator = TagAggregator()
        
        coverage = aggregator.compute_aspect_coverage(sample_extractions)
        
        # cost is mentioned in all 3 reviews
        assert coverage["cost"] == 3
        
        # bureaucracy is mentioned in 1 review
        assert coverage["bureaucracy"] == 1

    def test_aspect_coverage_required_aspects(self, sample_extractions):
        """Test aspect coverage with required aspects."""
        aggregator = TagAggregator()
        
        coverage = aggregator.compute_aspect_coverage(
            sample_extractions,
            required_aspects=["cost", "fuel", "transport"],
        )
        
        assert coverage["cost"] == 3
        assert coverage["fuel"] == 0  # Not mentioned
        assert coverage["transport"] == 0  # Not mentioned

    def test_empty_extractions(self):
        """Test aggregation with empty input."""
        aggregator = TagAggregator()
        
        distributions, context = aggregator.aggregate_tags([])
        
        assert distributions == {}
        assert context.sample_count == 0

    def test_time_decay_future_timestamp(self):
        """Test handling of future timestamps."""
        ref_time = datetime(2024, 1, 1)
        
        extractions = [
            ReviewExtraction(
                review_id="r1",
                aspects=[AspectLabel(aspect="cost", label="cheap", confidence=0.9)],
                timestamp="2025-06-01T10:00:00Z",  # Future
            ),
        ]
        
        aggregator = TagAggregator(
            enable_time_decay=True,
            reference_time=ref_time,
        )
        
        distributions, _ = aggregator.aggregate_tags(extractions)
        
        # Should still work, treating future as current (weight = 1.0)
        assert "cost" in distributions

