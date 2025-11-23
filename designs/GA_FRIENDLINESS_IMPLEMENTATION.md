# GA Friendliness Implementation Plan

This document defines the **implementation architecture, module structure, and function signatures** for the GA friendliness enrichment system. This is a planning document; function bodies will be implemented after review and iteration.

---

## 1. Library Structure & Organization

### 1.1 Decision: Standalone Library vs. Shared Module

**Choice:** Create a new standalone Python library `ga_friendliness` that can be used independently or integrated into the flyfun-apps ecosystem.

**Rationale:**
- **Pros:**
  - Clean separation of concerns (follows design principle)
  - Can be shared/reused by other projects
  - Easier to version and test independently
  - Clear dependency boundaries
- **Cons:**
  - Slightly more complex import paths
  - Need to manage dependencies carefully

**Location:** `shared/ga_friendliness/` (following the pattern of `shared/filtering/`, `shared/prioritization/`)

**Alternative Considered:** Separate package in `src/ga-friendliness/` (like `src/euro-aip/`)
- **Rejected because:** We want tight integration with flyfun-apps tooling and shared utilities, while still maintaining logical separation.

### 1.2 Module Structure

```
shared/ga_friendliness/
├── __init__.py                 # Public API exports
├── config.py                   # Configuration loading (JSON, env vars)
├── models.py                   # Pydantic models for ontology, personas, reviews
├── exceptions.py               # Exception hierarchy
├── database.py                 # SQLite schema creation, connection management, migrations
├── storage.py                  # Read/write operations for ga_meta.sqlite
├── ontology.py                 # Ontology loading, validation, aspect/label lookup
├── personas.py                 # Persona loading, validation, score computation
├── cache.py                    # Caching utility for remote data sources
├── nlp/
│   ├── __init__.py
│   ├── extractor.py           # LLM-based review tag extraction
│   ├── aggregator.py           # Tag aggregation → feature scores
│   └── summarizer.py           # LLM-based airport summary generation
├── features.py                 # Feature engineering (label distributions → scores)
├── scoring.py                  # Persona-based scoring functions
└── builder.py                  # Main pipeline orchestrator

tools/
└── build_ga_friendliness.py    # CLI tool for rebuilding ga_meta.sqlite

data/
├── ontology.json               # Ontology definition (versioned)
├── personas.json               # Persona definitions (versioned)
└── feature_mappings.json       # Feature mapping configurations (versioned)
```

---

## 2. Exception Hierarchy

### 2.1 Exception Classes (`exceptions.py`)

```python
# exceptions.py - Exception hierarchy for ga_friendliness library

class GAFriendlinessError(Exception):
    """Base exception for ga_friendliness library."""
    pass

class OntologyValidationError(GAFriendlinessError):
    """Raised when ontology validation fails."""
    pass

class PersonaValidationError(GAFriendlinessError):
    """Raised when persona validation fails."""
    pass

class ReviewExtractionError(GAFriendlinessError):
    """Raised when LLM extraction fails."""
    pass

class StorageError(GAFriendlinessError):
    """Raised when database operations fail."""
    pass

class FeatureMappingError(GAFriendlinessError):
    """Raised when feature mapping fails."""
    pass

class BuildError(GAFriendlinessError):
    """Raised when build process fails."""
    pass
```

**Design Decision: Exception Hierarchy**

- **Why:** Clear error types for better error handling and debugging
- **Usage:** Components raise specific exceptions, caller can handle appropriately
- **Pattern:** Base exception + specific subclasses for each domain

---

## 3. Core Models & Data Structures

### 2.1 Pydantic Models (`models.py`)

```python
# models.py - Data structures using Pydantic for validation

class AspectLabel(BaseModel):
    """Single label for an aspect (e.g., 'cost': 'expensive')."""
    aspect: str
    label: str
    confidence: float  # 0.0-1.0

class ReviewExtraction(BaseModel):
    """Structured extraction from a single review."""
    review_id: Optional[str]
    aspects: List[AspectLabel]
    raw_text_excerpt: Optional[str]  # For transparency/debugging

class OntologyConfig(BaseModel):
    """Loaded ontology.json structure."""
    version: str
    aspects: Dict[str, List[str]]  # aspect_name -> [allowed_labels]

class PersonaWeights(BaseModel):
    """Weights for a single persona."""
    ga_cost_score: float = 0.0
    ga_review_score: float = 0.0
    ga_hassle_score: float = 0.0
    ga_ops_ifr_score: float = 0.0
    ga_ops_vfr_score: float = 0.0
    ga_access_score: float = 0.0
    ga_fun_score: float = 0.0

class PersonaConfig(BaseModel):
    """Single persona definition."""
    id: str
    label: str
    description: str
    weights: PersonaWeights

class PersonasConfig(BaseModel):
    """Loaded personas.json structure."""
    version: str
    personas: Dict[str, PersonaConfig]  # persona_id -> PersonaConfig

class AirportFeatureScores(BaseModel):
    """Normalized feature scores for an airport."""
    icao: str
    ga_cost_score: float
    ga_review_score: float
    ga_hassle_score: float
    ga_ops_ifr_score: float
    ga_ops_vfr_score: float
    ga_access_score: float
    ga_fun_score: float

class AirportStats(BaseModel):
    """Aggregated stats for ga_airfield_stats table."""
    icao: str
    rating_avg: Optional[float]
    rating_count: int
    last_review_utc: Optional[str]
    fee_band_lt_1500kg: Optional[float]
    fee_band_1500_2000: Optional[float]
    fee_currency: Optional[str]
    mandatory_handling: bool
    ifr_available: bool
    night_available: bool
    # ... feature scores ...
    source_version: str
    scoring_version: str
```

---

## 4. Configuration Management

### 3.1 Config Loading (`config.py`)

```python
# config.py - Configuration loading and validation

class GAFriendlinessSettings(BaseSettings):
    """Settings for GA friendliness processing."""
    # Paths
    euro_aip_db_path: Path  # Path to euro_aip.sqlite
    ga_meta_db_path: Path   # Path to ga_meta.sqlite (output)
    ontology_json_path: Path
    personas_json_path: Path
    
    # LLM settings
    llm_model: str = "gpt-4o-mini"  # Default for cost efficiency
    llm_temperature: float = 0.0
    llm_api_key: Optional[str] = None  # From env or explicit
    
    # Processing settings
    confidence_threshold: float = 0.5  # Min confidence for tag inclusion
    batch_size: int = 50  # Reviews per LLM batch
    
    # Versioning
    source_version: str  # e.g., "airfield.directory-2025-11-01"
    scoring_version: str = "ga_scores_v1"

def load_ontology(path: Path) -> OntologyConfig:
    """
    Load and validate ontology.json.
    
    Raises:
        ValidationError if JSON is malformed or structure invalid.
    """
    # Load JSON, validate with Pydantic, return OntologyConfig

def load_personas(path: Path) -> PersonasConfig:
    """
    Load and validate personas.json.
    
    Raises:
        ValidationError if JSON is malformed or weights don't sum reasonably.
    """
    # Load JSON, validate with Pydantic, return PersonasConfig

def get_settings() -> GAFriendlinessSettings:
    """
    Load settings from environment variables and defaults.
    
    Environment variables:
        GA_FRIENDLINESS_EURO_AIP_DB
        GA_FRIENDLINESS_GA_META_DB
        GA_FRIENDLINESS_ONTOLOGY_JSON
        GA_FRIENDLINESS_PERSONAS_JSON
        GA_FRIENDLINESS_LLM_MODEL
        OPENAI_API_KEY (or GA_FRIENDLINESS_LLM_API_KEY)
    """
    # Use pydantic-settings BaseSettings pattern
```

---

## 5. Database Schema & Storage

### 5.1 Schema Creation & Versioning (`database.py`)

