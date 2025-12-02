# Rules RAG Enhancement - FINAL DECISIONS

**Date:** 2025-12-02  
**Status:** ✅ APPROVED - Ready for Implementation

---

## Decision Summary

All key decisions have been made. Implementation can proceed.

| # | Decision | Final Choice | Status |
|---|----------|--------------|--------|
| 1 | Router Complexity | **B: Keyword + LLM** | ✅ Approved |
| 2 | "Both" Path Handling | **C → A: Database-only MVP, then Sequential** | ✅ Approved |
| 3 | Country Extraction | **Enhanced: Names + ISO + ICAO + Context** | ✅ Approved |
| 4 | Embedding Model | **Hybrid: Local dev, OpenAI prod** | ✅ Approved |
| 5 | RAG Build Timing | **Integrate into xls_to_rules.py** | ✅ Approved |
| 6 | Clarification UX | **Yes, acceptable to ask** | ✅ Approved |
| 7 | Performance Priority | **Working first, optimize later** | ✅ Approved |
| 8 | MVP Scope | **Test without "both", add before production** | ✅ Approved |

---

## DECISION 1: Router Complexity ✅

### Final Choice: **Option B - Keyword Pre-Filter + LLM**

```python
class SmartRouter:
    def route(self, query: str, context: List[Message]) -> RouterDecision:
        # Fast keyword check for obvious cases
        rules_score = keyword_match_score(query, RULES_KEYWORDS)
        db_score = keyword_match_score(query, DATABASE_KEYWORDS)
        
        if rules_score > 2:  # Strong rules signal
            return RouterDecision(path="rules", confidence=0.9, countries=extract_countries(query, context))
        elif db_score > 2:  # Strong database signal
            return RouterDecision(path="database", confidence=0.9)
        else:
            # Ambiguous - use LLM
            return self.llm_classify(query, context)
```

**Rationale:**
- Fast path for ~80% of queries
- LLM for genuinely ambiguous queries
- Cost-effective

**Implementation Priority:** Phase 2 (Week 2)

---

## DECISION 2: "Both" Path Handling ✅

### Final Choice: **Start with C (Database-Only), Plan for A (Sequential)**

**Phase 1 (MVP Testing):**
- Router chooses primary intent: rules OR database
- No compound query handling
- Good for basic testing and validation

**Phase 2 (Before Production):**
- Implement sequential execution (A)
- Database results → Rules agent receives them as context
- **Reason:** "Combining answers will be important" for production quality

**Example Flow (Production):**
```
User: "Find customs airports in France with AVGAS and tell me customs procedures"

1. Router detects: "both" path needed
2. Execute database query:
   airports = find_airports(country="FR", point_of_entry=True, has_avgas=True)
   → Returns: LFMD, LFML, LFMN
   
3. Execute rules query with context:
   rules = retrieve_rules(query="customs procedures", countries=["FR"])
   
4. Synthesize combined answer:
   "I found 3 customs airports in France with AVGAS:
    - LFMD (Cannes)
    - LFML (Marseille)
    - LFMN (Nice)
    
    For customs procedures in France:
    [Rules synthesis here...]"
```

**Implementation Priority:**
- Phase 1 (Week 1-2): Database-only routing
- Phase 3 (Week 3): Sequential execution before production

---

## DECISION 3: Country Extraction ✅

### Final Choice: **Enhanced Multi-Format Support**

**Support Three Formats:**

1. **Country Names:** "Germany", "France", "United Kingdom"
2. **ISO-2 Codes:** "GB", "FR", "DE"
3. **ICAO Codes:** "EGTF", "LFMD" → Extract country from first 2 letters

**Example Queries:**
```
"What are the rules arriving at LFMD for IFR?"
→ Extract: LFMD → LF → France (FR)

"Customs procedures in Germany"
→ Extract: Germany → DE

"Flight plan requirements for GB"
→ Extract: GB (already ISO-2)

"What about EGTF?" (in conversation)
→ Extract: EGTF → EG → United Kingdom (GB)
```

**Disambiguation:**
- Use conversation context (last 3-5 messages)
- Ask for clarification if truly ambiguous
- **No support for:** Region groupings (Europe, Schengen, etc.)

