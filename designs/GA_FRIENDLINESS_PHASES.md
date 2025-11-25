# GA Friendliness Implementation Phases

This document outlines the phased implementation plan for the GA friendliness enrichment system. It is the authoritative source for implementation phases and is kept in sync with `GA_FRIENDLINESS_IMPLEMENTATION.md` Section 17.

---

## Overview

The implementation is organized into 6 phases with clear dependencies. Each phase builds on the previous one and includes validation criteria.

```
Phase 0 (Foundation)
    ↓
Phase 1 (Database) ──┐
    ↓                │
Phase 2 (NLP) ───────┼──→ Phase 4 (Builder)
    ↓                │
Phase 3 (Features) ──┘
    ↓
Phase 5 (AIP) ──────→ Phase 4 (integrated)
    ↓
Phase 6 (Web)
```

**Critical Path** for minimal working system: Phase 1 → Phase 2 → Phase 3 → Phase 4

---

## Phase 1: Core Infrastructure & Caching

**Goal:** Establish core structure, models, database schema, and caching.

### Tasks

1. **Library Structure**
   - Create `shared/ga_friendliness/` directory structure
   - Create `shared/ga_review_agent/` directory structure
   - Create `shared/ga_notification_requirement_agent/` directory structure
   - Set up `__init__.py` with public API exports

2. **Exception Hierarchy** (`exceptions.py`)
   - `GAFriendlinessError` (base)
   - `OntologyValidationError`
   - `PersonaValidationError`
   - `ReviewExtractionError`
   - `StorageError`
   - `FeatureMappingError`
   - `BuildError`
   - `AIPRuleParsingError`

3. **Core Models** (`models.py`)
   - `RawReview` - Raw input from sources (with `source` field for collision prevention)
   - `AspectLabel`, `ReviewExtraction` - Extraction results (with `timestamp` for time decay)
   - `OntologyConfig`, `PersonasConfig` - Configuration
   - `PersonaWeights`, `PersonaMissingBehaviors`, `PersonaConfig` - Persona definitions
   - `MissingBehavior` enum (NEUTRAL, NEGATIVE, POSITIVE, EXCLUDE)
   - `AggregationContext` - For optional time decay and Bayesian smoothing
   - `AirportFeatureScores`, `AirportStats` - Output models
   - `NotificationRule`, `ParsedAIPRules`, `RuleSummary` - AIP rule models

4. **Caching Utility** (`cache.py`)
   - `CachedDataLoader` base class
   - Support JSON and gzip formats
   - `force_refresh` and `never_refresh` flags
   - Cache directory management

5. **Database Schema** (`database.py`)
   - Schema versioning (`SCHEMA_VERSION = "1.0"`)
   - `create_schema()` - All tables including AIP tables
   - `migrate_schema()`, `ensure_schema_version()`
   - Tables: `ga_airfield_stats`, `ga_review_ner_tags`, `ga_review_summary`, `ga_meta_info`, `ga_landing_fees`, `ga_notification_requirements`, `ga_aip_rule_summary`
   - 6 fee bands: `fee_band_0_749kg`, `fee_band_750_1199kg`, `fee_band_1200_1499kg`, `fee_band_1500_1999kg`, `fee_band_2000_3999kg`, `fee_band_4000_plus_kg`
   - `notification_hassle_score` column
   - All 8 feature scores including `ga_hospitality_score`

6. **Storage Operations** (`storage.py`)
   - `GAMetaStorage` class with context manager
   - Transaction support, thread-safety
   - CRUD operations for all tables
   - `has_changes()` - Multi-strategy change detection
   - `get_processed_review_ids()`, `get_last_processed_timestamp()`
   - `compute_global_priors()`, `store_global_priors()`, `get_global_priors()` - For Bayesian smoothing
   - `get_last_successful_icao()` - For resume capability

7. **Configuration Loading** (`config.py`)
   - `GAFriendlinessSettings` with time decay and Bayesian smoothing flags
   - `load_ontology()`, `load_personas()`
   - Environment variable support

8. **Ontology & Persona Management** (`ontology.py`, `personas.py`)
   - `OntologyManager` - Validation, lookup
   - `PersonaManager` - Score computation with `MissingBehavior` handling

### Test Checkpoints

- [ ] Unit tests for all models (validation, serialization)
- [ ] Unit tests for exception hierarchy
- [ ] Unit tests for config loading
- [ ] Unit tests for schema creation and versioning
- [ ] Unit tests for storage operations (write/read/update)
- [ ] Unit tests for `has_changes()` logic
- [ ] Unit tests for persona score computation with MissingBehavior

---

## Phase 2: NLP Pipeline

**Goal:** Implement review extraction, aggregation, and summarization with LLM.

### Tasks