```python
# database.py - SQLite schema and connection management with versioning

SCHEMA_VERSION = "1.0"

def get_schema_version(conn: sqlite3.Connection) -> Optional[str]:
    """
    Get current schema version from database.
    
    Returns:
        Schema version string (e.g., "1.0") or None if not set.
    """
    # Query ga_meta_info for 'schema_version' key
    # Return version or None

def create_schema(conn: sqlite3.Connection) -> None:
    """
    Create all tables in ga_meta.sqlite and set schema version.
    
    Tables:
        - ga_airfield_stats (main query table)
        - ga_landing_fees (optional detailed fees)
        - ga_review_ner_tags (structured review tags)
        - ga_review_summary (LLM-generated summaries)
        - ga_meta_info (versioning metadata)
    
    Also creates indexes for performance.
    Sets schema_version in ga_meta_info.
    """
    # Execute CREATE TABLE statements
    # Create indexes on icao, (icao, aspect) for ga_review_ner_tags
    # Insert schema_version into ga_meta_info

def migrate_schema(
    conn: sqlite3.Connection,
    from_version: str,
    to_version: str
) -> None:
    """
    Migrate schema from one version to another.
    
    Handles:
        - Adding new columns (ALTER TABLE ADD COLUMN)
        - Modifying existing columns (via table recreation if needed)
        - Data transformations if required
    
    Raises:
        StorageError if migration fails.
    """
    # Check if migration path exists (from_version -> to_version)
    # Execute migration steps
    # Update schema_version in ga_meta_info
    # Commit transaction

def ensure_schema_version(conn: sqlite3.Connection) -> None:
    """
    Ensure database schema is at current version.
    
    If schema doesn't exist, creates it.
    If schema exists but is older version, migrates it.
    If schema is newer version, raises error.
    """
    current_version = get_schema_version(conn)
    
    if current_version is None:
        # No schema, create it
        create_schema(conn)
    elif current_version == SCHEMA_VERSION:
        # Schema is current, nothing to do
        pass
    elif current_version < SCHEMA_VERSION:
        # Schema is older, migrate
        migrate_schema(conn, current_version, SCHEMA_VERSION)
    else:
        # Schema is newer (shouldn't happen), raise error
        raise StorageError(
            f"Database schema version {current_version} is newer than "
            f"library version {SCHEMA_VERSION}. Please upgrade library."
        )

def get_connection(db_path: Path) -> sqlite3.Connection:
    """
    Get a connection to ga_meta.sqlite.
    
    Creates the database and schema if it doesn't exist.
    Ensures schema is at current version.
    
    Returns:
        Connection with schema at current version.
    """
    # Create parent dirs if needed
    # Create database if doesn't exist
    # Call ensure_schema_version()
    # Return connection
```

### 5.2 Storage Operations (`storage.py`)

```python
# storage.py - Read/write operations for ga_meta.sqlite with transaction support

import threading
from contextlib import contextmanager

class GAMetaStorage:
    """
    Handles all database operations for ga_meta.sqlite.
    
    Supports:
        - Transaction management (context manager)
        - Thread-safe operations
        - Batch writes for efficiency
        - Resource cleanup
    """
    
    def __init__(self, db_path: Path):
        """
        Initialize storage.
        
        Creates database and schema if needed.
        Ensures schema is at current version.
        """
        # Store db_path
        # Get connection (ensures schema version)
        # Create thread lock for thread-safety
    
    def __enter__(self):
        """Context manager entry: begin transaction."""
        # Begin transaction
        # Return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """
        Context manager exit: commit or rollback.
        
        Commits on success, rolls back on exception.
        """
        if exc_type is None:
            self.conn.commit()
        else:
            self.conn.rollback()
        # Don't suppress exceptions
    
    def close(self) -> None:
        """Close database connection and cleanup resources."""
        # Close connection if open
        # Cleanup resources
    
    def write_airfield_stats(self, stats: AirportStats) -> None:
        """
        Insert or update a row in ga_airfield_stats.
        
        Uses UPSERT pattern (INSERT OR REPLACE).
        Thread-safe.
        """
        with self._lock:
            # UPSERT pattern (INSERT OR REPLACE)
            # Raise StorageError on failure
    
    def write_review_tags(self, icao: str, tags: List[ReviewExtraction]) -> None:
        """
        Write review tags to ga_review_ner_tags.
        
        Clears existing tags for this icao first (idempotent rebuild).
        Thread-safe.
        """
        with self._lock:
            # DELETE existing tags for icao
            # INSERT new tags (use executemany for efficiency)
            # Raise StorageError on failure
    
    def write_review_tags_batch(
        self,
        tags_by_icao: Dict[str, List[ReviewExtraction]]
    ) -> None:
        """
        Write tags for multiple airports in a single transaction.
        
        More efficient than individual writes.
        Thread-safe.
        """
        with self._lock:
            # For each icao:
            #   DELETE existing tags
            #   INSERT new tags
            # All in single transaction
            # Raise StorageError on failure
    
    def write_review_summary(self, icao: str, summary_text: str, tags_json: List[str]) -> None:
        """Insert or update ga_review_summary for an airport."""
        with self._lock:
            # UPSERT
            # Raise StorageError on failure
    
    def write_meta_info(self, key: str, value: str) -> None:
        """Write to ga_meta_info table."""
        with self._lock:
            # INSERT OR REPLACE
            # Raise StorageError on failure
    
    def get_airfield_stats(self, icao: str) -> Optional[AirportStats]:
        """Read stats for a single airport."""
        # SELECT and map to AirportStats
        # Return None if not found
    
    def get_all_icaos(self) -> List[str]:
        """Get list of all ICAOs in ga_airfield_stats."""
        # SELECT DISTINCT icao
        # Return list
    
    def get_last_processed_timestamp(self, icao: str) -> Optional[datetime]:
        """
        Get when airport was last processed.
        
        Returns:
            Timestamp from ga_meta_info or ga_airfield_stats.last_review_utc,
            or None if airport not processed.
        """
        # Query for last processed timestamp
        # Return datetime or None
    
    def has_changes(
        self,
        icao: str,
        reviews: List[RawReview]
    ) -> bool:
        """
        Check if airport has new/changed reviews.
        
        Compares review timestamps with last processed time.
        
        Returns:
            True if reviews have changed since last processing.
        """
        last_processed = self.get_last_processed_timestamp(icao)
        if last_processed is None:
            return True  # Never processed
        
        # Check if any review has timestamp > last_processed
        # Return True if changes detected
    
    def attach_euro_aip(self, conn: sqlite3.Connection, euro_aip_path: Path) -> None:
        """
        ATTACH euro_aip.sqlite for joint queries.
        
        Usage:
            conn = self.get_connection()
            self.attach_euro_aip(conn, euro_aip_path)
            # Now can query: SELECT * FROM aip.airport JOIN ga.ga_airfield_stats ...
        """
        # Execute: ATTACH DATABASE 'euro_aip_path' AS aip
        # Raise StorageError on failure
```

---

## 6. Caching Layer

### 6.1 Caching Utility (`cache.py`)

