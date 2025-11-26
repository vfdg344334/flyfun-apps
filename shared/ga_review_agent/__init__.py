"""
GA Review Agent

LLM-based review processing for GA friendliness scoring.

Components:
    - ReviewExtractor: Extract structured tags from reviews
    - TagAggregator: Aggregate tags into feature distributions
    - SummaryGenerator: Generate airport summaries from tags
"""

from .extractor import ReviewExtractor
from .aggregator import TagAggregator
from .summarizer import SummaryGenerator

__all__ = [
    "ReviewExtractor",
    "TagAggregator",
    "SummaryGenerator",
]

