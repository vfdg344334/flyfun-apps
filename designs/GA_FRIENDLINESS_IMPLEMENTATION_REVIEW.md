# GA Friendliness Implementation Plan - Architecture Review

This document provides a comprehensive review of the implementation plan with focus on extensibility, maintainability, and best practices.

---

## 1. Strengths

### ✅ Well-Designed Abstractions
- **ReviewSource interface**: Excellent abstraction for multiple data sources
- **CompositeReviewSource**: Good pattern for combining sources
- **CachedDataLoader**: Independent caching layer following familiar patterns

### ✅ Separation of Concerns
- Clear module boundaries (NLP, features, scoring, storage)
- Library independence from euro_aip
- Configuration separate from business logic

### ✅ Type Safety
- Extensive use of Pydantic models
- Type hints throughout
- Validation at boundaries

### ✅ Testability
- Good test structure outlined
- Mock-friendly design (LLM, sources)

---

## 2. Areas for Improvement

### 2.1 Error Handling & Resilience

**Current State:** Minimal error handling mentioned.

**Recommendations:**

1. **Add Error Types:**
```python
# shared/ga_friendliness/exceptions.py

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
```

2. **Retry Logic for LLM Calls:**
```python
# In nlp/extractor.py

from tenacity import retry, stop_after_attempt, wait_exponential

class ReviewExtractor:
    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=4, max=10)
    )
    def extract(self, review_text: str, review_id: Optional[str] = None) -> ReviewExtraction:
        # Existing implementation with retry on transient failures
```

3. **Partial Failure Handling:**
```python
# In builder.py

def build(self, ...) -> BuildResult:
    """
    Returns BuildResult with:
        - success_count: int
        - failure_count: int
        - failed_icaos: List[str]
        - errors: List[Tuple[str, Exception]]
    """
    # Continue processing even if some airports fail
    # Collect errors and return summary
```

**Action Items:**
- Add exception hierarchy
- Add retry logic for LLM calls
- Implement partial failure handling in builder
- Add error logging with context

---

### 2.2 Database Transaction Management

**Current State:** No mention of transactions, rollback, or atomicity.

**Recommendations:**

1. **Use Context Managers:**
```python
# In storage.py

class GAMetaStorage:
    def __enter__(self):
        """Context manager for transaction."""
        self.conn.execute("BEGIN TRANSACTION")
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is None:
            self.conn.commit()
        else:
            self.conn.rollback()
    
    def write_airfield_stats(self, stats: AirportStats) -> None:
        """Use savepoint for individual operations."""
        # Use SAVEPOINT for nested transactions
```

2. **Batch Writes:**
```python
def write_review_tags_batch(
    self,
    tags_by_icao: Dict[str, List[ReviewExtraction]]
) -> None:
    """
    Write tags for multiple airports in a single transaction.
    
    More efficient than individual writes.
    """
    # Use executemany for bulk inserts
    # Single transaction for all airports
```

**Action Items:**
- Add transaction support with context managers
- Implement batch write operations
- Add savepoint support for nested operations
- Document transaction boundaries

---

### 2.3 Feature Mapping Configuration

**Current State:** Feature mappings are hard-coded in `FeatureMapper` methods.

**Issue:** Hard to extend or modify without code changes.

**Recommendations:**

1. **Make Mappings Configurable:**
```python
# data/feature_mappings.json

{
  "version": "1.0",
  "mappings": {
    "ga_cost_score": {
      "aspect": "cost",
      "label_weights": {
        "cheap": 1.0,
        "reasonable": 0.6,
        "expensive": 0.0,
        "unclear": 0.5
      }
    },
    "ga_hassle_score": {
      "aspect": "bureaucracy",
      "label_weights": {
        "simple": 1.0,
        "moderate": 0.5,
        "complex": 0.0
      }
    }
  }
}
```

2. **Load Mappings in FeatureMapper:**
```python
# In features.py

class FeatureMapper:
    def __init__(
        self,
        ontology: OntologyConfig,
        mappings_path: Optional[Path] = None
    ):
        """
        Initialize with configurable mappings.
        
        If mappings_path provided, load from JSON.
        Otherwise, use default hard-coded mappings.
        """
        # Load mappings from JSON if provided
        # Validate mappings against ontology
        # Store for use in map_* methods
```

**Action Items:**
- Create feature_mappings.json schema
- Refactor FeatureMapper to load from config
- Keep hard-coded defaults as fallback
- Add validation of mappings against ontology