```python
# cache.py - Caching utility for remote data sources

from abc import ABC, abstractmethod
from pathlib import Path
from datetime import datetime
from typing import Any, Optional, Tuple
import json
import gzip
import logging

logger = logging.getLogger(__name__)

class CachedDataLoader(ABC):
    """
    Base class for data loaders that implement caching.
    
    Similar pattern to euro_aip's CachedSource, but independent.
    Provides caching for remote data to avoid repeated downloads.
    
    Usage:
        class MyLoader(CachedDataLoader):
            def fetch_data(self, key: str, **kwargs) -> Any:
                # Fetch from remote source
                return data
        
        loader = MyLoader(cache_dir="/path/to/cache")
        data = loader.get_cached("my_key", max_age_days=7)
    """
    
    def __init__(self, cache_dir: Path):
        """
        Initialize cached loader.
        
        Args:
            cache_dir: Base directory for caching
        """
        # Create cache directory structure
        # Store cache_dir path
    
    def set_force_refresh(self, force_refresh: bool = True) -> None:
        """Set whether to force refresh of cached data."""
        # Store flag
    
    def set_never_refresh(self, never_refresh: bool = True) -> None:
        """Set whether to never refresh cached data (use cache if exists)."""
        # Store flag
    
    def _get_cache_file(self, key: str, ext: str = "json") -> Path:
        """Get cache file path for a key."""
        # Return Path to cache file
    
    def _is_cache_valid(
        self,
        cache_file: Path,
        max_age_days: Optional[int] = None
    ) -> Tuple[bool, Optional[str]]:
        """
        Check if cache file is valid.
        
        Returns:
            (is_valid, reason_if_invalid)
        """
        # Check force_refresh flag
        # Check if file exists
        # Check never_refresh flag
        # Check age if max_age_days provided
        # Return (is_valid, reason)
    
    def _save_to_cache(self, data: Any, key: str, ext: str = "json") -> None:
        """Save data to cache."""
        # Handle JSON (with gzip support)
        # Handle other formats as needed
    
    def _load_from_cache(self, key: str, ext: str = "json") -> Any:
        """Load data from cache."""
        # Handle JSON (with gzip support)
        # Handle other formats as needed
    
    @abstractmethod
    def fetch_data(self, key: str, **kwargs) -> Any:
        """
        Fetch data from remote source.
        
        Must be implemented by subclasses.
        """
        pass
    
    def get_cached(
        self,
        key: str,
        max_age_days: Optional[int] = None,
        ext: str = "json",
        **kwargs
    ) -> Any:
        """
        Get data from cache or fetch if needed.
        
        Args:
            key: Cache key
            max_age_days: Maximum age of cache (None = no limit)
            ext: File extension (json, json.gz)
            **kwargs: Arguments to pass to fetch_data()
        
        Returns:
            Cached or freshly fetched data
        """
        # Get cache file path
        # Check if cache is valid
        # If valid, load and return
        # If not valid, call fetch_data()
        # Save to cache
        # Return data
```

**Design Decision: Independent Caching**

- **Why not reuse CachedSource from euro_aip?**
  - ga_friendliness should be independent (design principle)
  - CachedSource is tightly coupled to euro_aip's fetch method pattern
  - We need simpler caching for our use case (just JSON files)
  
- **Why this pattern?**
  - Follows same conceptual approach (familiar)
  - Simpler implementation (just JSON, no CSV/PDF)
  - Supports gzip for large files
  - Can be extended if needed

- **Alternative considered:**
  - Composition: Use CachedSource if euro_aip available
  - **Rejected:** Adds unnecessary complexity, breaks independence

### 5.2 Caching in Review Sources

```python
# Example: Cached AirfieldDirectorySource

class AirfieldDirectorySource(ReviewSource, CachedDataLoader):
    """
    Loads reviews from airfield.directory with caching.
    """
    
    def __init__(
        self,
        export_path: Optional[Path] = None,  # If None, download from S3
        cache_dir: Path,
        filter_ai_generated: bool = True,
        preferred_language: str = "EN",
        max_age_days: int = 7  # Cache bulk export for 7 days
    ):
        """
        Initialize with caching support.
        
        If export_path is None, will download from S3 and cache.
        """
        # Initialize CachedDataLoader
        # Store config
    
    def fetch_data(self, key: str, **kwargs) -> Dict:
        """
        Fetch data from remote source.
        
        Keys:
            - "bulk_export": Download from S3
            - "airport_{ICAO}": Fetch individual airport JSON
        """
        if key == "bulk_export":
            # Download from S3: airfield-directory-pireps-export-latest.json.gz
            # Return parsed JSON
        elif key.startswith("airport_"):
            icao = key.replace("airport_", "")
            # Fetch https://airfield.directory/airfield/{ICAO}.json
            # Return parsed JSON
        else:
            raise ValueError(f"Unknown key: {key}")
    
    def get_reviews(self) -> List[RawReview]:
        """
        Load reviews with caching.
        
        If export_path provided, use it directly.
        Otherwise, download and cache from S3.
        """
        if self.export_path and self.export_path.exists():
            # Use local file
            # Load and parse
        else:
            # Get from cache or download
            data = self.get_cached(
                "bulk_export",
                max_age_days=self.max_age_days,
                ext="json.gz"
            )
            # Parse and return reviews
    
    def get_airport_stats(self, icao: str) -> Optional[Dict]:
        """
        Get airport stats with caching.
        
        Fetches individual airport JSON with 30-day cache.
        """
        data = self.get_cached(
            f"airport_{icao}",
            max_age_days=30,  # Airport data changes less frequently
            ext="json"
        )
        # Extract and return stats
```

**Caching Strategy:**

1. **Bulk export (S3):**
   - Cache key: `bulk_export`
   - Default max_age: 7 days (export updates regularly)
   - Format: `.json.gz` (compressed)
   - Can force refresh for latest data

2. **Individual airport JSON:**
   - Cache key: `airport_{ICAO}`
   - Default max_age: 30 days (changes less frequently)
   - Format: `.json`
   - Used when fetching airport-level stats

3. **CLI flags:**
   - `--force-refresh`: Force download even if cache exists
   - `--never-refresh`: Use cache if exists, never download
   - `--cache-dir`: Override default cache directory

---

## 7. Ontology & Persona Management

### 7.1 Ontology (`ontology.py`)

```python
# ontology.py - Ontology validation and lookup

class OntologyManager:
    """Manages ontology aspects and labels."""
    
    def __init__(self, config: OntologyConfig):
        """Initialize with loaded ontology."""
        # Store config
    
    def validate_aspect(self, aspect: str) -> bool:
        """Check if aspect exists in ontology."""
        # Return aspect in config.aspects
    
    def validate_label(self, aspect: str, label: str) -> bool:
        """Check if label is allowed for aspect."""
        # Check label in config.aspects[aspect]
    
    def get_allowed_labels(self, aspect: str) -> List[str]:
        """Get list of allowed labels for an aspect."""
        # Return config.aspects.get(aspect, [])
    
    def validate_extraction(self, extraction: ReviewExtraction) -> List[str]:
        """
        Validate a ReviewExtraction against ontology.
        
        Returns:
            List of validation error messages (empty if valid).
        """
        # For each aspect-label pair, validate
        # Check confidence in [0, 1]
        # Return list of errors
```

### 6.2 Personas (`personas.py`)

```python
# personas.py - Persona loading and score computation

class PersonaManager:
    """Manages personas and computes persona-specific scores."""
    
    def __init__(self, config: PersonasConfig):
        """Initialize with loaded personas."""
        # Store config
    
    def get_persona(self, persona_id: str) -> Optional[PersonaConfig]:
        """Get persona by ID."""
        # Return config.personas.get(persona_id)
    
    def list_persona_ids(self) -> List[str]:
        """List all persona IDs."""
        # Return list(config.personas.keys())
    
    def compute_score(
        self,
        persona_id: str,
        features: AirportFeatureScores
    ) -> float:
        """
        Compute persona-specific score from base features.
        
        Formula:
            score = Σ(weight[feature] * feature_value)
        
        Returns:
            Score in [0, 1] range (assuming features are normalized).
        """
        # Get persona config
        # For each feature in features, multiply by persona weight
        # Sum and return
    
    def compute_scores_for_all_personas(
        self,
        features: AirportFeatureScores
    ) -> Dict[str, float]:
        """
        Compute scores for all personas.
        
        Returns:
            Dict mapping persona_id -> score
        """
        # For each persona, call compute_score
        # Return dict
```

---

## 8. NLP Pipeline (LangChain 1.0)

### 8.1 Review Tag Extraction (`nlp/extractor.py`)

