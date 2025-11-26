"""
Ontology validation and lookup.

Manages the aspect/label ontology used for review extraction.
"""

from typing import List, Optional

from .exceptions import OntologyValidationError
from .models import OntologyConfig, ReviewExtraction


class OntologyManager:
    """
    Manages ontology aspects and labels.
    
    Provides validation and lookup operations for the ontology.
    """

    def __init__(self, config: OntologyConfig):
        """
        Initialize with loaded ontology.
        
        Args:
            config: Validated OntologyConfig
        """
        self.config = config
        self._aspects_set = set(config.aspects.keys())
        self._labels_by_aspect = {
            aspect: set(labels) for aspect, labels in config.aspects.items()
        }

    @property
    def version(self) -> str:
        """Get ontology version."""
        return self.config.version

    def validate_aspect(self, aspect: str) -> bool:
        """Check if aspect exists in ontology."""
        return aspect in self._aspects_set

    def validate_label(self, aspect: str, label: str) -> bool:
        """Check if label is allowed for aspect."""
        return label in self._labels_by_aspect.get(aspect, set())

    def get_allowed_labels(self, aspect: str) -> List[str]:
        """Get list of allowed labels for an aspect."""
        return self.config.aspects.get(aspect, [])

    def get_aspects(self) -> List[str]:
        """Get list of all aspects."""
        return list(self.config.aspects.keys())

    def validate_extraction(self, extraction: ReviewExtraction) -> List[str]:
        """
        Validate a ReviewExtraction against ontology.
        
        Args:
            extraction: ReviewExtraction to validate
            
        Returns:
            List of validation error messages (empty if valid).
        """
        errors = []

        for aspect_label in extraction.aspects:
            # Validate aspect exists
            if not self.validate_aspect(aspect_label.aspect):
                errors.append(
                    f"Unknown aspect '{aspect_label.aspect}'"
                )
                continue

            # Validate label for aspect
            if not self.validate_label(aspect_label.aspect, aspect_label.label):
                errors.append(
                    f"Invalid label '{aspect_label.label}' for aspect '{aspect_label.aspect}'. "
                    f"Allowed: {self.get_allowed_labels(aspect_label.aspect)}"
                )

            # Validate confidence in range
            if not 0.0 <= aspect_label.confidence <= 1.0:
                errors.append(
                    f"Confidence {aspect_label.confidence} out of range [0, 1] "
                    f"for {aspect_label.aspect}:{aspect_label.label}"
                )

        return errors

    def filter_extraction(
        self,
        extraction: ReviewExtraction,
        confidence_threshold: float = 0.0
    ) -> ReviewExtraction:
        """
        Filter extraction to only include valid aspects/labels above threshold.
        
        Args:
            extraction: ReviewExtraction to filter
            confidence_threshold: Minimum confidence to include
            
        Returns:
            New ReviewExtraction with only valid, high-confidence aspects
        """
        filtered_aspects = []

        for aspect_label in extraction.aspects:
            # Skip invalid aspects/labels
            if not self.validate_aspect(aspect_label.aspect):
                continue
            if not self.validate_label(aspect_label.aspect, aspect_label.label):
                continue

            # Skip low confidence
            if aspect_label.confidence < confidence_threshold:
                continue

            filtered_aspects.append(aspect_label)

        return ReviewExtraction(
            review_id=extraction.review_id,
            aspects=filtered_aspects,
            raw_text_excerpt=extraction.raw_text_excerpt,
            timestamp=extraction.timestamp,
        )

    def get_prompt_context(self) -> str:
        """
        Generate ontology context for LLM prompts.
        
        Returns:
            String describing aspects and their allowed labels for use in prompts.
        """
        lines = ["Available aspects and their allowed labels:"]
        for aspect, labels in self.config.aspects.items():
            labels_str = ", ".join(labels)
            lines.append(f"- {aspect}: [{labels_str}]")
        return "\n".join(lines)

