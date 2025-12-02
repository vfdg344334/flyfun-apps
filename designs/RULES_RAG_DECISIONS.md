# Rules RAG Enhancement - Key Decisions & Discussion Guide

**Date:** 2025-12-02  
**Purpose:** This document focuses on the critical decisions needed before implementation begins.

---

## Decision Summary Table

| # | Decision | Options | Recommended | Priority | Status |
|---|----------|---------|-------------|----------|--------|
| 1 | Router Complexity | All queries / Keyword filter / No router | Keyword + LLM | HIGH | 🔴 Needs decision |
| 2 | "Both" Path Handling | Sequential / Parallel / Database-only / Not supported | Database-only MVP | MEDIUM | 🔴 Needs decision |
| 3 | Country Extraction | Strict / Expand regions / Ask user / Use context | Context + Ask | HIGH | 🔴 Needs decision |
| 4 | RAG Indexing | Question only / Question+Answer | Question only | LOW | ✅ Can defer |
| 5 | Embedding Model | Local / OpenAI small / OpenAI large | Local MVP | MEDIUM | 🔴 Needs decision |
| 6 | Vector DB Choice | ChromaDB / Qdrant / FAISS | ChromaDB | LOW | ✅ Recommended |
| 7 | RAG Build Timing | During xls_to_rules / On-demand / Separate script | During xls_to_rules | MEDIUM | 🔴 Needs decision |
| 8 | Fallback Strategy | No results → broaden / Return "don't know" / Use string match | Broaden then "don't know" | LOW | ✅ Can defer |

---

## DECISION 1: Router Complexity ⚡ HIGH PRIORITY

### The Question
**Should we route ALL queries through the router, or use a fast keyword pre-filter?**

### Context
Every query adds ~200ms latency for router LLM call. We process ~1000 queries/day.

### Options

#### Option A: Route ALL Queries Through LLM Router
```python
def handle_query(query):
    router_decision = router_llm.classify(query)  # Always call
    if router_decision.path == "rules":
        return rules_agent(query)
    else:
        return database_agent(query)
```

**Pros:**
- ✅ Consistent behavior
- ✅ Highest accuracy for ambiguous queries
- ✅ Learns from conversation context

**Cons:**
- ❌ 200ms latency added to EVERY query
- ❌ Higher costs (~$0.0001/query × 1000/day = $3/month)
- ❌ Overkill for obvious queries

#### Option B: Keyword Pre-Filter + LLM for Ambiguous (RECOMMENDED)
```python
RULES_KEYWORDS = ["rules", "regulations", "allowed", "required", "customs", "PPR", "IFR", "VFR"]
DATABASE_KEYWORDS = ["find", "near", "airports with", "route", "between"]

def handle_query(query):
    # Fast keyword check
    if has_keywords(query, RULES_KEYWORDS):
        return rules_agent(query)
    elif has_keywords(query, DATABASE_KEYWORDS):
        return database_agent(query)
    else:
        # Ambiguous - use router
        router_decision = router_llm.classify(query)
        return route_based_on(router_decision)
```

**Pros:**
- ✅ Fast path for ~80% of queries (no LLM call)
- ✅ Lower costs
- ✅ LLM only for genuinely ambiguous queries

**Cons:**
- ❌ Keywords might miss edge cases
- ❌ Need to maintain keyword list
- ❌ Slightly more complex logic

#### Option C: No Dedicated Router (Add RAG as Tool)
```python
# Add to existing planner tools:
{
    "name": "query_rules_rag",
    "description": "Search aviation rules using natural language",
    ...
}
```

**Pros:**
- ✅ Simplest integration
- ✅ Reuse existing planner
- ✅ Can combine with other tools

**Cons:**
- ❌ Planner may struggle to learn when to use RAG
- ❌ No explicit country extraction
- ❌ All tools shown in every query (token overhead)

### Recommendation: **Option B** - Keyword Pre-Filter + LLM

**Reasoning:**
- 80/20 rule: Most queries are clearly one type or the other
- Optimize for common case (fast path)
- LLM available for truly ambiguous queries
- Cost-effective