```python
# nlp/extractor.py - LLM-based review tag extraction

from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import PydanticOutputParser
from langchain_openai import ChatOpenAI
from tenacity import retry, stop_after_attempt, wait_exponential

class ReviewExtractor:
    """
    Extracts structured tags from free-text reviews using LLM.
    
    Features:
        - Retry logic for transient failures
        - Token usage tracking
        - Error handling with specific exceptions
    """
    
    def __init__(
        self,
        ontology: OntologyConfig,
        llm_model: str,
        llm_temperature: float,
        api_key: Optional[str] = None,
        max_retries: int = 3
    ):
        """
        Initialize extractor with LLM.
        
        Creates LangChain chain:
            prompt -> llm -> PydanticOutputParser(ReviewExtraction)
        
        Args:
            max_retries: Maximum number of retry attempts for LLM calls
        """
        # Build prompt template with ontology embedded
        # Create ChatOpenAI instance
        # Create PydanticOutputParser for ReviewExtraction
        # Chain: prompt | llm | parser
        # Store max_retries for retry logic
        # Initialize token usage tracking
    
    def extract(self, review_text: str, review_id: Optional[str] = None) -> ReviewExtraction:
        """
        Extract tags from a single review.
        
        Returns:
            ReviewExtraction with aspect-label pairs.
        
        Raises:
            ReviewExtractionError if LLM call fails or output doesn't match schema.
        """
        # Invoke chain with review_text
        # Track token usage
        # Handle retries for transient failures
        # Set review_id on result
        # Return ReviewExtraction
        # Raise ReviewExtractionError on failure
    
    def extract_batch(
        self,
        reviews: List[Tuple[str, Optional[str]]]  # (text, review_id)
    ) -> List[ReviewExtraction]:
        """
        Extract tags from multiple reviews (batched for efficiency).
        
        Can batch multiple reviews into single LLM call if model supports,
        or process sequentially with retries.
        """
        # Option 1: Single prompt with multiple reviews (if LLM supports)
        # Option 2: Process sequentially with batch() for parallelization
        # Apply confidence threshold
        # Return list of ReviewExtraction
```

**Design Decision: Batch Processing**

- **Option A:** Single LLM call with multiple reviews in prompt
  - **Pros:** Fewer API calls, lower cost
  - **Cons:** Token limits, harder error handling per review
- **Option B:** Sequential with LangChain's `batch()` for parallelization
  - **Pros:** Better error isolation, easier retry logic
  - **Cons:** More API calls
- **Choice:** Start with Option B (sequential with batch), add Option A as optimization later.

### 8.2 Tag Aggregation (`nlp/aggregator.py`)

```python
# nlp/aggregator.py - Aggregate tags into feature scores

class TagAggregator:
    """Aggregates review tags into normalized feature scores."""
    
    def __init__(self, ontology: OntologyConfig):
        """Initialize with ontology for label mapping."""
        # Store ontology
    
    def aggregate_tags(
        self,
        icao: str,
        tags: List[ReviewExtraction]
    ) -> AirportFeatureScores:
        """
        Aggregate tags for an airport into feature scores.
        
        Process:
            1. Group tags by aspect
            2. Count label distributions (weighted by confidence)
            3. Map distributions to normalized scores [0, 1]
            4. Return AirportFeatureScores
        
        Feature mappings (examples):
            - ga_cost_score: from 'cost' aspect labels (cheap=1.0, expensive=0.0)
            - ga_hassle_score: from 'bureaucracy' aspect (simple=1.0, complex=0.0)
            - ga_review_score: from 'overall_experience' aspect
            - ga_fun_score: from 'food', 'overall_experience' aspects
        """
        # Group by aspect
        # For each aspect, compute weighted label distribution
        # Map to feature scores using mapping rules
        # Return AirportFeatureScores
    
    def compute_label_distribution(
        self,
        aspect: str,
        tags: List[AspectLabel]
    ) -> Dict[str, float]:
        """
        Compute weighted distribution of labels for an aspect.
        
        Returns:
            Dict mapping label -> weighted count (sum of confidences)
        """
        # Filter tags for this aspect
        # Sum confidences per label
        # Return dict
```

### 8.3 Summary Generation (`nlp/summarizer.py`)

```python
# nlp/summarizer.py - LLM-based airport summary generation

class SummaryGenerator:
    """Generates airport-level summaries from aggregated data."""
    
    def __init__(
        self,
        llm_model: str,
        llm_temperature: float,
        api_key: Optional[str] = None
    ):
        """
        Initialize with LLM.
        
        Creates LangChain chain:
            prompt -> llm -> JSON parser (for summary_text + tags_json)
        """
        # Build prompt template
        # Create ChatOpenAI instance
        # Create JSON output parser
        # Chain: prompt | llm | parser
    
    def generate_summary(
        self,
        icao: str,
        tags: List[ReviewExtraction],
        rating_avg: Optional[float],
        rating_count: int,
        feature_scores: AirportFeatureScores
    ) -> Tuple[str, List[str]]:
        """
        Generate summary text and tags for an airport.
        
        Returns:
            (summary_text, tags_json)
            - summary_text: 2-4 sentence summary
            - tags_json: List of human-readable tags like ["GA friendly", "expensive"]
        
        Prompt includes:
            - Aggregated tags (top aspects)
            - Rating stats
            - Feature scores (for context)
            - Instructions to generate concise, pilot-focused summary
        """
        # Build prompt with all context
        # Invoke chain
        # Parse JSON response
        # Return (summary_text, tags_json)
```

---

## 9. Feature Engineering

### 9.1 Feature Score Mapping (`features.py`)

```python
# features.py - Map label distributions to normalized feature scores

class FeatureMappingConfig(BaseModel):
    """Configuration for a single feature mapping."""
    aspect: str
    label_weights: Dict[str, float]  # label -> weight (0.0-1.0)

class FeatureMappingsConfig(BaseModel):
    """Loaded feature_mappings.json structure."""
    version: str
    mappings: Dict[str, FeatureMappingConfig]  # feature_name -> mapping

class FeatureMapper:
    """
    Maps ontology label distributions to normalized feature scores.
    
    Supports configurable mappings from JSON file, with hard-coded defaults
    as fallback.
    """
    
    def __init__(
        self,
        ontology: OntologyConfig,
        mappings_path: Optional[Path] = None
    ):
        """
        Initialize with ontology and optional mappings config.
        
        Args:
            ontology: Ontology configuration
            mappings_path: Optional path to feature_mappings.json.
                          If None, uses hard-coded default mappings.
        """
        # Store ontology
        # Load mappings from JSON if provided
        # Validate mappings against ontology
        # Store mappings (or use defaults)
    
    def map_cost_score(self, distribution: Dict[str, float]) -> float:
        """
        Map 'cost' aspect labels to ga_cost_score [0, 1].
        
        Uses mapping from config if available, otherwise defaults:
            - cheap -> 1.0
            - reasonable -> 0.6
            - expensive -> 0.0
            - unclear -> 0.5 (neutral)
        
        Returns weighted average based on distribution.
        
        Raises:
            FeatureMappingError if mapping fails.
        """
        # Get mapping config for 'ga_cost_score' (or use default)
        # Apply label weights to distribution
        # Return normalized score
        # Raise FeatureMappingError on failure
    
    def map_hassle_score(self, distribution: Dict[str, float]) -> float:
        """
        Map 'bureaucracy' aspect labels to ga_hassle_score [0, 1].
        
        Mapping:
            - simple -> 1.0
            - moderate -> 0.5
            - complex -> 0.0
        """
        # Similar to map_cost_score
    
    def map_review_score(self, distribution: Dict[str, float]) -> float:
        """
        Map 'overall_experience' aspect labels to ga_review_score [0, 1].
        
        Mapping:
            - very_positive -> 1.0
            - positive -> 0.75
            - neutral -> 0.5
            - negative -> 0.25
            - very_negative -> 0.0
        """
        # Similar pattern
    
    def map_ops_ifr_score(
        self,
        tags: List[ReviewExtraction],
        aip_data: Optional[Dict]  # From euro_aip if available
    ) -> float:
        """
        Compute ga_ops_ifr_score from tags + AIP data.
        
        Combines:
            - Review tags about IFR capability
            - AIP data (procedures available, runway length, etc.)
        
        Returns [0, 1] where 1.0 = excellent IFR support.
        """
        # Check AIP for IFR procedures
        # Check tags for IFR-related aspects
        # Combine into score
    
    def map_ops_vfr_score(
        self,
        tags: List[ReviewExtraction],
        aip_data: Optional[Dict]
    ) -> float:
        """Similar to map_ops_ifr_score but for VFR operations."""
        # Similar pattern
    
    def map_access_score(self, distribution: Dict[str, float]) -> float:
        """
        Map 'transport' aspect labels to ga_access_score [0, 1].
        
        How easy is it to get to/from the airport?
        """
        # Similar pattern
    
    def map_fun_score(
        self,
        tags: List[ReviewExtraction]
    ) -> float:
        """
        Map 'food', 'overall_experience' aspects to ga_fun_score [0, 1].
        
        Combines multiple aspects for "vibe" / enjoyment factor.
        """
        # Combine food, overall_experience distributions
        # Return composite score
```

