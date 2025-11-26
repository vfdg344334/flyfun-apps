"""
LLM-based review tag extraction.

Uses LangChain to extract structured aspect-label pairs from free-text reviews.
"""

import json
import logging
from typing import Any, Dict, List, Optional, Tuple

from tenacity import retry, stop_after_attempt, wait_exponential, retry_if_exception_type

from shared.ga_friendliness.exceptions import ReviewExtractionError
from shared.ga_friendliness.interfaces import ReviewExtractorInterface
from shared.ga_friendliness.models import (
    AspectLabel,
    OntologyConfig,
    ReviewExtraction,
)

logger = logging.getLogger(__name__)


# Default extraction prompt template
EXTRACTION_PROMPT_TEMPLATE = """You are an expert at analyzing aviation reviews and extracting structured information.

Given a review of an airfield/airport, extract relevant aspects and labels according to the ontology below.

{ontology_context}

For each aspect mentioned in the review, assign the most appropriate label.
Only extract aspects that are clearly mentioned or implied in the review.
Assign a confidence score (0.0-1.0) based on how certain you are about the extraction.

Review to analyze:
"{review_text}"

Respond with a JSON object in this exact format:
{{
    "aspects": [
        {{"aspect": "<aspect_name>", "label": "<label>", "confidence": <0.0-1.0>}},
        ...
    ]
}}

Only include aspects that are actually mentioned or clearly implied in the review.
Be conservative - only extract with high confidence when the text clearly supports it."""


