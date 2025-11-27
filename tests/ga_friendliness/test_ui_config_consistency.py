"""
Tests for UI config consistency.

Ensures that:
- All feature names have display names and descriptions
- Personas only reference known features
- Relevance buckets are properly configured
"""

import pytest

from shared.ga_friendliness import (
    FEATURE_NAMES,
    get_default_personas,
)
from shared.ga_friendliness.ui_config import (
    FEATURE_DISPLAY_NAMES,
    FEATURE_DESCRIPTIONS,
    RELEVANCE_BUCKETS,
    validate_config_consistency,
    get_ui_config,
)


class TestFeatureNameConsistency:
    """Test that all features are properly documented."""

    def test_all_features_have_display_names(self):
        """Every feature in FEATURE_NAMES must have a display name."""
        for feature in FEATURE_NAMES:
            assert feature in FEATURE_DISPLAY_NAMES, f"Missing display name for {feature}"

    def test_all_features_have_descriptions(self):
        """Every feature in FEATURE_NAMES must have a description."""
        for feature in FEATURE_NAMES:
            assert feature in FEATURE_DESCRIPTIONS, f"Missing description for {feature}"

    def test_no_extra_display_names(self):
        """Display names should not include unknown features."""
        for key in FEATURE_DISPLAY_NAMES:
            assert key in FEATURE_NAMES, f"Extra display name for unknown feature: {key}"

    def test_no_extra_descriptions(self):
        """Descriptions should not include unknown features."""
        for key in FEATURE_DESCRIPTIONS:
            assert key in FEATURE_NAMES, f"Extra description for unknown feature: {key}"

    def test_feature_count_matches(self):
        """All dictionaries should have same number of entries as FEATURE_NAMES."""
        assert len(FEATURE_DISPLAY_NAMES) == len(FEATURE_NAMES)
        assert len(FEATURE_DESCRIPTIONS) == len(FEATURE_NAMES)


class TestPersonaWeightsConsistency:
    """Test that personas only reference known features."""

    def test_persona_weights_use_valid_features(self):
        """Persona weights must only reference known features."""
        personas = get_default_personas()
        for persona_id, persona in personas.personas.items():
            for weight_key in persona.weights.model_dump().keys():
                if getattr(persona.weights, weight_key, 0) > 0:
                    assert weight_key in FEATURE_NAMES, \
                        f"Persona {persona_id} references unknown feature: {weight_key}"

    def test_all_personas_have_positive_weights(self):
        """Each persona should have at least one positive weight."""
        personas = get_default_personas()
        for persona_id, persona in personas.personas.items():
            total = persona.weights.total_weight()
            assert total > 0, f"Persona {persona_id} has no positive weights"

    def test_persona_weights_are_reasonable(self):
        """Persona weights should sum to approximately 1.0."""
        personas = get_default_personas()
        for persona_id, persona in personas.personas.items():
            total = persona.weights.total_weight()
            assert 0.95 <= total <= 1.05, \
                f"Persona {persona_id} weights sum to {total}, expected ~1.0"


class TestRelevanceBuckets:
    """Test relevance bucket configuration."""

    def test_relevance_buckets_have_required_fields(self):
        """Relevance buckets should have id, label, and color."""
        for bucket in RELEVANCE_BUCKETS:
            assert "id" in bucket, f"Bucket missing 'id': {bucket}"
            assert "label" in bucket, f"Bucket missing 'label': {bucket}"
            assert "color" in bucket, f"Bucket missing 'color': {bucket}"

    def test_relevance_buckets_have_hex_colors(self):
        """Bucket colors should be valid hex colors."""
        for bucket in RELEVANCE_BUCKETS:
            assert bucket["color"].startswith("#"), f"Bucket color should be hex: {bucket}"
            assert len(bucket["color"]) == 7, f"Bucket color should be #RRGGBB: {bucket}"

    def test_relevance_buckets_have_unknown(self):
        """Relevance buckets should include 'unknown' for missing data."""
        bucket_ids = [b["id"] for b in RELEVANCE_BUCKETS]
        assert "unknown" in bucket_ids, "Must have 'unknown' bucket for missing data"

    def test_relevance_buckets_have_quartiles(self):
        """Relevance buckets should have all quartile buckets."""
        bucket_ids = [b["id"] for b in RELEVANCE_BUCKETS]
        expected = ["top-quartile", "second-quartile", "third-quartile", "bottom-quartile"]
        for expected_id in expected:
            assert expected_id in bucket_ids, f"Missing quartile bucket: {expected_id}"


class TestValidateConfigConsistency:
    """Test the validation helper function."""

    def test_validate_config_consistency_passes(self):
        """validate_config_consistency should return no errors for valid config."""
        errors = validate_config_consistency()
        assert errors == [], f"Validation errors: {errors}"


class TestGetUIConfig:
    """Test the get_ui_config helper function."""

    def test_get_ui_config_returns_all_fields(self):
        """get_ui_config should return all required fields."""
        config = get_ui_config()
        
        assert "feature_names" in config
        assert "feature_display_names" in config
        assert "feature_descriptions" in config
        assert "relevance_buckets" in config

    def test_get_ui_config_feature_names_match(self):
        """get_ui_config feature_names should match FEATURE_NAMES."""
        config = get_ui_config()
        assert config["feature_names"] == FEATURE_NAMES