---

### 2.4 Logging & Observability

**Current State:** Basic logging mentioned, but not comprehensive.

**Recommendations:**

1. **Structured Logging:**
```python
# In builder.py

import structlog

logger = structlog.get_logger(__name__)

def process_airport(self, icao: str, ...) -> None:
    logger.info(
        "processing_airport",
        icao=icao,
        review_count=len(reviews),
        has_aip_data=aip_data is not None
    )
    # ... processing ...
    logger.info(
        "airport_processed",
        icao=icao,
        feature_scores={...},
        persona_scores={...}
    )
```

2. **Progress Tracking:**
```python
# In builder.py

from tqdm import tqdm

def build(self, ...) -> None:
    reviews = reviews_source.get_reviews()
    by_icao = group_by_icao(reviews)
    
    with tqdm(total=len(by_icao), desc="Processing airports") as pbar:
        for icao, airport_reviews in by_icao.items():
            self.process_airport(icao, airport_reviews, ...)
            pbar.update(1)
```

3. **Metrics Collection:**
```python
# In builder.py

class BuildMetrics:
    """Track build statistics."""
    airports_processed: int = 0
    reviews_extracted: int = 0
    llm_calls: int = 0
    llm_tokens_used: int = 0
    errors: int = 0
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
```

**Action Items:**
- Add structured logging throughout
- Add progress bars for long operations
- Track metrics (LLM calls, tokens, processing time)
- Add logging levels (DEBUG for detailed, INFO for progress)

---

### 2.5 LLM Cost Management

**Current State:** No mention of cost tracking or rate limiting.

**Recommendations:**

1. **Token Tracking:**
```python
# In nlp/extractor.py

class ReviewExtractor:
    def __init__(self, ...):
        self.token_usage = {
            "input_tokens": 0,
            "output_tokens": 0,
            "total_cost_usd": 0.0
        }
    
    def extract(self, ...) -> ReviewExtraction:
        # Track token usage from LLM response
        # Calculate cost based on model pricing
        # Update self.token_usage
```

2. **Rate Limiting:**
```python
# In nlp/extractor.py

from tenacity import retry, stop_after_attempt, wait_exponential

class ReviewExtractor:
    def __init__(self, ..., rate_limit_per_minute: int = 60):
        self.rate_limiter = RateLimiter(rate_limit_per_minute)
    
    def extract(self, ...) -> ReviewExtraction:
        with self.rate_limiter:
            # Make LLM call
```

3. **Cost Estimation:**
```python
# In builder.py

def estimate_cost(
    self,
    reviews: List[RawReview],
    model: str
) -> Dict[str, float]:
    """
    Estimate LLM costs before running.
    
    Returns:
        Dict with estimated tokens and cost.
    """
    # Estimate tokens per review
    # Calculate total tokens
    # Look up model pricing
    # Return estimate
```

**Action Items:**
- Add token usage tracking
- Implement rate limiting
- Add cost estimation function
- Log costs in build summary

---

### 2.6 Incremental Updates

**Current State:** Full rebuild every time.

**Issue:** Expensive to rebuild entire database when only a few airports change.

**Recommendations:**

1. **Incremental Update Mode:**
```python
# In builder.py

def build_incremental(
    self,
    reviews_source: ReviewSource,
    since: Optional[datetime] = None,
    icaos: Optional[List[str]] = None
) -> None:
    """
    Update only changed airports.
    
    Args:
        since: Only process reviews updated since this date
        icaos: Only process these specific airports
    """
    # Load existing ICAOs from database
    # Filter reviews by since date or icaos
    # Process only changed airports
    # Update database
```

2. **Change Detection:**
```python
# In storage.py

def get_last_processed_timestamp(self, icao: str) -> Optional[datetime]:
    """Get when airport was last processed."""
    # Query ga_meta_info or ga_airfield_stats
    # Return timestamp

def has_changes(
    self,
    icao: str,
    reviews: List[RawReview]
) -> bool:
    """
    Check if airport has new/changed reviews.
    
    Compares review timestamps with last processed time.
    """
    # Compare timestamps
    # Return True if changes detected
```

**Action Items:**
- Add incremental update mode
- Implement change detection
- Add CLI flag for incremental mode
- Document when to use full vs incremental

---

### 2.7 Schema Versioning & Migrations

**Current State:** Schema creation mentioned, but no versioning or migration strategy.