**Design Decision: AIP Data Integration**

- **Question:** How to get AIP data (IFR procedures, runway info) for feature engineering?
- **Option A:** Query euro_aip.sqlite directly in feature mapper
  - **Pros:** Direct access, no coupling
  - **Cons:** Requires euro_aip dependency in feature mapper
- **Option B:** Pass AIP data as optional parameter (already in signature above)
  - **Pros:** Flexible, can work without euro_aip
  - **Cons:** Caller must fetch AIP data
- **Choice:** Option B (optional parameter). Builder will fetch AIP data when available.

**Design Decision: Configurable Feature Mappings**

- **Why:** Hard-coded mappings are hard to modify without code changes
- **Solution:** Load mappings from `feature_mappings.json` if provided
- **Fallback:** Use hard-coded defaults if config not provided
- **Validation:** Validate mappings against ontology on load
- **Versioning:** Mappings config has version field for tracking changes

---

## 10. Main Pipeline Orchestrator

### 10.1 Builder (`builder.py`)

```python
# builder.py - Main pipeline orchestrator

import structlog
from typing import Optional
from datetime import datetime
from dataclasses import dataclass, field

logger = structlog.get_logger(__name__)

@dataclass
class BuildMetrics:
    """Track build statistics."""
    airports_processed: int = 0
    reviews_extracted: int = 0
    llm_calls: int = 0
    llm_tokens_used: int = 0
    errors: int = 0
    failed_icaos: List[str] = field(default_factory=list)
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None

@dataclass
class BuildResult:
    """Result of build operation."""
    success: bool
    metrics: BuildMetrics
    error: Optional[Exception] = None

class GAFriendlinessBuilder:
    """
    Orchestrates the full pipeline to build ga_meta.sqlite.
    
    Supports:
        - Full rebuild
        - Incremental updates
        - Dependency injection for testing
        - Progress tracking
        - Error handling with partial failure support
    """
    
    def __init__(
        self,
        settings: GAFriendlinessSettings,
        *,
        storage: Optional[GAMetaStorage] = None,
        extractor: Optional[ReviewExtractor] = None,
        aggregator: Optional[TagAggregator] = None,
        feature_mapper: Optional[FeatureMapper] = None,
        persona_manager: Optional[PersonaManager] = None
    ):
        """
        Initialize builder with settings and optional dependency injection.
        
        If dependencies not provided, creates them from settings.
        Useful for testing with mocks.
        
        Loads:
            - Ontology
            - Personas
            - Feature mappings (if configured)
            - Creates storage instance
            - Initializes NLP components
        """
        # Store settings
        # Load ontology and personas
        # Load feature mappings if configured
        # Create or use injected dependencies:
        #   - storage
        #   - extractor
        #   - aggregator
        #   - feature_mapper
        #   - persona_manager
        # Initialize metrics
    
    def build(
        self,
        reviews_source: ReviewSource,
        euro_aip_path: Optional[Path] = None,
        incremental: bool = False,
        since: Optional[datetime] = None,
        icaos: Optional[List[str]] = None
    ) -> BuildResult:
        """
        Main entry point: build ga_meta.sqlite from reviews.
        
        Pipeline:
            1. Load reviews from source
            2. Group reviews by ICAO
            3. Filter for incremental update if requested
            4. For each ICAO:
                a. Extract tags (LLM) with retry logic
                b. Aggregate tags → feature scores
                c. Generate summary (LLM)
                d. Optionally fetch AIP data for ops scores
                e. Compute persona scores
                f. Write to database (in transaction)
            5. Write metadata (versions, timestamps)
            6. Return build result with metrics
        
        Args:
            reviews_source: Provides reviews (see ReviewSource interface)
            euro_aip_path: Optional path to euro_aip.sqlite for AIP data
            incremental: If True, only process airports with changes
            since: For incremental mode, only process reviews updated since this date
            icaos: Optional list of specific ICAOs to process
        
        Returns:
            BuildResult with success status, metrics, and any errors
        """
        metrics = BuildMetrics()
        metrics.start_time = datetime.utcnow()
        
        try:
            # Load reviews
            # Group by ICAO
            # Filter for incremental if requested:
            #   - Check storage.has_changes() for each ICAO
            #   - Filter by since date if provided
            #   - Filter by icaos if provided
            
            # Process each ICAO (with progress tracking)
            with self.storage:  # Transaction context
                for icao, airport_reviews in by_icao.items():
                    try:
                        logger.info("processing_airport", icao=icao, review_count=len(airport_reviews))
                        self.process_airport(icao, airport_reviews, ...)
                        metrics.airports_processed += 1
                        logger.info("airport_processed", icao=icao)
                    except Exception as e:
                        logger.error("airport_failed", icao=icao, error=str(e))
                        metrics.errors += 1
                        metrics.failed_icaos.append(icao)
                        # Continue processing other airports
            
            # Write metadata (versions, timestamps)
            # Log completion
            metrics.end_time = datetime.utcnow()
            return BuildResult(success=True, metrics=metrics)
            
        except Exception as e:
            logger.error("build_failed", error=str(e))
            metrics.end_time = datetime.utcnow()
            return BuildResult(success=False, metrics=metrics, error=e)
    
    def process_airport(
        self,
        icao: str,
        reviews: List[RawReview],
        aip_data: Optional[Dict] = None,
        airport_stats: Optional[Dict] = None
    ) -> None:
        """
        Process a single airport: extract, aggregate, summarize, score, write.
        
        This is the core per-airport processing logic.
        All operations are within the storage transaction context.
        
        Args:
            icao: Airport ICAO code
            reviews: List of reviews for this airport
            aip_data: Optional AIP data from euro_aip.sqlite
            airport_stats: Optional stats from airfield.directory individual JSON:
                - average_rating: float
                - landing_fees: Dict by aircraft type
                - fuel_prices: Dict
        
        Raises:
            BuildError if processing fails (extraction, aggregation, etc.)
        """
        try:
            # Extract tags from reviews (with retry logic)
            # Track LLM token usage
            # Aggregate tags → feature scores
            # Incorporate airport_stats (average_rating, landing fees) if available
            # Generate summary (with retry logic)
            # Compute persona scores
            # Build AirportStats (include rating_avg, fee_band_* from airport_stats)
            # Write to storage (within transaction)
            # Update last_processed_timestamp in metadata
        except Exception as e:
            logger.error("airport_processing_failed", icao=icao, error=str(e))
            raise BuildError(f"Failed to process airport {icao}: {e}") from e
    
    def fetch_aip_data(self, icao: str, euro_aip_path: Path) -> Optional[Dict]:
        """
        Fetch AIP data for an airport from euro_aip.sqlite.
        
        Returns:
            Dict with IFR procedures, runway info, etc. (or None if not found)
        """
        # ATTACH euro_aip
        # Query airport, procedures, runways
        # Return structured dict
```

