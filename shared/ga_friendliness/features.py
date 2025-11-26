"""
Feature engineering for GA friendliness scoring.

Maps label distributions to normalized feature scores [0, 1].
"""

import logging
from typing import Any, Dict, List, Optional

from .exceptions import FeatureMappingError
from .models import (
    AggregationContext,
    AirportFeatureScores,
    FeatureMappingConfig,
    FeatureMappingsConfig,
    OntologyConfig,
    ReviewExtraction,
)

logger = logging.getLogger(__name__)


# Aircraft type to MTOW mapping (kg)
AIRCRAFT_MTOW_MAP: Dict[str, int] = {
    # Light singles (0-749 kg band)
    "c150": 726,       # Cessna 150
    "c152": 757,       # Cessna 152
    
    # Light singles (750-1199 kg band)
    "pa28": 1111,      # Piper PA-28
    "c172": 1157,      # Cessna 172
    
    # Complex singles (1200-1499 kg band)
    "c182": 1406,      # Cessna 182
    "m20": 1315,       # Mooney M20
    
    # High-performance singles (1500-1999 kg band)
    "pa32": 1542,      # Piper PA-32
    "sr22": 1633,      # Cirrus SR22
    "c210": 1814,      # Cessna 210
    "da42": 1785,      # Diamond DA42
    "be76": 1769,      # Beech Duchess
    
    # Light twins (2000-3999 kg band)
    "pa34": 2155,      # Piper Seneca
    "be58": 2449,      # Beech Baron
    "tbm85": 3354,     # TBM 850
    "tbm9": 3354,      # TBM 900 series
    "pc6": 2800,       # Pilatus PC-6
    
    # Turboprops/Light jets (4000+ kg band)
    "pc12": 4740,      # Pilatus PC-12
    "c510": 4536,      # Cessna Citation Mustang
    "c525": 5670,      # Citation CJ series
}


def get_mtow_for_aircraft(aircraft_type: str) -> Optional[int]:
    """
    Get MTOW for a known aircraft type.
    
    Args:
        aircraft_type: Aircraft type code (e.g., "c172", "sr22")
    
    Returns:
        MTOW in kg, or None if aircraft type unknown
    """
    return AIRCRAFT_MTOW_MAP.get(aircraft_type.lower())


def get_fee_band_for_mtow(mtow_kg: int) -> str:
    """
    Get fee band name for a given MTOW.
    
    Fee bands:
        - 0-749 kg
        - 750-1199 kg
        - 1200-1499 kg
        - 1500-1999 kg
        - 2000-3999 kg
        - 4000+ kg
    
    Args:
        mtow_kg: MTOW in kg
    
    Returns:
        Fee band name (e.g., "fee_band_0_749kg")
    """
    if mtow_kg < 750:
        return "fee_band_0_749kg"
    elif mtow_kg < 1200:
        return "fee_band_750_1199kg"
    elif mtow_kg < 1500:
        return "fee_band_1200_1499kg"
    elif mtow_kg < 2000:
        return "fee_band_1500_1999kg"
    elif mtow_kg < 4000:
        return "fee_band_2000_3999kg"
    else:
        return "fee_band_4000_plus_kg"


def aggregate_fees_by_band(
    fee_data: Dict[str, Any],
) -> Dict[str, Optional[float]]:
    """
    Aggregate fee data from source into fee bands.
    
    Maps aircraft types from source data to fee bands.
    
    Args:
        fee_data: Fee data dict from source (e.g., airfield.directory aerops)
            Expected format: { "aircraft_type": { "landing": price, ... }, ... }
            or { "aircraft_type": price, ... }
    
    Returns:
        Dict mapping fee band names to average fees
    """
    bands: Dict[str, List[float]] = {
        "fee_band_0_749kg": [],
        "fee_band_750_1199kg": [],
        "fee_band_1200_1499kg": [],
        "fee_band_1500_1999kg": [],
        "fee_band_2000_3999kg": [],
        "fee_band_4000_plus_kg": [],
    }
    
    for aircraft_type, data in fee_data.items():
        mtow = get_mtow_for_aircraft(aircraft_type)
        if mtow is None:
            continue
        
        # Extract landing fee
        if isinstance(data, dict):
            fee = data.get("landing") or data.get("total")
        else:
            fee = data
        
        if fee is not None:
            try:
                fee_value = float(fee)
                band = get_fee_band_for_mtow(mtow)
                bands[band].append(fee_value)
            except (ValueError, TypeError):
                pass
    
    # Calculate averages
    result: Dict[str, Optional[float]] = {}
    for band, fees in bands.items():
        if fees:
            result[band] = sum(fees) / len(fees)
        else:
            result[band] = None
    
    return result


