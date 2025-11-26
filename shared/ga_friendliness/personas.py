"""
Persona loading and score computation.

Manages personas and computes persona-specific scores from features.
"""

from typing import Dict, List, Optional

from .models import (
    AirportFeatureScores,
    MissingBehavior,
    PersonaConfig,
    PersonaMissingBehaviors,
    PersonasConfig,
)


# Feature names for iteration
FEATURE_NAMES = [
    "ga_cost_score",
    "ga_review_score",
    "ga_hassle_score",
    "ga_ops_ifr_score",
    "ga_ops_vfr_score",
    "ga_access_score",
    "ga_fun_score",
    "ga_hospitality_score",
]


class PersonaManager:
    """
    Manages personas and computes persona-specific scores.
    
    Handles missing values according to each persona's configuration.
    """

    def __init__(self, config: PersonasConfig):
        """
        Initialize with loaded personas.
        
        Args:
            config: Validated PersonasConfig
        """
        self.config = config

    @property
    def version(self) -> str:
        """Get personas config version."""
        return self.config.version

    def get_persona(self, persona_id: str) -> Optional[PersonaConfig]:
        """Get persona by ID."""
        return self.config.personas.get(persona_id)

    def list_persona_ids(self) -> List[str]:
        """List all persona IDs."""
        return list(self.config.personas.keys())

    def list_personas(self) -> List[PersonaConfig]:
        """List all persona configs."""
        return list(self.config.personas.values())

    def _resolve_missing_value(
        self,
        value: Optional[float],
        behavior: MissingBehavior
    ) -> tuple[Optional[float], bool]:
        """
        Resolve missing value based on behavior.
        
        Returns:
            Tuple of (resolved_value, should_include)
            If should_include is False, this feature should be excluded.
        """
        if value is not None:
            return value, True

        if behavior == MissingBehavior.EXCLUDE:
            return None, False
        elif behavior == MissingBehavior.NEGATIVE:
            return 0.0, True
        elif behavior == MissingBehavior.POSITIVE:
            return 1.0, True
        else:  # NEUTRAL
            return 0.5, True

    def compute_score(
        self,
        persona_id: str,
        features: AirportFeatureScores
    ) -> Optional[float]:
        """
        Compute persona-specific score from base features.
        
        Handles missing (None) feature values based on persona's missing_behaviors:
            - NEUTRAL: treat as 0.5 (average)
            - NEGATIVE: treat as 0.0 (worst case - feature is required)
            - POSITIVE: treat as 1.0 (best case - rare)
            - EXCLUDE: skip this feature, re-normalize remaining weights
        
        Args:
            persona_id: ID of persona to compute score for
            features: Airport feature scores
            
        Returns:
            Score in [0, 1] range, or None if persona not found
        """
        persona = self.get_persona(persona_id)
        if persona is None:
            return None

        missing_behaviors = persona.missing_behaviors or PersonaMissingBehaviors()

        total_score = 0.0
        total_weight = 0.0

        for feature_name in FEATURE_NAMES:
            weight = getattr(persona.weights, feature_name, 0.0)
            if weight == 0.0:
                continue  # Feature not used by this persona

            value = getattr(features, feature_name, None)
            behavior = getattr(missing_behaviors, feature_name, MissingBehavior.NEUTRAL)

            resolved_value, should_include = self._resolve_missing_value(value, behavior)

            if not should_include:
                continue  # Excluded feature

            if resolved_value is not None:
                total_score += weight * resolved_value
                total_weight += weight

        # Normalize by total active weight (handles EXCLUDE behavior)
        if total_weight > 0:
            return total_score / total_weight

        return 0.5  # Default if no features available

    def compute_scores_for_all_personas(
        self,
        features: AirportFeatureScores
    ) -> Dict[str, float]:
        """
        Compute scores for all personas.
        
        Args:
            features: Airport feature scores
            
        Returns:
            Dict mapping persona_id -> score
        """
        scores = {}
        for persona_id in self.list_persona_ids():
            score = self.compute_score(persona_id, features)
            if score is not None:
                scores[persona_id] = score
        return scores

    def get_top_personas_for_airport(
        self,
        features: AirportFeatureScores,
        n: int = 3
    ) -> List[tuple[str, float]]:
        """
        Get top N personas for an airport by score.
        
        Args:
            features: Airport feature scores
            n: Number of top personas to return
            
        Returns:
            List of (persona_id, score) tuples, sorted by score descending
        """
        scores = self.compute_scores_for_all_personas(features)
        sorted_scores = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        return sorted_scores[:n]

    def explain_score(
        self,
        persona_id: str,
        features: AirportFeatureScores
    ) -> Dict[str, dict]:
        """
        Explain how a persona score was computed.
        
        Useful for transparency and debugging.
        
        Returns:
            Dict with feature-level breakdown
        """
        persona = self.get_persona(persona_id)
        if persona is None:
            return {}

        missing_behaviors = persona.missing_behaviors or PersonaMissingBehaviors()

        explanation = {
            "persona_id": persona_id,
            "persona_label": persona.label,
            "features": {},
            "total_weight": 0.0,
            "total_score": 0.0,
        }

        for feature_name in FEATURE_NAMES:
            weight = getattr(persona.weights, feature_name, 0.0)
            if weight == 0.0:
                continue

            value = getattr(features, feature_name, None)
            behavior = getattr(missing_behaviors, feature_name, MissingBehavior.NEUTRAL)
            resolved_value, should_include = self._resolve_missing_value(value, behavior)

            feature_info = {
                "weight": weight,
                "raw_value": value,
                "resolved_value": resolved_value,
                "missing_behavior": behavior.value if value is None else None,
                "included": should_include,
                "contribution": weight * resolved_value if should_include and resolved_value else 0,
            }

            explanation["features"][feature_name] = feature_info

            if should_include and resolved_value is not None:
                explanation["total_weight"] += weight
                explanation["total_score"] += weight * resolved_value

        if explanation["total_weight"] > 0:
            explanation["final_score"] = (
                explanation["total_score"] / explanation["total_weight"]
            )
        else:
            explanation["final_score"] = 0.5

        return explanation