### 10.2 Review Source Interface

```python
# Abstract interface for review sources

class RawReview(BaseModel):
    """Raw review from source."""
    icao: str
    review_text: str  # Primary language text
    review_id: str  # Unique ID (format: "ICAO#sha256" for airfield.directory)
    rating: Optional[float] = None  # 1-5 scale, can be null
    timestamp: Optional[str] = None  # ISO format: "2025-08-15T00:00:00.000Z"
    language: str = "EN"  # Language code of review_text (EN, DE, IT, FR, ES, NL)
    ai_generated: bool = False  # Whether review is AI-generated
    likes_count: int = 0  # Number of likes (for future use)

class ReviewSource(ABC):
    """Abstract interface for review sources."""
    
    @abstractmethod
    def get_reviews(self) -> List[RawReview]:
        """Load all reviews from source."""
        pass
    
    @abstractmethod
    def get_source_version(self) -> str:
        """Return version identifier for this source snapshot."""
        pass

# Example implementations (not in this library, but interface defined):
# - AirfieldDirectorySource (scrapes/API from airfield.directory)
# - CSVReviewSource (reads from CSV export)
# - JSONReviewSource (reads from JSON file)
# - CompositeReviewSource (combines multiple sources)
# - DatabaseReviewSource (reads from existing ga_meta.sqlite)
# - Custom API sources (future: other review platforms)
```

**Design Decision: Source Abstraction**

- **Why:** Allows different review sources (airfield.directory, manual CSV, future APIs)
- **Implementation:** Abstract base class with concrete implementations outside library
- **CLI tool** will provide a concrete implementation (e.g., `CSVReviewSource`)
- **Multiple sources:** Can combine sources using `CompositeReviewSource` (see below)

### 10.2.1 Combining Multiple Sources

```python
# Composite pattern for combining multiple review sources

class CompositeReviewSource(ReviewSource):
    """
    Combines reviews from multiple sources.
    
    Useful for:
        - Merging airfield.directory + manual CSV reviews
        - Combining different API sources
        - Adding custom reviews to existing data
    """
    
    def __init__(self, sources: List[ReviewSource]):
        """
        Initialize with list of sources.
        
        Args:
            sources: List of ReviewSource instances to combine
        """
        # Store sources list
    
    def get_reviews(self) -> List[RawReview]:
        """
        Combine reviews from all sources.
        
        Handles:
            - Deduplication by review_id (if same ID appears in multiple sources)
            - Merging reviews for same airport
            - Preserving source metadata if needed
        
        Returns:
            Combined list of RawReview objects
        """
        # For each source, call get_reviews()
        # Combine lists
        # Deduplicate by review_id (keep first occurrence or merge)
        # Return combined list
    
    def get_source_version(self) -> str:
        """
        Return composite version string.
        
        Returns:
            String like "composite:airfield.directory-2025-11-23+csv-2025-01-15"
        """
        # Combine source versions from all sources
        # Return composite string
```

**Usage Example:**

```python
# In CLI tool or builder:
airfield_source = AirfieldDirectorySource(export_path)
csv_source = CSVReviewSource(csv_path)
composite = CompositeReviewSource([airfield_source, csv_source])

builder = GAFriendlinessBuilder(settings)
builder.build(composite, euro_aip_path)
```

**Design Decision: Extensibility**

- **Adding new sources:** Simply implement the `ReviewSource` interface
- **No library changes needed:** New sources can be added in CLI tool or separate module
- **Deduplication:** `CompositeReviewSource` handles deduplication by `review_id`
- **Source priority:** In composite, first source takes precedence for duplicate IDs
- **Future sources could include:**
  - Other review platforms/APIs
  - Manual curation sources
  - Scraped data (with proper licensing)
  - User-submitted reviews from your own platform

### 10.3 AirfieldDirectorySource Implementation

Based on the actual airfield.directory API structure, here's the concrete implementation:

```python
# In tools/build_ga_friendliness.py or shared/ga_friendliness/sources.py

class AirfieldDirectorySource(ReviewSource):
    """
    Loads reviews from airfield.directory bulk export.
    
    Supports:
        - Individual airport JSON: https://airfield.directory/airfield/{ICAO}.json
        - Bulk export: S3 bucket airfield-directory-pirep-export
        - Format: airfield-directory-pireps-export-latest.json.gz
    """
    
    def __init__(
        self,
        export_path: Path,  # Path to .json or .json.gz file
        filter_ai_generated: bool = True,  # Filter out AI-generated reviews
        preferred_language: str = "EN"  # Primary language for review text
    ):
        """
        Initialize source.
        
        Args:
            export_path: Path to bulk export JSON file
            filter_ai_generated: If True, exclude reviews with ai_generated=true
            preferred_language: Language code (EN, DE, IT, FR, ES, NL) for review text
        """
        # Store config
        # Load JSON (handle .gz if needed)
        # Parse structure
    
    def get_reviews(self) -> List[RawReview]:
        """
        Load all reviews from bulk export.
        
        Structure:
            {
                "metadata": {...},
                "pireps": {
                    "ICAO": {
                        "ICAO#id": {
                            "id": "...",
                            "content": {"EN": "...", "DE": "...", ...},
                            "language": "EN",
                            "rating": 4 or null,
                            "likes_count": 0,
                            "user": {...},
                            "created_at": "2025-08-15T00:00:00.000Z",
                            "updated_at": "...",
                            "ai_generated": true/false
                        }
                    }
                }
            }
        
        Returns:
            List of RawReview objects, one per PIREP
        """
        # Iterate through pireps dict
        # For each ICAO, iterate through reviews
        # Filter ai_generated if configured
        # Extract review_text from content[preferred_language] or fallback
        # Map to RawReview:
        #   - icao: from outer key
        #   - review_text: content[preferred_language] or first available
        #   - review_id: id field
        #   - rating: rating field (can be null)
        #   - timestamp: created_at or updated_at
        # Return list
    
    def get_source_version(self) -> str:
        """
        Extract version from export metadata.
        
        Returns:
            Version string like "airfield.directory-2025-11-23"
        """
        # Read metadata.export_date
        # Format as "airfield.directory-YYYY-MM-DD"
        # Return
    
    def get_airport_stats(self, icao: str) -> Optional[Dict]:
        """
        Get airport-level stats from individual airport JSON.
        
        Note: This requires fetching individual airport JSON files.
        For bulk processing, this would be called separately if needed.
        
        Returns:
            Dict with:
                - average_rating: float (from airfield.data.average_rating)
                - landing_fees: Dict by aircraft type (from aerops.data.landing_fees)
                - fuel_prices: Dict (from aerops.data.fuel_prices)
        """
        # Fetch https://airfield.directory/airfield/{ICAO}.json
        # Extract stats
        # Return dict
```

**Key Implementation Details:**

1. **Multi-language handling:**
   - Reviews have `content` dict with multiple languages (EN, DE, IT, FR, ES, NL)
   - Use `preferred_language` parameter, fallback to first available
   - Store primary language in `RawReview` for reference

2. **AI-generated filtering:**
   - Reviews have `ai_generated` boolean field
   - Default to filtering these out (can be configured)
   - Matches the jq filter pattern in documentation

3. **Rating handling:**
   - `rating` can be `null` (especially for AI-generated reviews)
   - Store as `Optional[float]` in `RawReview`
   - Airport-level `average_rating` available in individual airport JSON

