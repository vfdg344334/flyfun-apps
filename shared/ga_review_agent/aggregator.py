"""
Tag aggregation for GA friendliness scoring.

Aggregates extracted tags into feature distributions and scores.
"""

import logging
import math
from collections import defaultdict
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

from shared.ga_friendliness.models import (
    AggregationContext,
    AspectLabel,
    ReviewExtraction,
)
from shared.ga_friendliness.storage import parse_timestamp

logger = logging.getLogger(__name__)


class TagAggregator:
    """
    Aggregates review tags into distributions and feature scores.
    
    Features:
        - Weighted aggregation by confidence
        - Optional time decay (recent reviews weighted more)
        - Label distribution computation
    """

    def __init__(
        self,
        enable_time_decay: bool = False,
        time_decay_half_life_days: float = 365.0,
        reference_time: Optional[datetime] = None,
    ):
        """
        Initialize aggregator.
        
        Args:
            enable_time_decay: Apply time decay to review weights
            time_decay_half_life_days: Half-life for exponential decay
            reference_time: Reference time for decay calculation (None = now)
        """
        self.enable_time_decay = enable_time_decay
        self.time_decay_half_life_days = time_decay_half_life_days
        self.reference_time = reference_time or datetime.now(timezone.utc).replace(tzinfo=None)

    def _compute_time_weight(self, timestamp_str: Optional[str]) -> float:
        """
        Compute time-based weight using exponential decay.
        
        Formula: weight = 0.5 ^ (age_days / half_life_days)
        
        Returns 1.0 if time decay disabled or timestamp not available.
        """
        if not self.enable_time_decay or not timestamp_str:
            return 1.0
        
        try:
            review_time = parse_timestamp(timestamp_str)
            age_days = (self.reference_time - review_time).days
            
            if age_days < 0:
                # Future timestamp - treat as current
                return 1.0
            
            # Exponential decay: 0.5 ^ (age / half_life)
            decay = math.pow(0.5, age_days / self.time_decay_half_life_days)
            return max(0.01, decay)  # Minimum weight of 1%
            
        except (ValueError, TypeError):
            return 1.0

    def aggregate_tags(
        self,
        extractions: List[ReviewExtraction],
    ) -> Tuple[Dict[str, Dict[str, float]], AggregationContext]:
        """
        Aggregate tags from multiple reviews into distributions.
        
        Args:
            extractions: List of ReviewExtraction objects
        
        Returns:
            Tuple of:
                - Dict mapping aspect -> label -> weighted count
                - AggregationContext with metadata
        """
        # Initialize distributions
        distributions: Dict[str, Dict[str, float]] = defaultdict(lambda: defaultdict(float))
        total_weight = 0.0
        
        for extraction in extractions:
            time_weight = self._compute_time_weight(extraction.timestamp)
            
            for aspect_label in extraction.aspects:
                # Combined weight = confidence * time_weight
                weight = aspect_label.confidence * time_weight
                distributions[aspect_label.aspect][aspect_label.label] += weight
                total_weight += weight
        
        # Convert to regular dicts
        result = {
            aspect: dict(labels)
            for aspect, labels in distributions.items()
        }
        
        context = AggregationContext(
            sample_count=len(extractions),
            reference_time=self.reference_time if self.enable_time_decay else None,
        )
        
        return result, context

    def compute_label_distribution(
        self,
        extractions: List[ReviewExtraction],
        aspect: str,
    ) -> Dict[str, float]:
        """
        Compute normalized label distribution for a specific aspect.
        
        Returns dict mapping label -> probability (0-1, sums to 1).
        """
        distributions, _ = self.aggregate_tags(extractions)
        aspect_dist = distributions.get(aspect, {})
        
        if not aspect_dist:
            return {}
        
        total = sum(aspect_dist.values())
        if total == 0:
            return {}
        
        return {label: count / total for label, count in aspect_dist.items()}

    def get_dominant_label(
        self,
        extractions: List[ReviewExtraction],
        aspect: str,
    ) -> Optional[Tuple[str, float]]:
        """
        Get the most common label for an aspect.
        
        Returns:
            Tuple of (label, proportion) or None if no data
        """
        distribution = self.compute_label_distribution(extractions, aspect)
        
        if not distribution:
            return None
        
        max_label = max(distribution, key=distribution.get)
        return (max_label, distribution[max_label])

    def aggregate_by_icao(
        self,
        extractions: List[ReviewExtraction],
    ) -> Dict[str, List[ReviewExtraction]]:
        """
        Group extractions by ICAO (if review_id contains ICAO info).
        
        Note: This is a utility method. Typically extractions are already
        grouped by airport before aggregation.
        """
        by_icao: Dict[str, List[ReviewExtraction]] = defaultdict(list)
        
        for extraction in extractions:
            # Try to extract ICAO from review_id if present
            if extraction.review_id:
                # Assuming review_id format might be "ICAO_xxx" or similar
                parts = extraction.review_id.split("_")
                if len(parts) > 0 and len(parts[0]) == 4:
                    icao = parts[0].upper()
                    by_icao[icao].append(extraction)
                else:
                    by_icao["UNKNOWN"].append(extraction)
            else:
                by_icao["UNKNOWN"].append(extraction)
        
        return dict(by_icao)

    def compute_aspect_coverage(
        self,
        extractions: List[ReviewExtraction],
        required_aspects: Optional[List[str]] = None,
    ) -> Dict[str, int]:
        """
        Compute how many reviews mention each aspect.
        
        Args:
            extractions: List of extractions
            required_aspects: Optional list of aspects to check
        
        Returns:
            Dict mapping aspect -> count of reviews mentioning it
        """
        aspect_counts: Dict[str, int] = defaultdict(int)
        
        for extraction in extractions:
            seen_aspects = set()
            for aspect_label in extraction.aspects:
                if aspect_label.aspect not in seen_aspects:
                    aspect_counts[aspect_label.aspect] += 1
                    seen_aspects.add(aspect_label.aspect)
        
        # Include required aspects with 0 count if not present
        if required_aspects:
            for aspect in required_aspects:
                if aspect not in aspect_counts:
                    aspect_counts[aspect] = 0
        
        return dict(aspect_counts)