**Implementation:**

```python
class CountryExtractor:
    """Extract countries from user queries supporting multiple formats."""
    
    # ICAO prefix to ISO-2 mapping
    ICAO_TO_ISO = {
        "LF": "FR",  # France
        "EG": "GB",  # United Kingdom
        "ED": "DE",  # Germany
        "LO": "AT",  # Austria
        "LS": "CH",  # Switzerland
        "EB": "BE",  # Belgium
        "EH": "NL",  # Netherlands
        "EI": "IE",  # Ireland
        "LE": "ES",  # Spain
        "LI": "IT",  # Italy
        # ... complete mapping
    }
    
    # Country name aliases
    COUNTRY_ALIASES = {
        "UK": "GB",
        "United Kingdom": "GB",
        "England": "GB",
        "Britain": "GB",
        "Germany": "DE",
        "France": "FR",
        "Switzerland": "CH",
        "Swiss": "CH",
        "Netherlands": "NL",
        "Holland": "NL",
        # ... complete mapping
    }
    
    def extract(self, query: str, conversation: List[Message]) -> List[str]:
        """Extract country codes from query and conversation context."""
        countries = []
        
        # 1. Try explicit ISO-2 codes (GB, FR, DE)
        countries.extend(self._extract_iso_codes(query))
        
        # 2. Try country names (Germany → DE)
        countries.extend(self._extract_country_names(query))
        
        # 3. Try ICAO codes (LFMD → LF → FR)
        countries.extend(self._extract_from_icao(query))
        
        # 4. Check conversation context if nothing found
        if not countries:
            for msg in reversed(conversation[-5:]):
                context_countries = self.extract(msg.content, [])
                if context_countries:
                    return context_countries
        
        return list(set(countries))  # Deduplicate
    
    def _extract_from_icao(self, text: str) -> List[str]:
        """Extract country from ICAO codes like LFMD → FR."""
        # Match 4-letter ICAO codes
        icao_pattern = r'\b([A-Z]{4})\b'
        matches = re.findall(icao_pattern, text)
        
        countries = []
        for icao in matches:
            prefix = icao[:2]
            if prefix in self.ICAO_TO_ISO:
                countries.append(self.ICAO_TO_ISO[prefix])
        
        return countries
```

**Implementation Priority:** Phase 2 (Week 2)

---

## DECISION 4: Embedding Model ✅

### Final Choice: **Hybrid Approach**

**Development & Initial Testing:**
- Model: `all-MiniLM-L6-v2` (local, HuggingFace)
- Cost: Free
- Quality: Good (75-80% precision)
- Speed: Fast (~10ms)
- **Purpose:** Rapid iteration, offline development

**Production (After Evaluation):**
- Model: `text-embedding-3-small` (OpenAI)
- Cost: ~$0.60/month
- Quality: Excellent (80-85% precision)
- Speed: Good (~100ms)
- **Condition:** If evaluation shows meaningful quality improvement

**Decision Point:**
- Build test dataset (100+ queries)
- Measure precision@5 for both models
- If OpenAI shows >5% improvement → upgrade
- Otherwise stick with local (free is good!)

**Implementation:**
```python
class EmbeddingProvider:
    """Abstraction for swappable embedding models."""
    
    def __init__(self, model_name: str = "all-MiniLM-L6-v2"):
        self.model_name = model_name
        
        if model_name == "all-MiniLM-L6-v2":
            from sentence_transformers import SentenceTransformer
            self.model = SentenceTransformer(model_name)
            self.provider = "local"
        
        elif model_name == "text-embedding-3-small":
            from langchain_openai import OpenAIEmbeddings
            self.model = OpenAIEmbeddings(model=model_name)
            self.provider = "openai"
    
    def embed(self, texts: List[str]) -> List[List[float]]:
        if self.provider == "local":
            return self.model.encode(texts, show_progress_bar=False).tolist()
        else:
            return self.model.embed_documents(texts)
```

**Configuration:**
```python
# shared/aviation_agent/config.py
class RulesRAGSettings(BaseModel):
    embedding_model: str = Field(
        default="all-MiniLM-L6-v2",
        description="Embedding model: all-MiniLM-L6-v2 or text-embedding-3-small"
    )
```

