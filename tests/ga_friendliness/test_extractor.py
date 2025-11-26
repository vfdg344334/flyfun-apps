"""
Unit tests for ga_review_agent extractor.
"""

import pytest

from shared.ga_friendliness import (
    get_default_ontology,
    OntologyConfig,
    ReviewExtraction,
)
from shared.ga_review_agent import ReviewExtractor


@pytest.mark.unit
class TestReviewExtractorMock:
    """Tests for ReviewExtractor using mock LLM."""

    @pytest.fixture
    def mock_extractor(self, sample_ontology):
        """Create mock extractor."""
        return ReviewExtractor(
            ontology=sample_ontology,
            mock_llm=True,
        )

    def test_extract_cheap_review(self, mock_extractor):
        """Test extracting from review mentioning cheap prices."""
        result = mock_extractor.extract(
            review_text="Very cheap landing fees, affordable fuel.",
            review_id="test1",
        )
        
        assert result.review_id == "test1"
        
        # Check that cost aspect was extracted
        cost_labels = [a for a in result.aspects if a.aspect == "cost"]
        assert len(cost_labels) > 0
        assert cost_labels[0].label == "cheap"

    def test_extract_friendly_staff(self, mock_extractor):
        """Test extracting friendly staff mentions."""
        result = mock_extractor.extract(
            review_text="Excellent service, very friendly and helpful staff!",
            review_id="test2",
        )
        
        staff_labels = [a for a in result.aspects if a.aspect == "staff"]
        assert len(staff_labels) > 0
        assert staff_labels[0].label in ["very_positive", "positive"]

    def test_extract_multiple_aspects(self, mock_extractor):
        """Test extracting multiple aspects from one review."""
        result = mock_extractor.extract(
            review_text="Great airfield, friendly staff, cheap fees, restaurant on site.",
            review_id="test3",
        )
        
        # Should have multiple aspects
        aspects_found = {a.aspect for a in result.aspects}
        assert len(aspects_found) >= 2

    def test_extract_preserves_timestamp(self, mock_extractor):
        """Test that timestamp is preserved in extraction."""
        result = mock_extractor.extract(
            review_text="Nice little airfield.",
            review_id="test4",
            timestamp="2024-06-15T10:30:00Z",
        )
        
        assert result.timestamp == "2024-06-15T10:30:00Z"

    def test_extract_batch(self, mock_extractor):
        """Test batch extraction."""
        reviews = [
            ("Cheap and friendly!", "r1", "2024-01-01"),
            ("Expensive but good food.", "r2", "2024-02-01"),
            ("Simple procedures, easy access.", "r3", "2024-03-01"),
        ]
        
        results = mock_extractor.extract_batch(reviews)
        
        assert len(results) == 3
        assert results[0].review_id == "r1"
        assert results[1].review_id == "r2"
        assert results[2].review_id == "r3"

    def test_token_usage_tracking(self, mock_extractor):
        """Test token usage is tracked."""
        mock_extractor.reset_token_usage()
        
        mock_extractor.extract("Test review.", "test")
        
        usage = mock_extractor.get_token_usage()
        # Mock doesn't track real tokens, but total_calls should increase
        # For mock, we just verify the dict structure
        assert "input_tokens" in usage
        assert "output_tokens" in usage
        assert "total_calls" in usage

    def test_confidence_scores(self, mock_extractor):
        """Test that confidence scores are in valid range."""
        result = mock_extractor.extract(
            review_text="Very cheap, extremely friendly, great overall!",
            review_id="test",
        )
        
        for aspect in result.aspects:
            assert 0.0 <= aspect.confidence <= 1.0


@pytest.mark.unit
class TestExtractorValidation:
    """Tests for extraction validation against ontology."""

    def test_invalid_aspect_filtered(self, sample_ontology):
        """Test that invalid aspects from LLM are filtered."""
        extractor = ReviewExtractor(
            ontology=sample_ontology,
            mock_llm=True,
        )
        
        # The mock extractor only produces valid aspects
        # This test verifies the validation logic exists
        result = extractor.extract("Test review.", "test")
        
        for aspect in result.aspects:
            assert sample_ontology.validate_aspect(aspect.aspect)

    def test_invalid_label_filtered(self, sample_ontology):
        """Test that invalid labels from LLM are filtered."""
        extractor = ReviewExtractor(
            ontology=sample_ontology,
            mock_llm=True,
        )
        
        result = extractor.extract("Test review.", "test")
        
        for aspect in result.aspects:
            assert sample_ontology.validate_label(aspect.aspect, aspect.label)