# Default label score mappings
DEFAULT_LABEL_SCORES: Dict[str, Dict[str, float]] = {
    "cost": {
        "cheap": 1.0,
        "reasonable": 0.7,
        "expensive": 0.2,
        "unclear": 0.5,
    },
    "staff": {
        "very_positive": 1.0,
        "positive": 0.8,
        "neutral": 0.5,
        "negative": 0.2,
        "very_negative": 0.0,
    },
    "bureaucracy": {
        "simple": 1.0,
        "moderate": 0.6,
        "complex": 0.2,
    },
    "fuel": {
        "excellent": 1.0,
        "ok": 0.7,
        "poor": 0.3,
        "unavailable": 0.0,
    },
    "transport": {
        "excellent": 1.0,
        "good": 0.8,
        "ok": 0.5,
        "poor": 0.2,
        "none": 0.0,
    },
    "food": {
        "excellent": 1.0,
        "good": 0.8,
        "ok": 0.5,
        "poor": 0.2,
        "none": 0.0,
    },
    "restaurant": {
        "on_site": 1.0,
        "walking": 0.8,
        "nearby": 0.6,
        "available": 0.4,
        "none": 0.0,
    },
    "accommodation": {
        "on_site": 1.0,
        "walking": 0.8,
        "nearby": 0.6,
        "available": 0.4,
        "none": 0.0,
    },
    "overall_experience": {
        "very_positive": 1.0,
        "positive": 0.8,
        "neutral": 0.5,
        "negative": 0.2,
        "very_negative": 0.0,
    },
    "runway": {
        "excellent": 1.0,
        "ok": 0.6,
        "poor": 0.2,
    },
    "noise_neighbours": {
        "not_an_issue": 1.0,
        "minor_concern": 0.6,
        "significant_issue": 0.2,
    },
    "training_traffic": {
        "busy": 0.3,
        "moderate": 0.6,
        "quiet": 0.9,
        "none": 1.0,
    },
}