**Implementation:**
```python
class SmartRouter:
    def route(self, query: str, context: List[Message]) -> RouterDecision:
        # Fast keyword check
        rules_score = keyword_match_score(query, RULES_KEYWORDS)
        db_score = keyword_match_score(query, DATABASE_KEYWORDS)
        
        if rules_score > 2:  # Strong rules signal
            return RouterDecision(path="rules", confidence=0.9)
        elif db_score > 2:  # Strong database signal
            return RouterDecision(path="database", confidence=0.9)
        else:
            # Ambiguous - use LLM
            return self.llm_classify(query, context)
```

### Action Items:
- [ ] Define comprehensive keyword lists
- [ ] Set confidence thresholds
- [ ] Log ambiguous queries for tuning

---

## DECISION 2: Handling "Both" Queries 🔀 MEDIUM PRIORITY

### The Question
**How should we handle queries that need both database search AND rules information?**

### Example Query
> "Find customs airports in France with AVGAS and tell me about customs procedures"

This needs:
1. Database query: Airports in France with customs=True AND has_avgas=True
2. Rules query: Customs procedures in France

### Options

#### Option A: Sequential Execution (Database → Rules)
```python
# 1. Execute database query
airports = find_airports(filters={
    "country": "FR",
    "has_avgas": True,
    "point_of_entry": True
})

# 2. Pass results to rules agent
rules_context = retrieve_rules(query="customs procedures", countries=["FR"])

# 3. Synthesize combined answer
answer = format_with_both(airports, rules_context)
```

**Pros:**
- ✅ Can reference specific airports in rules explanation
- ✅ Complete answer to compound query
- ✅ Good user experience

**Cons:**
- ❌ More complex orchestration
- ❌ Slower (sequential execution)
- ❌ Need to merge results intelligently

#### Option B: Parallel Execution
```python
# Run both paths simultaneously
airports_future = async find_airports(...)
rules_future = async retrieve_rules(...)

airports = await airports_future
rules = await rules_future

answer = merge_results(airports, rules)
```

**Pros:**
- ✅ Faster than sequential
- ✅ Complete answer

**Cons:**
- ❌ Complex merging logic
- ❌ Requires async infrastructure
- ❌ May produce disjointed answers

#### Option C: Database-Only (MVP) (RECOMMENDED)
```python
# Router chooses primary intent
if "find" in query or "airports" in query:
    # Database path only
    # Trust that point_of_entry filter is sufficient
    return find_airports(filters={"point_of_entry": True})
else:
    # Rules path only
    return rules_agent(query)
```

**Pros:**
- ✅ Simple to implement
- ✅ Works for MVP
- ✅ Database metadata (point_of_entry flag) provides basic info

**Cons:**
- ❌ Doesn't answer compound questions fully
- ❌ User might need to ask follow-up
- ❌ Less sophisticated

#### Option D: Refuse to Handle Both
```python
if router_decision.path == "both":
    return (
        "Your question combines airport search and regulations. "
        "Please ask separately:\n"
        "1. 'Find customs airports in France with AVGAS'\n"
        "2. 'What are customs procedures in France?'"
    )
```

**Pros:**
- ✅ Simplest implementation
- ✅ Explicit about capabilities

**Cons:**
- ❌ Poor user experience
- ❌ Requires user to rephrase

### Recommendation: **Option C for MVP, Option A for Future**

**MVP (Phase 1):**
- Router chooses primary intent (database OR rules)
- Database path trusts metadata flags
- User can ask follow-up if needed

**Future Enhancement (Phase 2):**
- Implement sequential execution
- Rules agent receives database results as context
- Synthesize combined answer

**Why:**
- Get core functionality working first
- Compound queries are <10% of total
- Can add orchestration layer later

### Action Items:
- [ ] Track frequency of "both" queries in logs
- [ ] Design merge strategy for Phase 2
- [ ] Add "Follow-up suggestion" to responses

---

## DECISION 3: Country Extraction 🌍 HIGH PRIORITY

### The Question
**How should we handle ambiguous or complex country references?**

### Problem Cases