**Recommendations:**

1. **Schema Versioning:**
```python
# In database.py

SCHEMA_VERSION = "1.0"

def get_schema_version(conn: sqlite3.Connection) -> Optional[str]:
    """Get current schema version."""
    # Query ga_meta_info for 'schema_version'
    # Return version or None if not set

def create_schema(conn: sqlite3.Connection) -> None:
    """Create schema and set version."""
    # Create tables
    # Set schema_version in ga_meta_info

def migrate_schema(
    conn: sqlite3.Connection,
    from_version: str,
    to_version: str
) -> None:
    """
    Migrate schema from one version to another.
    
    Handles:
        - Adding new columns
        - Modifying existing columns (via ALTER TABLE)
        - Data transformations if needed
    """
    # Implement migration logic
    # Update schema_version
```

2. **Migration Scripts:**
```python
# shared/ga_friendliness/migrations/
#   __init__.py
#   v1_0_to_v1_1.py
#   v1_1_to_v1_2.py

# Each migration file:
def migrate(conn: sqlite3.Connection) -> None:
    """Migrate from previous version."""
    # ALTER TABLE statements
    # Data transformations
```

**Action Items:**
- Add schema version tracking
- Create migration framework
- Document migration process
- Add migration tests

---

### 2.8 Concurrency & Parallelization

**Current State:** Sequential processing of airports.

**Issue:** Could be slow for large datasets.

**Recommendations:**

1. **Parallel Airport Processing:**
```python
# In builder.py

from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
from multiprocessing import cpu_count

def build(self, ..., max_workers: Optional[int] = None) -> None:
    """
    Process airports in parallel.
    
    Args:
        max_workers: Number of parallel workers (default: cpu_count())
    """
    max_workers = max_workers or cpu_count()
    
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(self.process_airport, icao, reviews, ...)
            for icao, reviews in by_icao.items()
        }
        # Wait for completion, handle errors
```

2. **Thread-Safe Storage:**
```python
# In storage.py

import threading

class GAMetaStorage:
    def __init__(self, db_path: Path):
        self._lock = threading.Lock()
        # ...
    
    def write_airfield_stats(self, stats: AirportStats) -> None:
        with self._lock:
            # Thread-safe write
```

**Action Items:**
- Add parallel processing option
- Make storage thread-safe
- Add CLI flag for max_workers
- Test with concurrent access

---

### 2.9 Dependency Injection & Testability

**Current State:** Builder creates all dependencies internally.

**Issue:** Hard to test with mocks, tight coupling.

**Recommendations:**

1. **Dependency Injection:**
```python
# In builder.py

class GAFriendlinessBuilder:
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
        Initialize with optional dependency injection.
        
        If dependencies not provided, create from settings.
        Useful for testing with mocks.
        """
        self.storage = storage or GAMetaStorage(settings.ga_meta_db_path)
        self.extractor = extractor or ReviewExtractor(...)
        # ... etc
```

2. **Factory Functions:**
```python
# In builder.py

def create_builder(settings: GAFriendlinessSettings) -> GAFriendlinessBuilder:
    """Factory function for creating builder with all dependencies."""
    # Create all dependencies
    # Return builder
```

**Action Items:**
- Add dependency injection to Builder
- Create factory functions
- Update tests to use mocks
- Document testing patterns

---

### 2.10 Resource Management

**Current State:** No explicit resource cleanup mentioned.

**Recommendations:**

1. **Context Managers:**
```python
# In storage.py

class GAMetaStorage:
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Close database connections."""
        if hasattr(self, 'conn'):
            self.conn.close()

# In builder.py

def build(self, ...) -> None:
    with self.storage:
        # Processing
        # Connection automatically closed
```

2. **LLM Client Cleanup:**
```python
# In nlp/extractor.py

class ReviewExtractor:
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Clean up LLM client resources."""
        if hasattr(self, 'llm_client'):
            # Close connections, cleanup
```

**Action Items:**
- Add context managers for resources
- Document resource cleanup
- Add cleanup in error cases
- Test resource cleanup

---

### 2.11 Configuration Validation

**Current State:** Pydantic validation, but could be more comprehensive.

**Recommendations:**