4. **Landing fees:**
   - Available in `aerops.data.landing_fees` by aircraft type (PC12, DA42, C172, etc.)
   - Can be used to populate `ga_landing_fees` table
   - Fees have structure: `{"lineNet": ..., "price": ..., "tax": ..., "title": ...}`

5. **Bulk export format:**
   - Nested structure: `pireps[ICAO][review_id]`
   - Need to flatten to list of reviews
   - Metadata includes export date for versioning

**Updated RawReview Model:**

```python
class RawReview(BaseModel):
    """Raw review from source."""
    icao: str
    review_text: str  # Primary language text
    review_id: str  # Unique ID (format: "ICAO#sha256")
    rating: Optional[float] = None  # 1-5 scale, can be null
    timestamp: Optional[str] = None  # ISO format: "2025-08-15T00:00:00.000Z"
    language: str = "EN"  # Language code of review_text
    ai_generated: bool = False  # Whether review is AI-generated
    likes_count: int = 0  # Number of likes
```

---

## 11. CLI Tool

### 11.1 CLI Structure (`tools/build_ga_friendliness.py`)

```python
# tools/build_ga_friendliness.py - CLI tool for rebuilding ga_meta.sqlite

def main():
    """
    CLI entry point.
    
    Usage:
        # From airfield.directory bulk export:
        python tools/build_ga_friendliness.py \
            --airfield-directory-export path/to/airfield-directory-pireps-export-latest.json.gz \
            --euro-aip-db path/to/euro_aip.sqlite \
            --ga-meta-db path/to/ga_meta.sqlite \
            --ontology data/ontology.json \
            --personas data/personas.json \
            [--filter-ai-generated] \
            [--preferred-language EN] \
            [--llm-model gpt-4o-mini] \
            [--confidence-threshold 0.5] \
            [--batch-size 50] \
            [--cache-dir path/to/cache] \
            [--force-refresh] \
            [--never-refresh] \
            [--incremental] \
            [--since YYYY-MM-DD] \
            [--icaos ICAO1,ICAO2,...]
        
        # From CSV (for testing/manual data):
        python tools/build_ga_friendliness.py \
            --reviews-csv path/to/reviews.csv \
            --ga-meta-db path/to/ga_meta.sqlite \
            ...
        
        # Combining multiple sources:
        python tools/build_ga_friendliness.py \
            --airfield-directory-export path/to/airfield-export.json.gz \
            --reviews-csv path/to/additional-reviews.csv \
            --ga-meta-db path/to/ga_meta.sqlite \
            ...
    """
    # Parse arguments
    # Load settings (merge CLI args with env vars)
    # Create ReviewSource based on input type:
    #   - If --airfield-directory-export: AirfieldDirectorySource
    #   - If --reviews-csv: CSVReviewSource
    # Create GAFriendlinessBuilder
    # Call builder.build()
    # Print summary

def create_airfield_directory_source(
    export_path: Path,
    filter_ai_generated: bool = True,
    preferred_language: str = "EN"
) -> ReviewSource:
    """
    Create ReviewSource from airfield.directory bulk export.
    
    Args:
        export_path: Path to .json or .json.gz file
        filter_ai_generated: Filter out AI-generated reviews
        preferred_language: Language code for review text
    """
    # Create AirfieldDirectorySource instance
    # Return

def create_csv_review_source(csv_path: Path) -> ReviewSource:
    """
    Create ReviewSource from CSV file.
    
    CSV format (expected):
        icao,review_text,review_id,rating,timestamp,language,ai_generated
        LFQQ,"Great airport...",rev_123,4.5,2025-01-15T10:00:00Z,EN,false
    """
    # Read CSV
    # Parse rows into RawReview objects
    # Return ReviewSource implementation

def create_composite_source(
    sources: List[ReviewSource]
) -> ReviewSource:
    """
    Create composite source from multiple sources.
    
    Args:
        sources: List of ReviewSource instances to combine
    
    Returns:
        CompositeReviewSource that merges all sources
    """
    # Create CompositeReviewSource
    # Return

# Additional CLI commands (future):
# - validate-ontology: Validate ontology.json
# - validate-personas: Validate personas.json
# - compute-scores: Recompute scores for existing ga_meta.sqlite (without re-extraction)
```

**Design Decision: CLI Tool Location**

- **Option A:** In `tools/` directory (alongside `aipexport.py`, `foreflight.py`)
  - **Pros:** Consistent with existing tooling, easy to find
  - **Cons:** None
- **Option B:** In `shared/ga_friendliness/cli.py`
  - **Pros:** Co-located with library
  - **Cons:** Breaks pattern of tools/ directory
- **Choice:** Option A (`tools/build_ga_friendliness.py`)

---

## 12. Integration with euro_aip

### 12.1 Dependency Management

**Decision:** `ga_friendliness` library should **not** have a hard dependency on `euro_aip`.

**Rationale:**
- Design principle: ga_meta.sqlite is independent
- Runtime consumers may not need euro_aip
- Use ATTACH DATABASE pattern for joint queries

**How it works:**
- `ga_friendliness` uses **ICAO codes** as the linking key (strings)
- When AIP data is needed (for feature engineering), caller provides it
- Storage layer can ATTACH euro_aip.sqlite for queries, but doesn't require it

### 12.2 Integration Points

```python
# In builder.py or feature mapper:

def fetch_aip_data_for_features(icao: str, euro_aip_path: Path) -> Optional[Dict]:
    """
    Fetch AIP data needed for feature engineering.
    
    Uses euro_aip library if available, otherwise queries SQL directly.
    
    Returns:
        Dict with:
            - has_ifr_procedures: bool
            - runway_length_m: Optional[float]
            - has_customs: bool
            - etc.
    """
    # Try to import euro_aip (optional dependency)
    # If available, use DatabaseStorage to load airport
    # Otherwise, query SQL directly via ATTACH
    # Return structured dict
```

**Design Decision: Optional euro_aip Import**

- **Pattern:** Try/except import, fallback to direct SQL
- **Pros:** Works with or without euro_aip installed
- **Cons:** Slightly more complex code
- **Alternative:** Always use direct SQL (simpler, but less type-safe)
- **Choice:** Try/except pattern for flexibility

---

## 13. Web App Integration (Future)

### 13.1 API Endpoints (Conceptual)

```python
# web/server/api/ga_friendliness.py (future)

@router.get("/airports/{icao}/ga-friendliness")
def get_airport_ga_friendliness(
    icao: str,
    persona: Optional[str] = None
) -> Dict:
    """
    Get GA friendliness data for an airport.
    
    Returns:
        - Base feature scores
        - Persona-specific score (if persona provided)
        - Summary text and tags
        - Review stats
    """
    # ATTACH both databases
    # Query ga_airfield_stats, ga_review_summary
    # If persona provided, compute score (or read from denormalized column)
    # Return JSON

@router.get("/route/ga-friendly-airports")
def find_ga_friendly_along_route(
    route: List[Tuple[float, float]],  # lat/lon points
    corridor_width_nm: float = 20,
    persona: str = "ifr_touring_sr22",
    segment_length_nm: int = 100
) -> Dict:
    """
    Find GA-friendly airports along a route.
    
    Uses euro_aip for spatial queries, joins to ga_meta for scores.
    """
    # Use euro_aip spatial queries (R-tree)
    # Join to ga_airfield_stats
    # Compute persona scores
    # Segment by distance
    # Return structured response
```

### 13.2 Integration with Existing Tools

```python
# In shared/airport_tools.py (future extension)

def find_airports_near_route_with_ga_friendliness(
    context: ToolContext,
    route: List[Tuple[float, float]],
    persona: Optional[str] = None,
    **kwargs
) -> Dict[str, Any]:
    """
    Extend existing find_airports_near_route to include GA friendliness.
    
    If ga_meta.sqlite is available, attach it and include scores.
    """
    # Call existing find_airports_near_route logic
    # If ga_meta.sqlite exists, ATTACH and join
    # Add ga_friendliness fields to response
    # Return enhanced result
```