1. **Review Extractor** (`ga_review_agent/extractor.py`)
   - LangChain 1.0: `ChatPromptTemplate`, `ChatOpenAI`, `PydanticOutputParser`
   - `ReviewExtractor` class
   - `extract()`, `extract_batch()` methods
   - Preserve timestamps from `RawReview` in `ReviewExtraction`
   - Retry logic with tenacity
   - Token usage tracking

2. **Tag Aggregator** (`ga_review_agent/aggregator.py`)
   - `TagAggregator` class
   - `aggregate_tags()` - Group by aspect, compute distributions
   - `compute_label_distribution()` - Weighted by confidence
   - `_apply_time_decay()` - Optional time decay (disabled by default)
   - Support `AggregationContext` parameter

3. **Summary Generator** (`ga_review_agent/summarizer.py`)
   - LangChain 1.0 chain
   - `SummaryGenerator` class
   - `generate_summary()` - 2-4 sentence summary + tags

### Test Checkpoints

- [ ] Unit tests for tag aggregation (distributions, weighted counts)
- [ ] Unit tests for time decay logic (verify weights decrease with age)
- [ ] Integration tests with mock LLM
- [ ] Integration test: Full pipeline for one airport (extract → aggregate → summarize → store)

---

## Phase 3: Feature Engineering

**Goal:** Implement feature score mapping with optional Bayesian smoothing.

### Tasks

1. **Fee Band Aggregation** (`features.py`)
   - `AIRCRAFT_MTOW_MAP` constant
   - `get_mtow_for_aircraft()`, `get_fee_band_for_mtow()`
   - `aggregate_fees_by_band()` - Aircraft type → MTOW → fee band

2. **Feature Mapper** (`features.py`)
   - `FeatureMapper` class
   - Load mappings from JSON with hard-coded defaults
   - All mapping methods support `AggregationContext`:
     - `map_cost_score()` - from 'cost' aspect
     - `map_hassle_score()` - from 'bureaucracy' + AIP notification
     - `map_review_score()` - from 'overall_experience'
     - `map_ops_ifr_score()` - from tags + AIP data
     - `map_ops_vfr_score()` - from tags + AIP data
     - `map_access_score()` - from 'transport' aspect
     - `map_fun_score()` - from 'food', 'overall_experience'
     - `map_hospitality_score()` - from 'restaurant', 'accommodation' (availability/proximity)
   - Bayesian smoothing logic (disabled by default)

3. **Persona Scoring** (`personas.py`)
   - `compute_score()` with MissingBehavior handling
   - Re-normalization for EXCLUDE behavior
   - `compute_scores_for_all_personas()`

### Test Checkpoints

- [ ] Unit tests for fee band aggregation
- [ ] Unit tests for each feature mapping
- [ ] Unit tests for Bayesian smoothing (verify smoothing toward prior)
- [ ] Golden data tests (known airports with expected scores)

---

## Phase 4: Builder & CLI

**Goal:** Implement main orchestrator and CLI with full pipeline integration.

### Tasks

1. **Build Metrics** (`builder.py`)
   - `BuildMetrics` dataclass (airports, reviews, LLM usage, errors, timing, cache stats)
   - `BuildResult` dataclass
   - `FailureMode` enum (CONTINUE, FAIL_FAST, SKIP)

2. **Builder Orchestrator** (`builder.py`)
   - `GAFriendlinessBuilder` class
   - Dependency injection pattern
   - `build()` method:
     - Load reviews from source
     - Group by ICAO, sort for consistent order
     - Filter for incremental updates
     - **Resume capability** (`resume_from` parameter)
     - Per-airport transactions (allows resume on failure)
     - Store `last_successful_icao` checkpoint
   - `process_airport()` method:
     - Create `AggregationContext` if extensions enabled
     - Extract → aggregate → map → summarize → score → write
     - Fetch airport_stats (fees, rating) if `fetch_fees=True`
   - `process_aip_rules()` - Optional AIP processing
   - Structured logging with structlog

3. **Review Sources** (`sources.py` or in CLI)
   - `ReviewSource` abstract interface
   - `AirfieldDirectorySource`:
     - Bulk export (reviews only) from S3
     - Individual airport JSON (reviews + fees) with caching
     - `fetch_fees` flag
   - `CSVReviewSource` - For testing/manual data
   - `CompositeReviewSource` - Combine multiple sources
   - Review ID prefixing for collision prevention

4. **CLI Tool** (`tools/build_ga_friendliness.py`)
   - Source flags: `--airfield-directory-export`, `--reviews-csv`
   - Fee flags: `--fetch-fees`, `--no-fees`
   - Cache flags: `--cache-dir`, `--force-refresh`, `--never-refresh`
   - Incremental flags: `--incremental`, `--since`, `--icaos`
   - Resume flags: `--resume-from ICAO`, `--resume`
   - Failure mode: `--failure-mode {continue,fail_fast,skip}`
   - Metrics: `--metrics-output`
   - AIP: `--parse-aip-rules`, `--euro-aip-db`

### Test Checkpoints