1. **Path Validation:**
```python
# In config.py

class GAFriendlinessSettings(BaseSettings):
    @validator('euro_aip_db_path', 'ga_meta_db_path')
    def validate_paths(cls, v):
        """Validate paths exist (for read) or parent exists (for write)."""
        if v.exists() or v.parent.exists():
            return v
        raise ValueError(f"Path or parent must exist: {v}")
    
    @validator('ontology_json_path', 'personas_json_path')
    def validate_config_files(cls, v):
        """Validate config files exist."""
        if not v.exists():
            raise ValueError(f"Config file not found: {v}")
        return v
```

2. **Value Validation:**
```python
@validator('confidence_threshold')
def validate_confidence(cls, v):
    """Validate confidence threshold in [0, 1]."""
    if not 0 <= v <= 1:
        raise ValueError("confidence_threshold must be in [0, 1]")
    return v
```

**Action Items:**
- Add comprehensive validators
- Validate file existence
- Validate numeric ranges
- Add helpful error messages

---

### 2.12 Documentation & Type Hints

**Current State:** Good docstrings, but could add more.

**Recommendations:**

1. **API Documentation:**
```python
# Add module-level docstrings

"""
GA Friendliness Library

This library provides tools for enriching airport data with GA friendliness
scores based on reviews, fees, and operational characteristics.

Example:
    >>> from shared.ga_friendliness import GAFriendlinessBuilder, AirfieldDirectorySource
    >>> builder = GAFriendlinessBuilder(settings)
    >>> source = AirfieldDirectorySource(export_path, cache_dir)
    >>> builder.build(source)
"""
```

2. **Type Hints for Complex Types:**
```python
# Use TypedDict for complex return types

from typing import TypedDict

class BuildResult(TypedDict):
    """Result of build operation."""
    success_count: int
    failure_count: int
    failed_icaos: List[str]
    errors: List[Tuple[str, str]]  # (icao, error_message)
    metrics: BuildMetrics
```

**Action Items:**
- Add module docstrings
- Use TypedDict for complex returns
- Add examples to docstrings
- Generate API docs (Sphinx/MkDocs)

---

## 3. Additional Suggestions

### 3.1 Plugin Architecture for Feature Mappings

**Consider:** Making feature mappings pluggable.

```python
# shared/ga_friendliness/features/plugins.py

class FeatureMappingPlugin(ABC):
    """Plugin for custom feature mapping logic."""
    
    @abstractmethod
    def map_feature(
        self,
        feature_name: str,
        distribution: Dict[str, float]
    ) -> float:
        pass

# Allow custom plugins for specialized mappings
```

### 3.2 Observability Hook

**Consider:** Adding hooks for monitoring/observability.

```python
# In builder.py

class BuildObserver(ABC):
    """Observer for build progress."""
    
    @abstractmethod
    def on_airport_start(self, icao: str) -> None:
        pass
    
    @abstractmethod
    def on_airport_complete(self, icao: str, result: Dict) -> None:
        pass

# Builder can accept observer for custom monitoring
```

### 3.3 Dry-Run Mode

**Consider:** Add dry-run mode for testing.

```python
# In builder.py

def build(self, ..., dry_run: bool = False) -> BuildResult:
    """
    Build with optional dry-run mode.
    
    In dry-run:
        - Process all airports
        - Calculate scores
        - But don't write to database
        - Return results for inspection
    """
```

---

## 4. Priority Recommendations

### High Priority (Before Implementation)
1. ✅ Add error handling & exception hierarchy
2. ✅ Add transaction management
3. ✅ Make feature mappings configurable
4. ✅ Add structured logging
5. ✅ Add dependency injection for testing

### Medium Priority (During Implementation)
6. ⚠️ Add LLM cost tracking
7. ⚠️ Add incremental update mode
8. ⚠️ Add schema versioning
9. ⚠️ Add parallel processing option
10. ⚠️ Add resource management (context managers)

### Low Priority (Future Enhancements)
11. 🔵 Plugin architecture for mappings
12. 🔵 Observability hooks
13. 🔵 Dry-run mode
14. 🔵 Advanced monitoring/metrics

---

## 5. Summary

The implementation plan is **solid and well-thought-out**. The main areas for improvement are:

1. **Resilience**: Better error handling and retry logic
2. **Operational Concerns**: Logging, monitoring, cost tracking
3. **Flexibility**: Configurable feature mappings, incremental updates
4. **Maintainability**: Dependency injection, better resource management
5. **Robustness**: Transactions, schema migrations, validation

Most of these can be added incrementally during implementation without major architectural changes.

---

*End of review.*