| User Input | Challenge | Possible Interpretation |
|------------|-----------|------------------------|
| "Europe" | Which countries? | All EU? Schengen? All geographic? |
| "Germany and neighbors" | Which neighbors? | All 9? Just bordering? |
| "Flying in Schengen" | Many countries | 27 Schengen countries |
| No country mentioned | Default? | User's location? Previous context? |
| "UK" vs "GB" | Code ambiguity | ISO-2: GB, but user says UK |

### Options

#### Option A: Strict - Require Explicit Codes
```python
def extract_countries(query: str) -> List[str]:
    # Only accept explicit ISO-2 codes or unambiguous names
    if "France" in query:
        return ["FR"]
    elif "Germany" in query:
        return ["DE"]
    else:
        raise ValueError("Please specify a country explicitly")
```

**Pros:**
- ✅ No ambiguity
- ✅ Simple logic

**Cons:**
- ❌ Poor user experience (forced to be explicit)
- ❌ Can't handle "Europe" queries
- ❌ Requires error handling and rephrasing

#### Option B: Expand Regions to Country Lists
```python
REGION_MAPPING = {
    "europe": ["FR", "DE", "GB", "IT", "ES", ...],  # All European countries
    "schengen": ["FR", "DE", "IT", "ES", ...],      # Schengen area
    "eu": ["FR", "DE", "IT", ...],                   # EU members
    "baltic": ["EE", "LV", "LT"],                    # Baltic states
}

def extract_countries(query: str) -> List[str]:
    if "europe" in query.lower():
        return REGION_MAPPING["europe"]
    ...
```

**Pros:**
- ✅ Handles "Europe" queries naturally
- ✅ Can answer broad questions

**Cons:**
- ❌ "Europe" → 40+ countries → large result set
- ❌ Need to maintain region mappings
- ❌ What about "Germany and neighbors"? (complex logic)

#### Option C: Ask User for Clarification
```python
def extract_countries(query: str) -> List[str] | NeedsClarification:
    if "europe" in query.lower():
        return NeedsClarification(
            message="Which European countries are you interested in?",
            suggestions=["France", "Germany", "UK", "All Schengen countries"]
        )
```

**Pros:**
- ✅ No guessing - get user intent explicitly
- ✅ Educational (user learns to be specific)

**Cons:**
- ❌ Extra interaction round-trip
- ❌ Slows down conversation
- ❌ Frustrating for obvious cases

#### Option D: Use Conversation Context (RECOMMENDED)
```python
def extract_countries(query: str, conversation: List[Message]) -> List[str]:
    # Try to extract from current query
    countries = explicit_extraction(query)
    
    if countries:
        return countries
    
    # Check conversation history
    for prev_message in reversed(conversation[-5:]):  # Last 5 messages
        prev_countries = explicit_extraction(prev_message.content)
        if prev_countries:
            return prev_countries
    
    # Still ambiguous - ask
    return NeedsClarification(...)
```

**Pros:**
- ✅ Natural conversation flow
- ✅ Handles follow-ups: "What about Germany?" after discussing France
- ✅ Falls back to asking if truly unclear

**Cons:**
- ❌ More complex state tracking
- ❌ Might carry over wrong context
- ❌ Need to handle context expiration

### Recommendation: **Option D** - Use Context + Ask

**Implementation Strategy:**
1. **First Pass:** Extract from current query using NER + keyword matching
2. **Second Pass:** Check last 3-5 messages for country mentions
3. **Expansion:** Support common regions (Europe → ask which countries)
4. **Fallback:** If ambiguous, ask user with suggestions

**Country Name Handling:**
```python
COUNTRY_ALIASES = {
    "UK": "GB",
    "United Kingdom": "GB",
    "England": "GB",
    "Britain": "GB",
    "Netherlands": "NL",
    "Holland": "NL",
    "Switzerland": "CH",
    "Swiss": "CH",
    ...
}
```

### Action Items:
- [ ] Build comprehensive country alias map
- [ ] Define region expansions (Europe, Schengen, EU)
- [ ] Set context window (recommend: 5 messages)
- [ ] Design clarification prompts

---

## DECISION 4: Embedding Model 🤖 MEDIUM PRIORITY