**Design Decision: Backward Compatibility**

- Existing tools should work **without** ga_meta.sqlite
- GA friendliness is **opt-in** enhancement
- Use LEFT JOIN so airports without GA data still appear

---

## 14. Testing Strategy

### 14.1 Unit Tests

```python
# tests/ga_friendliness/test_ontology.py
def test_ontology_validation()
def test_label_lookup()

# tests/ga_friendliness/test_personas.py
def test_persona_score_computation()
def test_weight_validation()

# tests/ga_friendliness/test_features.py
def test_cost_score_mapping()
def test_hassle_score_mapping()

# tests/ga_friendliness/test_nlp_extractor.py
def test_review_extraction()  # Mock LLM
def test_batch_extraction()

# tests/ga_friendliness/test_storage.py
def test_schema_creation()
def test_write_read_airfield_stats()
```

### 14.2 Integration Tests

```python
# tests/ga_friendliness/test_builder.py
def test_full_pipeline_with_mock_reviews()
def test_idempotent_rebuild()

# tests/ga_friendliness/test_integration_euro_aip.py
def test_joint_query_with_euro_aip()
def test_feature_engineering_with_aip_data()
```

### 14.3 Golden Data Tests

```python
# tests/ga_friendliness/test_golden_airports.py
def test_known_ga_friendly_airport_scores()
def test_known_expensive_airport_scores()

# Use a small set of airports with known characteristics
# Verify scores match expectations
```

---

## 15. Key Design Decisions Summary

### 15.1 Library Structure
- **Choice:** Standalone library in `shared/ga_friendliness/`
- **Rationale:** Clean separation, reusable, follows existing patterns

### 15.2 Configuration Format
- **Choice:** JSON (not YAML)
- **Rationale:** Simpler parsing, no extra dependency, consistent with project

### 15.3 LLM Framework
- **Choice:** LangChain 1.0
- **Rationale:** Already in project, modern API, good Pydantic integration

### 15.4 Database Linking
- **Choice:** ICAO codes as external keys, ATTACH DATABASE for queries
- **Rationale:** No hard dependency on euro_aip, flexible runtime usage

### 15.5 Persona Scores Storage
- **Choice:** Hybrid: one primary persona denormalized, others computed at runtime
- **Rationale:** Balance between query performance and flexibility

### 15.6 Review Source Abstraction
- **Choice:** Abstract ReviewSource interface, concrete implementations in CLI
- **Rationale:** Library stays source-agnostic, easy to add new sources

### 15.7 Feature Engineering AIP Integration
- **Choice:** Optional AIP data parameter, fetched by builder when available
- **Rationale:** Works with or without euro_aip, flexible

### 15.8 Batch Processing
- **Choice:** Sequential with LangChain batch() for parallelization
- **Rationale:** Better error handling, can optimize later

### 15.9 Caching Strategy
- **Choice:** Independent `CachedDataLoader` utility (not reusing euro_aip's CachedSource)
- **Rationale:** 
  - Maintains library independence (design principle)
  - Simpler implementation (JSON only, no CSV/PDF)
  - Supports gzip for large files
  - Follows same conceptual pattern (familiar to developers)
- **Caching targets:**
  - Bulk export from S3 (7-day cache)
  - Individual airport JSON (30-day cache)
- **CLI flags:** `--force-refresh`, `--never-refresh`, `--cache-dir`

### 15.10 Error Handling & Resilience
- **Choice:** Exception hierarchy with specific error types
- **Rationale:** Clear error handling, better debugging, retry logic support
- **Implementation:** Base `GAFriendlinessError` with domain-specific subclasses

### 15.11 Transaction Management
- **Choice:** Context manager pattern for transactions
- **Rationale:** Atomic operations, automatic rollback on errors, thread-safe
- **Implementation:** Storage class supports `with` statement, batch writes

### 15.12 Configurable Feature Mappings
- **Choice:** Load mappings from JSON with hard-coded defaults
- **Rationale:** Easy to modify without code changes, versioned config
- **Implementation:** `feature_mappings.json` with validation against ontology

### 15.13 Incremental Updates
- **Choice:** Support incremental mode with change detection
- **Rationale:** Efficient updates when only some airports change, faster rebuilds
- **Implementation:** `has_changes()` method, `--incremental` CLI flag, `--since` date filter

### 15.14 Schema Versioning
- **Choice:** Track schema version, support migrations
- **Rationale:** Safe schema evolution, backward compatibility
- **Implementation:** Version in `ga_meta_info`, migration framework

### 15.15 Resource Management
- **Choice:** Context managers for database connections and LLM clients
- **Rationale:** Automatic cleanup, proper resource handling
- **Implementation:** `__enter__`/`__exit__` methods, `close()` methods

### 15.16 Dependency Injection
- **Choice:** Optional dependency injection in Builder constructor
- **Rationale:** Testability with mocks, flexible component replacement
- **Implementation:** Optional parameters with defaults that create dependencies

### 15.17 Structured Logging
- **Choice:** Use structlog for structured logging with context
- **Rationale:** Better observability, easier debugging, progress tracking
- **Implementation:** Structured log events with context (icao, review_count, etc.)

---

## 16. Open Questions & Decisions

*Note: As decisions are made, replace "Suggestion:" with "Decision:" and add rationale if different from suggestion.*

### 16.1 Non-ICAO Fields
- **Question:** How to handle non-ICAO strips?
- **Suggestion:** Start with ICAO-only, add pseudo-ICAO mapping later if needed
- **Decision:** Start with ICAO only

### 16.2 Missing Data Handling
- **Question:** Neutral score (0.5) vs NULL for airports without reviews?
- **Suggestion:** NULL with flag, let UI decide how to display
- **Decision:**  NULL with flag, so we can decide later

### 16.3 Persona Explosion
- **Question:** How many personas to support in UI?
- **Suggestion:** Start with 3 (IFR touring, VFR budget, training), add more as needed
- **Decision:** yes start with these 3

### 16.4 Learned Weights
- **Question:** ML-based persona weights from user feedback?
- **Suggestion:** Phase 2 feature, keep hand-tuned weights for now
- **Decision:** yes, hand-tuned for now, we'll see later

### 16.5 Review Text Storage
- **Question:** Store raw review text excerpts or only tags?
- **Suggestion:** Start with tags only (privacy/licensing), add excerpts later if needed
- **Decision:** tag only

---

## 17. Implementation Phases

### Phase 1: Core Infrastructure & Caching
1. Create library structure
2. Implement exception hierarchy
3. Implement models (Pydantic)
4. Implement caching utility (CachedDataLoader)
5. Implement database schema with versioning
6. Implement storage with transaction support
7. Implement ontology and persona loading
8. Implement feature mappings loading
9. Unit tests for core components

### Phase 2: NLP Pipeline
1. Implement ReviewExtractor with LangChain (with retry logic)
2. Implement TagAggregator
3. Implement SummaryGenerator (with retry logic)
4. Add token usage tracking
5. Integration tests with mock LLM

### Phase 3: Feature Engineering
1. Implement FeatureMapper with configurable mappings
2. Implement scoring functions
3. Integration with optional AIP data
4. Add feature mapping validation
5. Golden data tests

### Phase 4: Builder & CLI
1. Implement GAFriendlinessBuilder with dependency injection
2. Add incremental update support
3. Add structured logging and progress tracking
4. Add error handling and partial failure support
5. Implement CSVReviewSource
6. Create CLI tool with all flags
7. Add resource management (context managers)
8. End-to-end test with sample data

### Phase 5: Web Integration (Future)
1. API endpoints
2. Integration with existing tools
3. UI components for displaying scores

---

*End of implementation plan. Ready for review and iteration.*

