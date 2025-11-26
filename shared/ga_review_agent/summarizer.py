"""
Airport summary generation from review tags.

Uses LLM to generate human-readable summaries from extracted tags.
"""

import json
import logging
from typing import Any, Dict, List, Optional, Tuple

from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

from shared.ga_friendliness.exceptions import ReviewExtractionError
from shared.ga_friendliness.interfaces import SummaryGeneratorInterface
from shared.ga_friendliness.models import (
    AirportStats,
    ReviewExtraction,
)

logger = logging.getLogger(__name__)


SUMMARY_PROMPT_TEMPLATE = """You are an expert at summarizing aviation reviews.

Based on the following extracted tags from reviews of airport {icao}, generate:
1. A 2-4 sentence summary of the airfield's key characteristics
2. A list of 3-6 short tags (e.g., "GA friendly", "expensive", "good restaurant")

Extracted review tags:
{tags_summary}

Additional context:
- Number of reviews: {review_count}
- Average rating: {avg_rating}

Generate a JSON response in this format:
{{
    "summary": "2-4 sentence summary here...",
    "tags": ["tag1", "tag2", "tag3"]
}}

Focus on the most notable and consistent characteristics. Be balanced - include both positive and negative aspects if present."""


class SummaryGenerator(SummaryGeneratorInterface):
    """
    Generates human-readable airport summaries from extracted tags.
    
    Uses LLM to create natural language summaries and tag lists.
    """

    def __init__(
        self,
        llm_model: str = "gpt-4o-mini",
        llm_temperature: float = 0.3,  # Slightly higher for more natural text
        api_key: Optional[str] = None,
        mock_llm: bool = False,
    ):
        """
        Initialize summary generator.
        
        Args:
            llm_model: LLM model name
            llm_temperature: LLM temperature
            api_key: OpenAI API key (uses env var if not provided)
            mock_llm: If True, use mock LLM for testing
        """
        self.llm_model = llm_model
        self.llm_temperature = llm_temperature
        self.api_key = api_key
        self.mock_llm = mock_llm
        
        # Token usage tracking
        self._token_usage = {
            "input_tokens": 0,
            "output_tokens": 0,
            "total_calls": 0,
        }
        
        # Initialize LLM chain if not mock
        self._chain = None
        if not mock_llm:
            self._init_chain()

    def _init_chain(self) -> None:
        """Initialize LangChain chain."""
        try:
            from langchain_core.prompts import ChatPromptTemplate
            from langchain_openai import ChatOpenAI
            
            # Create LLM
            llm_kwargs: Dict[str, Any] = {
                "model": self.llm_model,
                "temperature": self.llm_temperature,
            }
            if self.api_key:
                llm_kwargs["api_key"] = self.api_key
            
            self._llm = ChatOpenAI(**llm_kwargs)
            
            # Create prompt template
            self._prompt = ChatPromptTemplate.from_template(SUMMARY_PROMPT_TEMPLATE)
            
            # Create chain
            self._chain = self._prompt | self._llm
            
        except ImportError as e:
            raise ReviewExtractionError(
                f"LangChain not available. Install with: pip install langchain-openai. Error: {e}"
            )

    def _build_tags_summary(self, extractions: List[ReviewExtraction]) -> str:
        """Build summary of tags for prompt."""
        # Aggregate tags
        from collections import defaultdict
        tag_counts: Dict[str, Dict[str, int]] = defaultdict(lambda: defaultdict(int))
        
        for extraction in extractions:
            for aspect_label in extraction.aspects:
                tag_counts[aspect_label.aspect][aspect_label.label] += 1
        
        # Format as readable summary
        lines = []
        for aspect, labels in sorted(tag_counts.items()):
            labels_str = ", ".join(
                f"{label} ({count})" 
                for label, count in sorted(labels.items(), key=lambda x: -x[1])
            )
            lines.append(f"- {aspect}: {labels_str}")
        
        return "\n".join(lines) if lines else "No tags extracted"

    def _mock_generate(
        self,
        icao: str,
        tags_summary: str,
        review_count: int,
        avg_rating: Optional[float],
    ) -> Dict[str, Any]:
        """Generate mock summary for testing."""
        # Parse tags to generate summary
        summary_parts = []
        tags = []
        
        if "cheap" in tags_summary.lower():
            summary_parts.append("offers reasonable landing fees")
            tags.append("budget-friendly")
        elif "expensive" in tags_summary.lower():
            summary_parts.append("has higher-than-average fees")
            tags.append("expensive")
        
        if "very_positive" in tags_summary.lower() or "positive" in tags_summary.lower():
            summary_parts.append("has friendly and helpful staff")
            tags.append("GA friendly")
        
        if "simple" in tags_summary.lower():
            summary_parts.append("features straightforward procedures")
            tags.append("easy access")
        elif "complex" in tags_summary.lower():
            summary_parts.append("requires more advance planning")
            tags.append("complex procedures")
        
        if "on_site" in tags_summary.lower() and "restaurant" in tags_summary.lower():
            summary_parts.append("has an on-site restaurant")
            tags.append("good restaurant")
        
        # Build summary
        if summary_parts:
            summary = f"{icao} " + ", ".join(summary_parts) + "."
        else:
            summary = f"{icao} is a general aviation airfield with {review_count} reviews."
        
        if avg_rating:
            summary += f" Average rating: {avg_rating:.1f}/5."
        
        if not tags:
            tags = ["GA airfield"]
        
        return {
            "summary": summary,
            "tags": tags[:6],  # Max 6 tags
        }

    def _parse_llm_response(self, response_text: str) -> Dict[str, Any]:
        """Parse LLM response into structured format."""
        try:
            text = response_text.strip()
            
            # Find JSON object in response
            start = text.find("{")
            end = text.rfind("}") + 1
            
            if start >= 0 and end > start:
                json_str = text[start:end]
                result = json.loads(json_str)
                
                # Validate required fields
                if "summary" not in result:
                    result["summary"] = "Summary not available."
                if "tags" not in result:
                    result["tags"] = []
                
                return result
            
            raise ValueError("No JSON object found in response")
            
        except json.JSONDecodeError as e:
            raise ReviewExtractionError(f"Failed to parse LLM response as JSON: {e}")

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        retry=retry_if_exception_type(Exception),
        reraise=True,
    )
    def _call_llm(
        self,
        icao: str,
        tags_summary: str,
        review_count: int,
        avg_rating: Optional[float],
    ) -> Dict[str, Any]:
        """Call LLM with retry logic."""
        if self.mock_llm:
            return self._mock_generate(icao, tags_summary, review_count, avg_rating)
        
        if self._chain is None:
            raise ReviewExtractionError("LLM chain not initialized")
        
        try:
            response = self._chain.invoke({
                "icao": icao,
                "tags_summary": tags_summary,
                "review_count": review_count,
                "avg_rating": f"{avg_rating:.1f}" if avg_rating else "N/A",
            })
            
            content = response.content if hasattr(response, "content") else str(response)
            
            # Track token usage
            if hasattr(response, "usage_metadata"):
                usage = response.usage_metadata
                self._token_usage["input_tokens"] += usage.get("input_tokens", 0)
                self._token_usage["output_tokens"] += usage.get("output_tokens", 0)
            
            self._token_usage["total_calls"] += 1
            
            return self._parse_llm_response(content)
            
        except Exception as e:
            logger.error(f"LLM call failed: {e}")
            raise

    def generate_summary(
        self,
        icao: str,
        extractions: List[ReviewExtraction],
        stats: Optional[AirportStats] = None,
    ) -> Tuple[str, List[str]]:
        """
        Generate airport summary and tags.
        
        Args:
            icao: Airport ICAO code
            extractions: Extracted review tags
            stats: Optional airport stats for context
        
        Returns:
            Tuple of (summary_text, tags_list)
        """
        tags_summary = self._build_tags_summary(extractions)
        review_count = len(extractions)
        avg_rating = stats.rating_avg if stats else None
        
        try:
            result = self._call_llm(icao, tags_summary, review_count, avg_rating)
            return (result["summary"], result["tags"])
        except Exception as e:
            logger.error(f"Failed to generate summary for {icao}: {e}")
            # Return fallback
            return (
                f"{icao} is a general aviation airfield with {review_count} reviews.",
                ["GA airfield"],
            )

    def get_token_usage(self) -> Dict[str, int]:
        """Get cumulative token usage stats."""
        return self._token_usage.copy()

    def reset_token_usage(self) -> None:
        """Reset token usage counters."""
        self._token_usage = {
            "input_tokens": 0,
            "output_tokens": 0,
            "total_calls": 0,
        }