class FeatureMapper:
    """
    Maps label distributions to normalized feature scores.
    
    Uses configurable mappings to convert aspect/label distributions
    into [0, 1] feature scores for persona-based scoring.
    """

    def __init__(
        self,
        ontology: Optional[OntologyConfig] = None,
        mappings: Optional[FeatureMappingsConfig] = None,
    ):
        """
        Initialize feature mapper.
        
        Args:
            ontology: Ontology config for validation
            mappings: Custom feature mappings (uses defaults if not provided)
        """
        self.ontology = ontology
        self.custom_mappings = mappings
        self.label_scores = DEFAULT_LABEL_SCORES.copy()
        
        # Apply custom mappings if provided
        if mappings:
            for feature_name, config in mappings.mappings.items():
                if config.aspect in self.label_scores:
                    self.label_scores[config.aspect] = config.label_scores

    def _distribution_to_score(
        self,
        distribution: Dict[str, float],
        aspect: str,
        default: float = 0.5,
    ) -> float:
        """
        Convert label distribution to weighted score.
        
        Args:
            distribution: Dict mapping label -> weight/count
            aspect: Aspect name for looking up label scores
            default: Default score if no distribution
        
        Returns:
            Weighted score [0, 1]
        """
        if not distribution:
            return default
        
        label_scores = self.label_scores.get(aspect, {})
        if not label_scores:
            return default
        
        total_weight = 0.0
        weighted_score = 0.0
        
        for label, weight in distribution.items():
            score = label_scores.get(label, 0.5)
            weighted_score += score * weight
            total_weight += weight
        
        if total_weight == 0:
            return default
        
        return weighted_score / total_weight

    def map_cost_score(
        self,
        distribution: Dict[str, float],
    ) -> float:
        """
        Map 'cost' aspect distribution to ga_cost_score.
        
        Higher score = lower cost (more GA-friendly).
        """
        return self._distribution_to_score(distribution, "cost", default=0.5)

    def map_hassle_score(
        self,
        distribution: Dict[str, float],
        notification_hassle_score: Optional[float] = None,
    ) -> float:
        """
        Map 'bureaucracy' aspect + AIP notification rules to ga_hassle_score.
        
        Higher score = less hassle (more GA-friendly).
        
        Args:
            distribution: Bureaucracy aspect distribution
            notification_hassle_score: Score from AIP rules (optional)
        
        Returns:
            Combined hassle score [0, 1]
        """
        review_score = self._distribution_to_score(distribution, "bureaucracy", default=0.5)
        
        if notification_hassle_score is not None:
            # Weighted combination: 70% reviews, 30% AIP rules
            return 0.7 * review_score + 0.3 * notification_hassle_score
        
        return review_score

    def map_review_score(
        self,
        distribution: Dict[str, float],
    ) -> float:
        """
        Map 'overall_experience' aspect to ga_review_score.
        
        Higher score = better overall experience.
        """
        return self._distribution_to_score(distribution, "overall_experience", default=0.5)

    def map_access_score(
        self,
        distribution: Dict[str, float],
    ) -> float:
        """
        Map 'transport' aspect to ga_access_score.
        
        Higher score = better access to facilities.
        """
        return self._distribution_to_score(distribution, "transport", default=0.5)

    def map_hospitality_score(
        self,
        restaurant_dist: Dict[str, float],
        accommodation_dist: Dict[str, float],
    ) -> float:
        """
        Map 'restaurant' and 'accommodation' aspects to ga_hospitality_score.
        
        Combines availability of food and lodging.
        Higher score = better hospitality options.
        """
        restaurant_score = self._distribution_to_score(restaurant_dist, "restaurant", default=0.5)
        accommodation_score = self._distribution_to_score(accommodation_dist, "accommodation", default=0.5)
        
        # Weight restaurant more heavily (60/40)
        return 0.6 * restaurant_score + 0.4 * accommodation_score

    def map_fun_score(
        self,
        food_dist: Dict[str, float],
        experience_dist: Dict[str, float],
    ) -> float:
        """
        Map 'food' and 'overall_experience' to ga_fun_score.
        
        Represents "is this a fun place to fly to?"
        """
        food_score = self._distribution_to_score(food_dist, "food", default=0.5)
        experience_score = self._distribution_to_score(experience_dist, "overall_experience", default=0.5)
        
        return 0.5 * food_score + 0.5 * experience_score

    def map_ops_vfr_score(
        self,
        runway_dist: Dict[str, float],
        traffic_dist: Dict[str, float],
    ) -> float:
        """
        Map runway and traffic aspects to ga_ops_vfr_score.
        
        Higher score = better VFR operations experience.
        """
        runway_score = self._distribution_to_score(runway_dist, "runway", default=0.6)
        traffic_score = self._distribution_to_score(traffic_dist, "training_traffic", default=0.6)
        
        return 0.6 * runway_score + 0.4 * traffic_score

    def map_ops_ifr_score(
        self,
        ifr_procedure_available: bool,
        runway_dist: Optional[Dict[str, float]] = None,
    ) -> float:
        """
        Map IFR availability to ga_ops_ifr_score.
        
        Primarily based on whether IFR procedures are available.
        
        Args:
            ifr_procedure_available: Whether airport has instrument approaches
            runway_dist: Optional runway quality distribution
        """
        # Base score from IFR availability
        if not ifr_procedure_available:
            return 0.1  # Very low score if no IFR procedures
        
        base_score = 0.8  # Good score for having IFR procedures
        
        # Adjust based on runway quality if available
        if runway_dist:
            runway_score = self._distribution_to_score(runway_dist, "runway", default=0.7)
            return 0.7 * base_score + 0.3 * runway_score
        
        return base_score

    def compute_feature_scores(
        self,
        icao: str,
        distributions: Dict[str, Dict[str, float]],
        ifr_procedure_available: bool = False,
        notification_hassle_score: Optional[float] = None,
    ) -> AirportFeatureScores:
        """
        Compute all feature scores from distributions.
        
        Args:
            icao: Airport ICAO code
            distributions: Dict mapping aspect -> label -> weight
            ifr_procedure_available: Whether IFR procedures exist
            notification_hassle_score: Optional AIP-based hassle score
        
        Returns:
            AirportFeatureScores with all features computed
        """
        return AirportFeatureScores(
            icao=icao,
            ga_cost_score=self.map_cost_score(distributions.get("cost", {})),
            ga_review_score=self.map_review_score(distributions.get("overall_experience", {})),
            ga_hassle_score=self.map_hassle_score(
                distributions.get("bureaucracy", {}),
                notification_hassle_score,
            ),
            ga_ops_ifr_score=self.map_ops_ifr_score(
                ifr_procedure_available,
                distributions.get("runway"),
            ),
            ga_ops_vfr_score=self.map_ops_vfr_score(
                distributions.get("runway", {}),
                distributions.get("training_traffic", {}),
            ),
            ga_access_score=self.map_access_score(distributions.get("transport", {})),
            ga_fun_score=self.map_fun_score(
                distributions.get("food", {}),
                distributions.get("overall_experience", {}),
            ),
            ga_hospitality_score=self.map_hospitality_score(
                distributions.get("restaurant", {}),
                distributions.get("accommodation", {}),
            ),
        )


def apply_bayesian_smoothing(
    score: float,
    sample_count: int,
    prior: float = 0.5,
    strength: float = 10.0,
) -> float:
    """
    Apply Bayesian smoothing to a score.
    
    For airports with few reviews, pulls score toward the prior (global average).
    
    Formula: smoothed = (k * prior + n * score) / (k + n)
    where k = strength, n = sample_count
    
    Args:
        score: Raw score
        sample_count: Number of samples contributing to score
        prior: Prior (global average) to smooth toward
        strength: Smoothing strength (higher = more smoothing)
    
    Returns:
        Smoothed score
    """
    if sample_count == 0:
        return prior
    
    return (strength * prior + sample_count * score) / (strength + sample_count)

