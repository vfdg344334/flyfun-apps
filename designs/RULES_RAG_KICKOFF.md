# Rules RAG Enhancement - Implementation Kickoff

**Status:** ✅ APPROVED - Ready to Start  
**Start Date:** 2025-12-02  
**Expected Completion:** ~4 weeks

---

## 🎯 Quick Reference

**All decisions finalized:** See [RULES_RAG_DECISIONS_FINAL.md](./RULES_RAG_DECISIONS_FINAL.md)

### Key Decisions Summary

| Decision | Choice |
|----------|--------|
| **Router** | Keyword pre-filter + LLM for ambiguous |
| **"Both" Path** | Database-only for testing, Sequential before production |
| **Country Extraction** | Names + ISO-2 + ICAO codes, context-aware |
| **Embeddings** | Local (dev), OpenAI (prod if better) |
| **RAG Build** | Integrate into xls_to_rules.py |
| **Performance** | Working first, optimize later |

---

## 🚀 Phase 1: RAG Foundation (THIS WEEK)

**Goal:** Working vector database and retrieval system

### Tasks Checklist

#### Day 1: Setup & Structure
- [ ] Create feature branch: `git checkout -b feature/rules-rag`
- [ ] Create `shared/aviation_agent/rules_rag.py`
- [ ] Add dependencies to requirements.txt:
  ```
  chromadb>=0.4.22
  sentence-transformers>=2.2.0
  ```
- [ ] Install dependencies: `source venv/bin/activate && pip install chromadb sentence-transformers`

#### Day 2: Vector DB Build
- [ ] Implement `EmbeddingProvider` class
  - Support `all-MiniLM-L6-v2` (local)
  - Abstract interface for easy swapping
- [ ] Implement `build_vector_db()` function
  - Read rules.json
  - Generate embeddings for all questions
  - Store in ChromaDB with metadata (country, category, answer, etc.)
- [ ] Test on sample rules.json

#### Day 3: Retrieval System
- [ ] Implement `RulesRAG` class
  - Initialize ChromaDB connection
  - Load existing vector DB
- [ ] Implement `retrieve_rules()` method
  - Embed query
  - Search with country filters
  - Return top-k matches with metadata
- [ ] Test retrieval quality manually

#### Day 4: Integration with xls_to_rules.py
- [ ] Modify `tools/xls_to_rules.py`
  - Add `--build-rag` / `--no-rag` flags
  - Add `--embedding-model` flag
  - Call `build_vector_db()` after rules.json generation
- [ ] Test full workflow: Excel → rules.json → vector DB
- [ ] Verify vector DB can be loaded and queried

#### Day 5: Testing & Documentation
- [ ] Write unit tests for:
  - `EmbeddingProvider`
  - `build_vector_db()`
  - `retrieve_rules()`
- [ ] Test with real rules.json
- [ ] Measure initial retrieval quality (10-20 sample queries)
- [ ] Document API in docstrings

### Deliverables

- ✅ `shared/aviation_agent/rules_rag.py` (~300-400 lines)
- ✅ Modified `tools/xls_to_rules.py` (~100 lines added)
- ✅ Unit tests in `tests/aviation_agent/test_rules_rag.py`
- ✅ Working vector DB in `cache/rules_vector_db/`
- ✅ Initial quality metrics

### Success Criteria

- Can build vector DB from rules.json ✓
- Can retrieve relevant rules for queries ✓
- Retrieval Precision@5 > 70% ✓
- All tests passing ✓

---

## 📋 Implementation Guide

### File Structure (Phase 1)

```
shared/aviation_agent/
  rules_rag.py              # NEW: RAG system
  __init__.py               # MODIFIED: Export RulesRAG

tools/
  xls_to_rules.py           # MODIFIED: Add vector DB build

cache/
  rules_vector_db/          # NEW: ChromaDB storage
    chroma.sqlite3
    ...

tests/aviation_agent/
  test_rules_rag.py         # NEW: Tests
```

### Key Classes to Implement

#### 1. EmbeddingProvider

```python
class EmbeddingProvider:
    """Abstraction for embedding models."""
    
    def __init__(self, model_name: str = "all-MiniLM-L6-v2"):
        """Initialize embedding model."""
        pass
    
    def embed(self, texts: List[str]) -> List[List[float]]:
        """Generate embeddings for texts."""
        pass
    
    def embed_query(self, query: str) -> List[float]:
        """Generate embedding for single query."""
        pass
```

#### 2. RulesRAG

```python
class RulesRAG:
    """RAG system for aviation rules retrieval."""
    
    def __init__(
        self,
        vector_db_path: Path,
        embedding_model: str = "all-MiniLM-L6-v2"
    ):
        """Initialize RAG system."""
        pass
    
    def retrieve_rules(
        self,
        query: str,
        countries: List[str],
        top_k: int = 5,
        similarity_threshold: float = 0.5
    ) -> List[Dict[str, Any]]:
        """Retrieve relevant rules using semantic search."""
        pass
```

#### 3. build_vector_db()

```python
def build_vector_db(
    rules_json_path: Path,
    vector_db_path: Path,
    embedding_model: str = "all-MiniLM-L6-v2",
) -> None:
    """Build vector database from rules.json."""
    pass
```

---

## 🧪 Testing Strategy

### Manual Testing (Day 3)

Test queries to validate retrieval:

```python
# Test 1: Simple rules query
query = "Do I need to file a flight plan in France?"
countries = ["FR"]
results = rag.retrieve_rules(query, countries, top_k=5)
# Expected: Questions about flight plans in France

# Test 2: Customs query
query = "Where do I clear customs?"
countries = ["FR"]
results = rag.retrieve_rules(query, countries, top_k=5)
# Expected: Questions about customs, POE, clearance

# Test 3: IFR/VFR query
query = "Can I fly VFR at night?"
countries = ["GB"]
results = rag.retrieve_rules(query, countries, top_k=5)
# Expected: Questions about VFR, night flying, regulations

# Test 4: Multi-country
query = "What are customs procedures?"
countries = ["FR", "DE", "CH"]
results = rag.retrieve_rules(query, countries, top_k=3)
# Expected: ~9 results (3 per country)
```

### Quality Metrics

Calculate for 20 sample queries:

```python
def calculate_precision_at_k(results: List[Dict], k: int = 5) -> float:
    """Calculate what % of top-k results are relevant."""
    relevant = sum(1 for r in results[:k] if is_relevant(r))
    return relevant / k

# Target: Precision@5 > 70%
```

---

## 🔧 Development Environment

### Setup Commands

```bash
# 1. Create branch
cd /Users/brice/Developer/public/flyfun-apps
git checkout -b feature/rules-rag

# 2. Activate venv
source venv/bin/activate

# 3. Install dependencies
pip install chromadb sentence-transformers

# 4. Create directory structure
mkdir -p cache/rules_vector_db
mkdir -p tests/aviation_agent

# 5. Run tests (as you build)
pytest tests/aviation_agent/test_rules_rag.py -v
```

### Testing the Build

```bash
# Build vector DB from rules.json
python tools/xls_to_rules.py \
    --defs data/rules_definitions.xlsx \
    --out data/rules.json \
    --add FR data/france_rules.xlsx \
    --build-rag

# Check vector DB created
ls -lh cache/rules_vector_db/

# Test retrieval (create simple test script)
python -c "
from shared.aviation_agent.rules_rag import RulesRAG
from pathlib import Path

rag = RulesRAG(Path('cache/rules_vector_db'))
results = rag.retrieve_rules(
    query='Do I need to file a flight plan?',
    countries=['FR'],
    top_k=5
)

for i, r in enumerate(results, 1):
    print(f'{i}. {r[\"question_text\"]} (score: {r[\"score\"]:.2f})')
"
```

---

## 📊 Progress Tracking

### Daily Check-ins

**Day 1 (Today):**
- Goal: Setup complete, structure in place
- Blockers: None expected
- Tomorrow: Start implementing embedding provider

**Day 2:**
- Goal: Vector DB build working
- Blockers: Embedding model download (first time)
- Tomorrow: Implement retrieval

**Day 3:**
- Goal: Retrieval working, manual testing
- Blockers: Quality tuning might take time
- Tomorrow: Integration with xls_to_rules.py

**Day 4:**
- Goal: Full workflow tested
- Blockers: Existing rules.json format issues?
- Tomorrow: Tests and documentation

**Day 5:**
- Goal: Phase 1 complete!
- Next: Plan Phase 2 (Router)

---

## 🆘 Troubleshooting

### Common Issues

**Issue:** ChromaDB installation fails
```bash
# Solution: Install build tools
pip install --upgrade pip setuptools wheel
pip install chromadb
```

**Issue:** Sentence-transformers model download slow
```bash
# Solution: Download once, cached automatically
python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('all-MiniLM-L6-v2')"
# Wait ~5 min for first download
```

**Issue:** Vector DB too large
```bash
# Check size
du -sh cache/rules_vector_db/
# Expected: 10-50MB for 500-1000 documents
```

**Issue:** Low retrieval quality (<70%)
- Check embedding model loaded correctly
- Verify questions are being embedded (not answers)
- Try increasing top_k
- Check country filters working

---

## 📝 Code Review Checklist

Before marking Phase 1 complete:

- [ ] Code follows project style (type hints, docstrings)
- [ ] All functions have docstrings with Args/Returns
- [ ] Unit tests cover main functionality
- [ ] Manual testing shows >70% precision
- [ ] No hardcoded paths (use Path, env vars)
- [ ] Error handling for missing files, DB errors
- [ ] Logging statements for debugging
- [ ] README.md updated with usage examples
- [ ] Dependencies added to requirements.txt
- [ ] Git commit messages are clear

---

## 🎉 Phase 1 Success!

When Phase 1 is complete, you'll have:

✅ A working RAG system that can:
- Build vector DB from rules.json
- Retrieve relevant rules semantically
- Filter by country
- Return top-k matches with scores

✅ Integrated into existing workflow:
- xls_to_rules.py builds vector DB automatically
- Vector DB stored in cache/
- Easy to rebuild when rules change

✅ Ready for Phase 2:
- Router can use retrieve_rules()
- Rules agent can synthesize from results
- Foundation is solid for building on

---

## 🚦 Go/No-Go Decision Points

### End of Day 2
**Question:** Is vector DB building successfully?
- ✅ Go: Vector DB contains documents, no errors
- ❌ No-go: Fix embedding/storage issues

### End of Day 3
**Question:** Is retrieval returning sensible results?
- ✅ Go: Top results are semantically related
- ❌ No-go: Tune similarity, check embeddings

### End of Phase 1
**Question:** Ready for Phase 2?
- ✅ Go: Precision >70%, tests pass, integrated
- ❌ No-go: Improve quality, fix blocking issues

---

## 📞 Questions During Implementation?

**Refer to:**
- Technical details: [RULES_RAG_AGENT_DESIGN.md](./RULES_RAG_AGENT_DESIGN.md) Section 7
- Decisions: [RULES_RAG_DECISIONS_FINAL.md](./RULES_RAG_DECISIONS_FINAL.md)
- Architecture: [RULES_RAG_ARCHITECTURE_DIAGRAM.md](./RULES_RAG_ARCHITECTURE_DIAGRAM.md)

**Need clarification?** Ask! Better to clarify early than rebuild later.

---

**Let's build! 🚀**