**Implementation Priority:** Phase 1 (Week 1)

---

## DECISION 5: RAG Build Timing ✅

### Final Choice: **Integrate into xls_to_rules.py**

**Implementation:**

```python
# tools/xls_to_rules.py

def main(argv: Optional[List[str]] = None) -> int:
    # ... existing argument parsing ...
    p.add_argument("--build-rag", action="store_true", default=True,
                   help="Build vector database for RAG (default: True)")
    p.add_argument("--no-rag", action="store_false", dest="build_rag",
                   help="Skip vector database build")
    p.add_argument("--embedding-model", default="all-MiniLM-L6-v2",
                   help="Embedding model for RAG (default: all-MiniLM-L6-v2)")
    
    args = p.parse_args(argv)
    
    # ... existing rules.json generation ...
    
    # Build vector DB
    if args.build_rag:
        print(f"\nBuilding vector database with {args.embedding_model}...")
        from shared.aviation_agent.rules_rag import build_vector_db
        
        vector_db_path = Path("cache/rules_vector_db")
        build_vector_db(
            rules_json_path=out_path,
            vector_db_path=vector_db_path,
            embedding_model=args.embedding_model,
        )
        print(f"✓ Vector database built at {vector_db_path}")
    
    return 0
```

**Usage:**
```bash
# Standard workflow (with RAG)
python tools/xls_to_rules.py \
    --defs data/rules_definitions.xlsx \
    --out data/rules.json \
    --add FR france_rules.xlsx \
    --add GB uk_rules.xlsx

# Quick test (skip RAG)
python tools/xls_to_rules.py --no-rag --add FR france_rules.xlsx --out test.json

# Use OpenAI embeddings
python tools/xls_to_rules.py --embedding-model text-embedding-3-small --add FR france.xlsx
```

**Implementation Priority:** Phase 1 (Week 1)

---

## DECISION 6: Clarification UX ✅

### Final Choice: **Yes, Acceptable to Ask**

When country/intent is ambiguous, the agent should ask for clarification:

**Example Interactions:**

```
User: "What are the rules?"
Agent: "I'd be happy to help! Which country's rules are you interested in? 
        For example: France (FR), Germany (DE), United Kingdom (GB)."

User: "Tell me about flying there"
Agent: "Could you clarify which country or airport you're asking about? 
        You can mention a country name, ISO code (like FR), or 
        airport ICAO code (like LFMD)."

User: "What about procedures?"
[After discussing France earlier]
Agent: [Uses context] "For France, the procedures are..."
```

**Implementation:**
```python
class NeedsClarification(BaseModel):
    """Returned when user intent is unclear."""
    message: str
    suggestions: List[str] = []
    context_hint: Optional[str] = None

# In router/extractor:
if not countries and not clear_intent:
    return NeedsClarification(
        message="Which country are you interested in?",
        suggestions=["France (FR)", "Germany (DE)", "United Kingdom (GB)"],
        context_hint="You can also mention an airport ICAO code like LFMD"
    )
```

**Implementation Priority:** Phase 2 (Week 2)

---

## DECISION 7: Performance Priority ✅

### Final Choice: **Working First, Optimize Later**

**Development Philosophy:**
1. ✅ **Phase 1-3:** Focus on correctness and functionality
2. ✅ **Phase 4:** Measure performance baselines
3. ✅ **Phase 5+:** Optimize bottlenecks if needed

**Keep Options Open:**
- Abstract embedding provider (easy to swap)
- Abstract vector DB (ChromaDB → Qdrant if needed)
- Router logic can be tuned (keyword thresholds, LLM model)
- Caching can be added later

**Don't Worry About Yet:**
- Response time optimization
- Token usage minimization
- Caching strategies
- Load balancing

**Will Measure:**
- End-to-end latency
- Token costs
- Retrieval accuracy
- User satisfaction

**Implementation Priority:** Phase 4 (Week 3-4) - Measurement only

---

## DECISION 8: MVP Scope ✅

### Final Choice: **Test Without "Both", Add Before Production**