- [ ] Unit tests for BuildMetrics, FailureMode
- [ ] Integration test: Full build with sample data
- [ ] Integration test: Incremental update (add review, verify only that airport processed)
- [ ] Integration test: Resume capability (fail mid-build, resume from checkpoint)
- [ ] Integration test: Failure modes (CONTINUE, FAIL_FAST, SKIP)
- [ ] End-to-end test: CLI with all flag combinations
- [ ] Test caching behavior (hits, misses, refresh flags)

---

## Phase 5: AIP Rule Parsing (Optional)

**Goal:** Add AIP notification rule parsing and integration with hassle scoring.

### Tasks

1. **AIP Source** (`ga_notification_requirement_agent/aip_source.py`)
   - `AIPSource` class
   - `get_airport_aip_text()` - Query euro_aip.sqlite
   - `get_all_airports()`, `get_last_aip_change_timestamp()`

2. **AIP Rule Parser** (`ga_notification_requirement_agent/rule_parser.py`)
   - LangChain 1.0: `ChatPromptTemplate`, `ChatOpenAI`, `PydanticOutputParser`
   - `AIPRuleParser` class
   - Hybrid regex/LLM approach
   - `parse_rules()` - Handle complex patterns (weekday-specific, business day, specific time)
   - `_try_regex_extraction()`, `_llm_extract_rules()`

3. **Rule Summarizer** (`ga_notification_requirement_agent/rule_summarizer.py`)
   - LangChain 1.0 chain
   - `AIPRuleSummarizer` class
   - `summarize_rules()` - Generate summary text + hassle level
   - `calculate_hassle_score()` - Normalized [0, 1] (1.0 = low hassle)

4. **Storage Extensions** (`storage.py`)
   - `write_notification_requirements()`
   - `write_aip_rule_summary()`
   - `update_notification_hassle_score()`
   - `get_last_aip_processed_timestamp()`, `update_last_aip_processed_timestamp()`

5. **Feature Integration** (`features.py`)
   - Update `map_hassle_score()` to combine review + AIP notification scores

6. **Builder Integration** (`builder.py`)
   - `process_aip_rules()` method
   - Incremental update support for AIP data

### Test Checkpoints

- [ ] Unit tests for regex rule extraction (common patterns)
- [ ] Unit tests for rule summarization (score calculation)
- [ ] Integration test: Parse rules for sample airport
- [ ] Integration test: Store rules and summary
- [ ] Integration test: Notification score integrated into hassle_score

---

## Phase 6: Web Integration (Future)

**Goal:** Integrate GA friendliness into web application.

### Tasks

1. API endpoints (`web/server/api/ga_friendliness.py`)
   - `GET /airports/{icao}/ga-friendliness`
   - `GET /route/ga-friendly-airports`

2. Integration with existing tools (`shared/airport_tools.py`)
   - Extend `find_airports_near_route` with GA friendliness

3. UI components
   - Display scores and summaries
   - Route-based search with persona selection

### Test Checkpoints

- [ ] API endpoint tests
- [ ] Integration tests with existing tools
- [ ] UI component tests

---

## Key Design Decisions (Reference)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Library location | `shared/ga_friendliness/` | Clean separation, reusable |
| Config format | JSON | Simple, no extra dependency |
| LLM framework | LangChain 1.0 | Modern API, Pydantic integration |
| Database linking | ICAO codes + ATTACH | No hard dependency on euro_aip |
| Fee currency | One per airport | Matches source data |
| Global priors storage | Single JSON key | Simpler read/write |
| Concurrent builds | Out of scope v1 | CLI warning only |
| MissingBehavior default | NEUTRAL (0.5) | Safe default, personas override |
| Test structure | Mirror source dirs | Clean organization |
| hospitality score | Availability/proximity | Not quality (that's in fun_score) |

---

## Optional Extensions (Disabled by Default)

Both implemented in Phases 2-3 but disabled by default:

### Time Decay
- Applies exponential decay to review weights based on age
- Formula: `weight = 1 / (1 + age_days / half_life_days)`
- Enable: `enable_time_decay=True`
- Requires timestamps in `ReviewExtraction`

### Bayesian Smoothing
- Smooths scores toward global prior for small sample sizes
- Formula: `smoothed = (local_score * n + prior * k) / (n + k)`
- Enable: `enable_bayesian_smoothing=True`
- Global priors computed once at build start or provided as fixed values

---

## Success Metrics Per Phase

| Phase | Criteria |
|-------|----------|
| 1 | All models validate, schema creates, storage operations work |
| 2 | Can extract tags from reviews, aggregate, generate summaries |
| 3 | Feature scores computed correctly, persona scores work |
| 4 | Can build complete database from reviews via CLI |
| 5 | Can parse AIP rules and integrate into scoring |
| 6 | Web app can display GA friendliness data |

---

*This document is synced with `GA_FRIENDLINESS_IMPLEMENTATION.md` Section 17.*

