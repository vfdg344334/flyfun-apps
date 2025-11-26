"""
Unit tests for ga_friendliness ontology management.
"""

import pytest

from shared.ga_friendliness import (
    OntologyManager,
    OntologyConfig,
    ReviewExtraction,
    AspectLabel,
)


@pytest.mark.unit
class TestOntologyManager:
    """Tests for OntologyManager class."""

    def test_create_manager(self, sample_ontology):
        """Test creating OntologyManager."""
        manager = OntologyManager(sample_ontology)
        assert manager.version == "1.0-test"

    def test_validate_aspect_valid(self, sample_ontology):
        """Test validating valid aspect."""
        manager = OntologyManager(sample_ontology)
        assert manager.validate_aspect("cost") is True
        assert manager.validate_aspect("staff") is True

    def test_validate_aspect_invalid(self, sample_ontology):
        """Test validating invalid aspect."""
        manager = OntologyManager(sample_ontology)
        assert manager.validate_aspect("nonexistent") is False

    def test_validate_label_valid(self, sample_ontology):
        """Test validating valid label."""
        manager = OntologyManager(sample_ontology)
        assert manager.validate_label("cost", "cheap") is True
        assert manager.validate_label("cost", "expensive") is True

    def test_validate_label_invalid(self, sample_ontology):
        """Test validating invalid label."""
        manager = OntologyManager(sample_ontology)
        assert manager.validate_label("cost", "invalid_label") is False
        assert manager.validate_label("nonexistent", "cheap") is False

    def test_get_allowed_labels(self, sample_ontology):
        """Test getting allowed labels."""
        manager = OntologyManager(sample_ontology)
        labels = manager.get_allowed_labels("cost")
        assert "cheap" in labels
        assert "expensive" in labels
        assert len(labels) == 4

    def test_get_aspects(self, sample_ontology):
        """Test getting all aspects."""
        manager = OntologyManager(sample_ontology)
        aspects = manager.get_aspects()
        assert "cost" in aspects
        assert "staff" in aspects
        assert "bureaucracy" in aspects

    def test_validate_extraction_valid(self, sample_ontology, sample_extraction):
        """Test validating valid extraction."""
        manager = OntologyManager(sample_ontology)
        errors = manager.validate_extraction(sample_extraction)
        assert len(errors) == 0

    def test_validate_extraction_invalid_aspect(self, sample_ontology):
        """Test validating extraction with invalid aspect."""
        manager = OntologyManager(sample_ontology)
        extraction = ReviewExtraction(
            aspects=[
                AspectLabel(aspect="invalid_aspect", label="value", confidence=0.9),
            ]
        )
        errors = manager.validate_extraction(extraction)
        assert len(errors) == 1
        assert "Unknown aspect" in errors[0]

    def test_validate_extraction_invalid_label(self, sample_ontology):
        """Test validating extraction with invalid label."""
        manager = OntologyManager(sample_ontology)
        extraction = ReviewExtraction(
            aspects=[
                AspectLabel(aspect="cost", label="invalid_label", confidence=0.9),
            ]
        )
        errors = manager.validate_extraction(extraction)
        assert len(errors) == 1
        assert "Invalid label" in errors[0]

    def test_filter_extraction_removes_invalid(self, sample_ontology):
        """Test filtering removes invalid aspects."""
        manager = OntologyManager(sample_ontology)
        extraction = ReviewExtraction(
            aspects=[
                AspectLabel(aspect="cost", label="cheap", confidence=0.9),
                AspectLabel(aspect="invalid", label="value", confidence=0.8),
                AspectLabel(aspect="cost", label="invalid_label", confidence=0.85),
            ]
        )
        
        filtered = manager.filter_extraction(extraction)
        assert len(filtered.aspects) == 1
        assert filtered.aspects[0].label == "cheap"

    def test_filter_extraction_confidence_threshold(self, sample_ontology):
        """Test filtering by confidence threshold."""
        manager = OntologyManager(sample_ontology)
        extraction = ReviewExtraction(
            aspects=[
                AspectLabel(aspect="cost", label="cheap", confidence=0.9),
                AspectLabel(aspect="staff", label="positive", confidence=0.3),
            ]
        )
        
        filtered = manager.filter_extraction(extraction, confidence_threshold=0.5)
        assert len(filtered.aspects) == 1
        assert filtered.aspects[0].aspect == "cost"

    def test_get_prompt_context(self, sample_ontology):
        """Test generating prompt context."""
        manager = OntologyManager(sample_ontology)
        context = manager.get_prompt_context()
        
        assert "cost" in context
        assert "cheap" in context
        assert "expensive" in context
        assert "staff" in context