**Testing Phase (Weeks 1-2):**
- ✅ Implement rules path only
- ✅ Implement database path only
- ✅ Router chooses one or the other
- ✅ Test basic functionality
- ✅ Validate retrieval quality

**Pre-Production Phase (Week 3):**
- ✅ Implement sequential "both" path
- ✅ Merge database results + rules answers
- ✅ Test compound queries
- ✅ Tune synthesis prompts

**Rationale:**
- Get core RAG working first
- Validate approach before complexity
- Compound queries need both paths working well
- Production quality requires answer combination

**Implementation Priority:**
- Phase 1-2: Single-path testing
- Phase 3: Sequential execution
- Phase 4: Production readiness

---

## Updated Implementation Roadmap

### Phase 1: RAG Foundation (Week 1) - 5 days

**Goal:** Working vector database and retrieval

**Tasks:**
- [x] Decision 5: Integrate RAG build into xls_to_rules.py
- [ ] Create `shared/aviation_agent/rules_rag.py`
- [ ] Implement `build_vector_db()` function
- [ ] Implement `retrieve_rules()` function
- [ ] Decision 4: Use all-MiniLM-L6-v2 for development
- [ ] Test retrieval on sample queries
- [ ] Unit tests

**Deliverables:**
- Working ChromaDB with embedded questions
- Retrieval function returning top-k matches
- Basic tests passing

**Definition of Done:**
- Can build vector DB from rules.json
- Can retrieve relevant rules for test queries
- Precision@5 > 70%

---

### Phase 2: Router & Country Extraction (Week 2) - 5 days

**Goal:** Query classification and country extraction

**Tasks:**
- [ ] Create `shared/aviation_agent/routing.py`
- [ ] Decision 1: Implement keyword pre-filter
- [ ] Implement LLM router for ambiguous queries
- [ ] Decision 3: Implement country extraction (names + ISO + ICAO)
- [ ] Decision 3: Build ICAO → ISO-2 mapping
- [ ] Decision 6: Implement clarification logic
- [ ] Test router accuracy on labeled dataset
- [ ] Unit tests

**Deliverables:**
- Router classifying queries as "rules" or "database"
- Country extractor supporting 3 formats
- Clarification prompts for ambiguous queries

**Definition of Done:**
- Router accuracy > 85% on test set
- Country extraction works for names, ISO, ICAO
- Clarification prompts are user-friendly

---

### Phase 3: Rules Agent & "Both" Path (Week 2-3) - 5 days

**Goal:** Answer synthesis and compound queries

**Tasks:**
- [ ] Create `shared/aviation_agent/rules_agent.py`
- [ ] Implement synthesis prompt
- [ ] Add citation handling
- [ ] Multi-country comparison logic
- [ ] Decision 2: Implement sequential "both" path
- [ ] Merge database + rules results
- [ ] Test compound queries
- [ ] Integration tests

**Deliverables:**
- Rules agent generating natural language answers
- Sequential execution for compound queries
- Combined answers (database + rules)

**Definition of Done:**
- Rules answers include citations
- Compound queries work end-to-end
- Multi-country comparisons are coherent

---

### Phase 4: LangGraph Integration (Week 3) - 3 days

**Goal:** Full agent integration

**Tasks:**
- [ ] Update `shared/aviation_agent/state.py`
- [ ] Modify `shared/aviation_agent/graph.py`
- [ ] Add router node
- [ ] Add rules agent node
- [ ] Add conditional routing edges
- [ ] Update formatter for rules path
- [ ] End-to-end testing
- [ ] Fix integration issues

**Deliverables:**
- Complete LangGraph with routing
- Both paths working in production agent
- Streaming support maintained

**Definition of Done:**
- Agent handles rules queries end-to-end
- Agent handles database queries end-to-end
- Agent handles compound queries end-to-end
- All existing tests still pass

---

### Phase 5: Evaluation & Tuning (Week 3-4) - 5 days

**Goal:** Production quality