### The Question
**Which embedding model should we use for RAG retrieval?**

### Options Comparison

| Model | Provider | Dims | Cost | Quality | Latency | Local? |
|-------|----------|------|------|---------|---------|--------|
| **all-MiniLM-L6-v2** | HuggingFace | 384 | Free | Good | ~10ms | ✅ |
| **all-mpnet-base-v2** | HuggingFace | 768 | Free | Better | ~20ms | ✅ |
| **text-embedding-3-small** | OpenAI | 1536 | $0.02/1M | Excellent | ~100ms | ❌ |
| **text-embedding-3-large** | OpenAI | 3072 | $0.13/1M | Best | ~150ms | ❌ |
| **voyage-2** | Voyage AI | 1024 | $0.10/1M | Excellent | ~100ms | ❌ |

### Cost Analysis (Based on 500 questions × 5 countries = 2,500 docs)

**One-time indexing cost:**
- Local model: $0 (runs on CPU/GPU)
- OpenAI small: ~$0.05 (2,500 docs × 50 tokens × $0.02/1M)
- OpenAI large: ~$0.33

**Query cost (1000 queries/day):**
- Local model: $0
- OpenAI small: ~$0.60/month (1000 × 30 × 20 tokens × $0.02/1M)
- OpenAI large: ~$3.90/month

### Quality Comparison (Estimated on Aviation Queries)

| Model | Precision@5 | Recall@10 | Speed |
|-------|-------------|-----------|-------|
| all-MiniLM-L6-v2 | 75% | 85% | ⚡⚡⚡ |
| all-mpnet-base-v2 | 78% | 87% | ⚡⚡ |
| text-embedding-3-small | 82% | 90% | ⚡ |
| text-embedding-3-large | 85% | 92% | ⚡ |

### Recommendation: **Hybrid Approach**

**Development & MVP:**
- Use **all-MiniLM-L6-v2** (local)
- Rationale:
  - Fast iteration (no API calls)
  - Free
  - Good enough for validation
  - Can run offline

**Production (After MVP Validation):**
- Upgrade to **text-embedding-3-small**
- Rationale:
  - Better quality for $0.60/month (negligible)
  - More consistent results
  - Better semantic understanding

**Implementation:**
```python
class EmbeddingProvider:
    def __init__(self, model_name: str):
        if model_name == "all-MiniLM-L6-v2":
            self.model = SentenceTransformer(model_name)
            self.provider = "local"
        elif model_name == "text-embedding-3-small":
            self.model = OpenAIEmbeddings(model=model_name)
            self.provider = "openai"
    
    def embed(self, texts: List[str]) -> List[List[float]]:
        if self.provider == "local":
            return self.model.encode(texts).tolist()
        else:
            return self.model.embed_documents(texts)
```

### Action Items:
- [ ] Start with all-MiniLM-L6-v2
- [ ] Build evaluation dataset
- [ ] Compare local vs. OpenAI quality on real queries
- [ ] Decision point: Keep local or upgrade?

---

## DECISION 5: RAG Database Build Timing 🏗️ MEDIUM PRIORITY

### The Question
**When and how should we build the vector database?**

### Options

#### Option A: Integrated into xls_to_rules.py (RECOMMENDED)
```python
# tools/xls_to_rules.py
def main():
    # 1. Convert Excel → rules.json
    rules_data = convert_excel_to_rules(...)
    save_rules_json(rules_data)
    
    # 2. Build vector DB
    print("Building vector database...")
    build_vector_db(
        rules_json_path="rules.json",
        output_path="cache/rules_vector_db"
    )
    print("Done!")
```

**Pros:**
- ✅ Single workflow for rule updates
- ✅ Vector DB always in sync with rules.json
- ✅ No manual steps

**Cons:**
- ❌ Adds ~30s to xls_to_rules.py runtime
- ❌ Requires embedding model installed

#### Option B: On-Demand (First Startup)
```python
# shared/aviation_agent/rules_rag.py
class RulesRAG:
    def __init__(self, ...):
        if not vector_db_exists():
            print("Building vector DB (one-time setup)...")
            build_from_rules_json()
```