class ReviewExtractor(ReviewExtractorInterface):
    """
    Extracts structured tags from free-text reviews using LLM.
    
    Features:
        - Retry logic for transient failures
        - Token usage tracking
        - Error handling with specific exceptions
        - Support for mock LLM for testing
    """

    def __init__(
        self,
        ontology: OntologyConfig,
        llm_model: str = "gpt-4o-mini",
        llm_temperature: float = 0.0,
        api_key: Optional[str] = None,
        max_retries: int = 3,
        mock_llm: bool = False,
    ):
        """
        Initialize extractor with LLM.
        
        Args:
            ontology: Ontology configuration for validation
            llm_model: LLM model name
            llm_temperature: LLM temperature (0.0 = deterministic)
            api_key: OpenAI API key (uses env var if not provided)
            max_retries: Maximum number of retry attempts for LLM calls
            mock_llm: If True, use mock LLM for testing
        """
        self.ontology = ontology
        self.llm_model = llm_model
        self.llm_temperature = llm_temperature
        self.api_key = api_key
        self.max_retries = max_retries
        self.mock_llm = mock_llm
        
        # Token usage tracking
        self._token_usage = {
            "input_tokens": 0,
            "output_tokens": 0,
            "total_calls": 0,
        }
        
        # Build ontology context for prompt
        self._ontology_context = self._build_ontology_context()
        
        # Initialize LLM chain if not mock
        self._chain = None
        if not mock_llm:
            self._init_chain()

    def _build_ontology_context(self) -> str:
        """Build ontology context string for prompt."""
        lines = ["Available aspects and their allowed labels:"]
        for aspect, labels in self.ontology.aspects.items():
            labels_str = ", ".join(labels)
            lines.append(f"- {aspect}: [{labels_str}]")
        return "\n".join(lines)

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
            self._prompt = ChatPromptTemplate.from_template(EXTRACTION_PROMPT_TEMPLATE)
            
            # Create chain
            self._chain = self._prompt | self._llm
            
        except ImportError as e:
            raise ReviewExtractionError(
                f"LangChain not available. Install with: pip install langchain-openai. Error: {e}"
            )

    def _mock_extract(self, review_text: str) -> Dict[str, Any]:
        """Generate mock extraction for testing."""
        # Simple heuristic-based extraction for testing
        aspects = []
        text_lower = review_text.lower()
        
        # Cost detection
        if any(word in text_lower for word in ["cheap", "inexpensive", "affordable"]):
            aspects.append({"aspect": "cost", "label": "cheap", "confidence": 0.8})
        elif any(word in text_lower for word in ["expensive", "pricey", "costly"]):
            aspects.append({"aspect": "cost", "label": "expensive", "confidence": 0.8})
        elif any(word in text_lower for word in ["reasonable", "fair"]):
            aspects.append({"aspect": "cost", "label": "reasonable", "confidence": 0.75})
        
        # Staff detection
        if any(word in text_lower for word in ["friendly", "helpful", "great staff", "excellent service"]):
            aspects.append({"aspect": "staff", "label": "very_positive", "confidence": 0.85})
        elif any(word in text_lower for word in ["good staff", "nice staff"]):
            aspects.append({"aspect": "staff", "label": "positive", "confidence": 0.8})
        elif any(word in text_lower for word in ["rude", "unhelpful"]):
            aspects.append({"aspect": "staff", "label": "negative", "confidence": 0.8})
        
        # Bureaucracy detection
        if any(word in text_lower for word in ["simple", "easy", "no hassle", "straightforward"]):
            aspects.append({"aspect": "bureaucracy", "label": "simple", "confidence": 0.8})
        elif any(word in text_lower for word in ["complex", "complicated", "bureaucratic"]):
            aspects.append({"aspect": "bureaucracy", "label": "complex", "confidence": 0.8})
        
        # Restaurant detection
        if any(phrase in text_lower for phrase in ["restaurant on site", "on-site restaurant", "cafe on site"]):
            aspects.append({"aspect": "restaurant", "label": "on_site", "confidence": 0.9})
        elif any(phrase in text_lower for phrase in ["good restaurant", "excellent food", "great food"]):
            aspects.append({"aspect": "restaurant", "label": "on_site", "confidence": 0.75})
        elif "no restaurant" in text_lower or "no food" in text_lower:
            aspects.append({"aspect": "restaurant", "label": "none", "confidence": 0.85})
        
        # Overall experience
        if any(word in text_lower for word in ["excellent", "fantastic", "wonderful", "amazing"]):
            aspects.append({"aspect": "overall_experience", "label": "very_positive", "confidence": 0.85})
        elif any(word in text_lower for word in ["great", "good", "nice", "pleasant"]):
            aspects.append({"aspect": "overall_experience", "label": "positive", "confidence": 0.8})
        elif any(word in text_lower for word in ["terrible", "awful", "horrible"]):
            aspects.append({"aspect": "overall_experience", "label": "very_negative", "confidence": 0.85})
        
        return {"aspects": aspects}

    def _parse_llm_response(self, response_text: str) -> Dict[str, Any]:
        """Parse LLM response into structured format."""
        # Try to extract JSON from response
        try:
            # Handle responses that might have extra text
            text = response_text.strip()
            
            # Find JSON object in response
            start = text.find("{")
            end = text.rfind("}") + 1
            
            if start >= 0 and end > start:
                json_str = text[start:end]
                return json.loads(json_str)
            
            raise ValueError("No JSON object found in response")
            
        except json.JSONDecodeError as e:
            raise ReviewExtractionError(f"Failed to parse LLM response as JSON: {e}")

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        retry=retry_if_exception_type(Exception),
        reraise=True,
    )
    def _call_llm(self, review_text: str) -> Dict[str, Any]:
        """Call LLM with retry logic."""
        if self.mock_llm:
            return self._mock_extract(review_text)
        
        if self._chain is None:
            raise ReviewExtractionError("LLM chain not initialized")
        
        try:
            # Invoke chain
            response = self._chain.invoke({
                "ontology_context": self._ontology_context,
                "review_text": review_text,
            })
            
            # Extract content from AIMessage
            content = response.content if hasattr(response, "content") else str(response)
            
            # Track token usage if available
            if hasattr(response, "usage_metadata"):
                usage = response.usage_metadata
                self._token_usage["input_tokens"] += usage.get("input_tokens", 0)
                self._token_usage["output_tokens"] += usage.get("output_tokens", 0)
            
            self._token_usage["total_calls"] += 1
            
            return self._parse_llm_response(content)
            
        except Exception as e:
            logger.error(f"LLM call failed: {e}")
            raise

    def extract(
        self,
        review_text: str,
        review_id: Optional[str] = None,
        timestamp: Optional[str] = None,
    ) -> ReviewExtraction:
        """
        Extract tags from a single review.
        
        Args:
            review_text: Review text to extract tags from
            review_id: Optional review ID from source
            timestamp: Optional timestamp from source review
        
        Returns:
            ReviewExtraction with aspect-label pairs
        
        Raises:
            ReviewExtractionError: If extraction fails
        """
        try:
            result = self._call_llm(review_text)
            
            # Parse aspects
            aspects = []
            for item in result.get("aspects", []):
                aspect = item.get("aspect", "")
                label = item.get("label", "")
                confidence = float(item.get("confidence", 0.0))
                
                # Validate against ontology
                if not self.ontology.validate_aspect(aspect):
                    logger.warning(f"Unknown aspect '{aspect}' in extraction")
                    continue
                if not self.ontology.validate_label(aspect, label):
                    logger.warning(f"Invalid label '{label}' for aspect '{aspect}'")
                    continue
                
                aspects.append(AspectLabel(
                    aspect=aspect,
                    label=label,
                    confidence=confidence,
                ))
            
            return ReviewExtraction(
                review_id=review_id,
                aspects=aspects,
                raw_text_excerpt=review_text[:200] if len(review_text) > 200 else review_text,
                timestamp=timestamp,
            )
            
        except Exception as e:
            raise ReviewExtractionError(f"Failed to extract from review: {e}")

    def extract_batch(
        self,
        reviews: List[Tuple[str, Optional[str], Optional[str]]],
    ) -> List[ReviewExtraction]:
        """
        Extract tags from multiple reviews.
        
        Args:
            reviews: List of (text, review_id, timestamp) tuples
        
        Returns:
            List of ReviewExtraction objects
        """
        results = []
        for text, review_id, timestamp in reviews:
            try:
                result = self.extract(text, review_id, timestamp)
                results.append(result)
            except ReviewExtractionError as e:
                logger.error(f"Failed to extract review {review_id}: {e}")
                # Return empty extraction for failed reviews
                results.append(ReviewExtraction(
                    review_id=review_id,
                    aspects=[],
                    timestamp=timestamp,
                ))
        return results

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