**Tasks:**
- [ ] Build evaluation dataset (100+ queries)
- [ ] Measure retrieval precision/recall
- [ ] Measure router accuracy
- [ ] Decision 4: Evaluate OpenAI embeddings vs local
- [ ] Tune similarity thresholds
- [ ] Tune router keyword weights
- [ ] Benchmark performance
- [ ] Fix quality issues
- [ ] Decision 7: Identify optimization opportunities (but don't implement)

**Deliverables:**
- Evaluation metrics report
- Tuned hyperparameters
- Performance baseline
- Quality assessment

**Definition of Done:**
- Retrieval Precision@5 > 80%
- Router Accuracy > 90%
- Response time < 3s (p95)
- Quality review passed

---

### Phase 6: Production Readiness (Week 4) - 3 days

**Goal:** Deploy to production

**Tasks:**
- [ ] Add logging/monitoring
- [ ] Error handling for all edge cases
- [ ] Graceful degradation (RAG fails → fallback)
- [ ] Documentation (user-facing & developer)
- [ ] Deployment guide
- [ ] Production configuration
- [ ] Smoke tests on production

**Deliverables:**
- Production-ready code
- Monitoring dashboard
- Documentation
- Deployment runbook

**Definition of Done:**
- All error cases handled gracefully
- Monitoring in place
- Documentation complete
- Deployed to production successfully

---

## Success Criteria (Revisited)

| Metric | Target | Measurement | Priority |
|--------|--------|-------------|----------|
| **Retrieval Precision@5** | >80% | Manual eval | HIGH |
| **Router Accuracy** | >90% | Labeled dataset | HIGH |
| **Answer Quality** | >85% thumbs up | User feedback | HIGH |
| **Response Time** | <3s (p95) | Production metrics | MEDIUM |
| **Compound Query Success** | >85% | Test set | HIGH |
| **Country Extraction Accuracy** | >95% | Test cases | HIGH |

---

## Risk Mitigation (Updated)

### High Risk Items
1. **Router Accuracy < 90%**
   - Mitigation: Extensive keyword list, tune LLM prompt, add examples
   
2. **Country Extraction Fails on ICAO Codes**
   - Mitigation: Comprehensive ICAO→ISO mapping, fallback to ask user

3. **"Both" Path Synthesis Poor Quality**
   - Mitigation: Iterate on synthesis prompt, show database results clearly

### Medium Risk Items
4. **Performance Regression**
   - Mitigation: Keep it in mind, but don't over-optimize early
   
5. **RAG Retrieval Quality < 80%**
   - Mitigation: Tune top-k, try OpenAI embeddings, adjust filters

---

## Next Steps (Immediate)

### This Week (Days 1-2)
1. ✅ **Document decisions** (this file) - DONE
2. [ ] **Set up development branch** (`feature/rules-rag`)
3. [ ] **Create Phase 1 tasks** in project management tool
4. [ ] **Start implementing** `rules_rag.py` module
5. [ ] **Build vector DB** for first time with sample data

### Next Week (Days 3-7)
6. [ ] Complete Phase 1 (RAG foundation)
7. [ ] Start Phase 2 (Router + Country extraction)
8. [ ] Build test dataset (50 queries for initial testing)

### Week 3 (Days 8-14)
9. [ ] Complete Phase 2 & 3
10. [ ] Start LangGraph integration
11. [ ] Test compound queries

### Week 4 (Days 15-21)
12. [ ] Complete Phase 4-6
13. [ ] Production deployment
14. [ ] Monitor and iterate

---

## Configuration Summary

### Environment Variables
```bash
# Development
RULES_JSON=data/rules.json
VECTOR_DB_PATH=cache/rules_vector_db
EMBEDDING_MODEL=all-MiniLM-L6-v2
ROUTER_MODEL=gpt-4o-mini
RULES_AGENT_MODEL=gpt-4o

# Production (consider)
EMBEDDING_MODEL=text-embedding-3-small  # If evaluation shows benefit
```

### Dependencies to Add
```
# requirements.txt
chromadb>=0.4.22
sentence-transformers>=2.2.0
```

---

## Questions & Clarifications Addressed

✅ All key decisions made  
✅ Implementation plan clear  
✅ Priorities established  
✅ Success criteria defined  

**Ready to begin implementation!**

---

**Approved By:** User  
**Approval Date:** 2025-12-02  
**Implementation Start:** 2025-12-02  
**Expected Completion:** ~4 weeks (2025-12-30)