**Pros:**
- ✅ No change to xls_to_rules.py
- ✅ Lazy initialization

**Cons:**
- ❌ Slow first startup (~60s)
- ❌ Might rebuild unnecessarily if cache cleared
- ❌ Harder to debug build issues

#### Option C: Separate Script
```bash
# Manual workflow:
$ python tools/xls_to_rules.py --out rules.json ...
$ python tools/build_rules_rag.py --input rules.json --output cache/rules_vector_db
```

**Pros:**
- ✅ Clear separation of concerns
- ✅ Can rebuild without regenerating rules.json

**Cons:**
- ❌ Manual step (easy to forget)
- ❌ Risk of rules.json and vector DB out of sync

### Recommendation: **Option A** - Integrated

**Rationale:**
- One workflow = less error-prone
- 30s build time is acceptable (not in hot path)
- Clear that vector DB is regenerated

**Implementation:**
```python
# tools/xls_to_rules.py
def main():
    # ... existing logic ...
    
    # Build vector DB
    if args.build_rag:  # Optional flag
        from shared.aviation_agent.rules_rag import build_vector_db
        build_vector_db(
            rules_json_path=out_path,
            vector_db_path=Path("cache/rules_vector_db"),
            embedding_model=args.embedding_model or "all-MiniLM-L6-v2"
        )
    
    return 0
```

**Usage:**
```bash
# With RAG build (default for production)
$ python tools/xls_to_rules.py --defs definitions.xlsx --add FR france.xlsx --build-rag

# Skip RAG build (for quick testing)
$ python tools/xls_to_rules.py --defs definitions.xlsx --add FR france.xlsx --no-rag
```

### Action Items:
- [ ] Add --build-rag / --no-rag flags to xls_to_rules.py
- [ ] Add build_vector_db() function to rules_rag.py
- [ ] Update tool documentation

---

## Implementation Priority Order

Based on decisions above, recommended implementation order:

### Sprint 1: Foundation (Week 1)
1. **DECISION 6** ✅ Vector DB: Use ChromaDB
2. **DECISION 5** Build integration: Add to xls_to_rules.py
3. **DECISION 4** Embedding: Start with all-MiniLM-L6-v2
4. **Task:** Build rules_rag.py module with retrieval functions

### Sprint 2: Router (Week 2)
5. **DECISION 1** Router: Keyword filter + LLM for ambiguous
6. **DECISION 3** Country extraction: Context-aware with fallback
7. **Task:** Build routing.py module

### Sprint 3: Agent (Week 2-3)
8. **DECISION 2** "Both" handling: Database-only for MVP
9. **Task:** Build rules_agent.py synthesis module
10. **Task:** Integrate into LangGraph

### Sprint 4: Polish (Week 3-4)
11. **DECISION 8** Fallback: Broaden search, then "don't know"
12. **Task:** Testing & tuning
13. **Task:** Documentation

---

## Questions for Stakeholder Review

1. **User Experience:**
   - Is it acceptable to ask users for clarification when country is ambiguous?
   - Should we support "Europe" queries (all countries) or suggest being specific?

2. **Performance:**
   - Is 200ms extra latency for routing acceptable?
   - Should we optimize for speed or accuracy?

3. **Scope:**
   - Should MVP handle compound queries (database + rules) or defer to Phase 2?
   - Are there specific query patterns we must support in MVP?

4. **Costs:**
   - Budget for embeddings: Stay local (free) or use OpenAI (~$1/month)?
   - Budget for router LLM calls: ~$3/month for all queries

5. **Quality:**
   - What's acceptable accuracy for router? (90%? 95%?)
   - What's acceptable retrieval precision? (80%? 85%?)

---

## Next Steps

1. **Review & Decide** on open decisions (1, 2, 3, 5, 7)
2. **Build Prototype** for RAG module (Sprint 1)
3. **Test Retrieval Quality** with sample queries
4. **Iterate** based on results
5. **Full Integration** (Sprints 2-4)

---

**Please provide feedback on:**
- Which decisions need discussion?
- Any concerns with recommendations?
- Priority changes?
- Additional considerations?

