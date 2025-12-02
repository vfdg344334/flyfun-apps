# Rules RAG Agent Design

**Version:** 1.0  
**Date:** 2025-12-02  
**Status:** Draft for Review

## Executive Summary

This document proposes enhancing the aviation agent with a RAG (Retrieval-Augmented Generation) system for aviation rules queries. The enhancement includes:
1. A router agent to classify queries as rules-based vs. database queries
2. A RAG-powered rules retrieval system using embeddings
3. A specialized rules agent to synthesize answers from retrieved rules
4. Integration with the existing xls_to_rules.py workflow

---

## 1. Current State Analysis

### 1.1 Current Architecture

The aviation agent currently uses a **single-path architecture**:

```
User Query → Planner → Tool Selection → Tool Execution → Formatter → Response
```

**Current Rules Handling:**
- Rules are stored in `rules.json` with structure:
  ```json
  {
    "questions": [
      {
        "question_id": "customs-poe",
        "question_text": "Do I need to land at a point of entry?",
        "question_raw": "...",
        "question_prefix": "...",
        "category": "Customs/Schengen",
        "tags": ["customs", "border"],
        "answers_by_country": {
          "FR": {
            "answer_html": "...",
            "links": ["..."],
            "last_reviewed": "2025-12-02",
            "confidence": "high"
          }
        }
      }
    ]
  }
  ```

- RulesManager (`shared/rules_manager.py`) provides:
  - In-memory indexing by country, category, tags
  - Filtering and search by string matching
  - Country-to-country comparison

- Aviation agent exposes two rule tools:
  - `list_rules_for_country(country_code, category?, tags?)`
  - `compare_rules_between_countries(country1, country2, category?)`

### 1.2 Current Limitations

1. **Poor Semantic Matching**: String-based search doesn't capture semantic similarity
   - "Where do I clear customs?" vs "Do I need to land at POE?" are semantically similar but don't match
   
2. **Inefficient Retrieval**: Returns all rules for a country then filters
   - May return 50+ rules when only 2-3 are relevant
   
3. **No Cross-Country Synthesis**: Can't answer "What are customs requirements across Europe?"
   
4. **Planner Confusion**: Single planner struggles to decide between:
   - "Find airports in France" (database query)
   - "What are France's flight plan rules?" (rules query)
   
5. **Context Overload**: Formatter receives too much irrelevant rule content

---

## 2. Problem Statement

**Goal:** Improve rules query handling through:
- Semantic understanding of pilot questions
- Efficient retrieval of only relevant rules
- Country-aware context injection
- Clear separation between rules and database queries

---

## 3. Proposed Architecture

### 3.1 High-Level Flow

```
User Query
    ↓
┌─────────────────┐
│ Router Agent    │ → Classifies query type + extracts countries
└─────────────────┘
    ↓           ↓
    Rules      Database
    Path        Path
    ↓           ↓
┌──────────────┐  ┌──────────────────┐
│ Rules Agent  │  │ Current Planner  │
│ (RAG)        │  │ (Tool Selection) │
└──────────────┘  └──────────────────┘
    ↓                    ↓
┌──────────────┐  ┌──────────────────┐
│ Vector DB    │  │ Tool Execution   │
│ Retrieval    │  │                  │
└──────────────┘  └──────────────────┘
    ↓                    ↓
┌──────────────┐  ┌──────────────────┐
│ LLM Synthesis│  │ Formatter        │
└──────────────┘  └──────────────────┘
    ↓                    ↓
    Final Answer
```

### 3.2 Component Breakdown

#### **A. Router Agent** (New)

**Responsibility:** Classify incoming queries and extract context

**Input:** User message(s)  
**Output:** 
```python
class RouterDecision(BaseModel):
    path: Literal["rules", "database", "both"]
    confidence: float  # 0.0 - 1.0
    countries: List[str]  # Extracted ISO-2 codes ["FR", "GB"]
    reasoning: str
```

**Classification Logic:**
- **Rules Path Triggers:**
  - Questions about regulations, requirements, procedures
  - Keywords: "rules", "regulations", "allowed", "required", "customs", "flight plan", "IFR", "VFR"
  - Examples: "Do I need PPR in France?", "What are IFR rules in Germany?"
  
- **Database Path Triggers:**
  - Questions about specific airports, locations, facilities
  - Keywords: "find", "near", "between", "airports with", "runway", "AVGAS"
  - Examples: "Airports near Paris", "Find customs airports in France"
  
- **Both Path:**
  - Compound queries requiring both database and rules
  - Example: "Find IFR airports in France" (database + rules validation)

**Implementation Options:**
1. **LLM-based classifier** (Recommended)
   - Use structured output (Pydantic model)
   - Can handle nuanced language
   - Extracts countries via NER
   
2. **Hybrid: ML classifier + keyword matching**
   - Fast keyword pre-filter
   - LLM for ambiguous cases
   
3. **Embeddings similarity**
   - Compare query embedding to labeled examples
   - Less flexible but faster

#### **B. Rules RAG System** (New)

**Components:**

1. **Vector Database:**
   - Store embeddings of all questions from rules.json
   - Metadata per vector:
     ```python
     {
       "question_id": "customs-poe",
       "question_text": "Do I need to land at a point of entry?",
       "country_code": "FR",
       "category": "Customs/Schengen",
       "tags": ["customs", "border"],
       "answer_html": "...",
       "links": [...]
     }
     ```
   
2. **Indexing Structure:**
   ```
   Collections:
     - rules_global: All questions (for cross-country queries)
     - rules_by_country: Separate collection per country (optional optimization)
   
   Filters:
     - country_code (for country-specific queries)
     - category (for topic filtering)
   ```

3. **Retrieval Strategy:**
   ```python
   def retrieve_rules(
       query: str,
       countries: List[str],
       top_k: int = 5,
       category: Optional[str] = None
   ) -> List[RuleDoc]:
       # Embed query
       query_embedding = embed_text(query)
       
       # Search with filters
       results = vector_db.search(
           embedding=query_embedding,
           filters={"country_code": {"$in": countries}},
           limit=top_k * len(countries)
       )
       
       return results
   ```

#### **C. Rules Agent** (New)

**Responsibility:** Synthesize answer from retrieved rules

**Input:**
- User query
- Retrieved rule documents (from RAG)
- Conversation history

**Output:**
- Natural language answer with citations
- Source links
- Multi-country comparison if applicable

**Prompt Structure:**
```
You are an aviation regulations expert. Answer the pilot's question using ONLY the provided rules.

Countries in scope: {countries}

Retrieved Rules:
{retrieved_rules}

User Question: {query}

Instructions:
- Cite specific countries when stating rules
- If rules differ between countries, highlight differences
- Include reference links
- If no rules found, say "I don't have information about..."
```

#### **D. Database Path** (Existing)

Keep current planner → tool → formatter flow unchanged

---

## 4. Implementation Options

### 4.1 Vector Database Choices

| Option | Pros | Cons | Recommendation |
|--------|------|------|----------------|
| **ChromaDB** | - Easy setup<br>- Local-first<br>- Good Python API | - Less mature<br>- Limited scale | ✅ **Best for MVP** |
| **Qdrant** | - High performance<br>- Good filtering<br>- Cloud + local | - More complex setup | Good for production |
| **FAISS** | - Fast<br>- No dependencies | - No metadata filtering<br>- Manual persistence | Not recommended |
| **Pinecone** | - Managed service<br>- Scalable | - Costs<br>- External dependency | Overkill for now |

**Recommendation:** Start with **ChromaDB** for simplicity, migrate to Qdrant if needed

### 4.2 Embedding Model Choices

| Model | Dimensions | Performance | Cost |
|-------|-----------|-------------|------|
| **text-embedding-3-small** (OpenAI) | 1536 | Excellent | ~$0.02/1M tokens |
| **text-embedding-3-large** (OpenAI) | 3072 | Best | ~$0.13/1M tokens |
| **voyage-2** (Voyage AI) | 1024 | Excellent | ~$0.10/1M tokens |
| **all-MiniLM-L6-v2** (local) | 384 | Good | Free |

**Recommendation:** 
- **Development:** all-MiniLM-L6-v2 (local, fast iteration)
- **Production:** text-embedding-3-small (good balance)

### 4.3 RAG Database Build Strategy

**Option 1: Build during xls_to_rules.py** (Recommended)
```python
# tools/xls_to_rules.py
def build_vector_db(rules_json_path: Path, output_db_path: Path):
    """Build ChromaDB from rules.json"""
    rules = load_rules_json(rules_json_path)
    
    # Initialize ChromaDB
    client = chromadb.PersistentClient(path=str(output_db_path))
    collection = client.get_or_create_collection("aviation_rules")
    
    # Process each question for each country
    for question in rules["questions"]:
        question_text = question["question_text"]
        for country_code, answer in question["answers_by_country"].items():
            collection.add(
                documents=[question_text],
                metadatas=[{
                    "question_id": question["question_id"],
                    "country_code": country_code,
                    "category": question["category"],
                    "tags": json.dumps(question["tags"]),
                    "answer_html": answer["answer_html"],
                    "links": json.dumps(answer.get("links", [])),
                    "last_reviewed": answer.get("last_reviewed", ""),
                }],
                ids=[f"{question['question_id']}_{country_code}"]
            )
```

**Option 2: On-demand build**
- Build vector DB on first agent startup
- Cache in `cache/rules_vector_db/`
- Rebuild when rules.json changes (check mtime)

**Option 3: Separate build script**
- New script: `tools/build_rules_rag.py`
- Run manually after xls_to_rules.py

**Recommendation:** Option 1 - integrate into xls_to_rules.py

### 4.4 Router Agent Implementation

**Option A: Separate LLM call** (Recommended)
```python
class QueryRouter:
    def route(self, messages: List[BaseMessage]) -> RouterDecision:
        llm = ChatOpenAI(model="gpt-4o-mini")  # Fast + cheap
        structured_llm = llm.with_structured_output(RouterDecision)
        
        prompt = ChatPromptTemplate.from_messages([
            ("system", ROUTER_SYSTEM_PROMPT),
            MessagesPlaceholder("messages"),
        ])
        
        chain = prompt | structured_llm
        return chain.invoke({"messages": messages})
```

**Option B: Embedding-based classification**
```python
def route_by_similarity(query: str) -> Literal["rules", "database"]:
    examples = {
        "rules": ["What are customs rules?", "Do I need PPR?"],
        "database": ["Find airports near X", "Airports with AVGAS"]
    }
    
    # Compute similarity to examples
    # Return path with highest similarity
```

**Option C: Keywords only** (Fast but brittle)
```python
RULES_KEYWORDS = ["rules", "regulations", "allowed", "required", ...]
DATABASE_KEYWORDS = ["find", "near", "airports with", ...]
```

**Recommendation:** Option A with Option C as fast pre-filter

---

## 5. Integration with LangGraph

### 5.1 Revised Graph Structure

```python
from langgraph.graph import StateGraph, END

class EnhancedAgentState(TypedDict):
    messages: List[BaseMessage]
    router_decision: Optional[RouterDecision]
    
    # Rules path
    retrieved_rules: Optional[List[Dict]]
    rules_answer: Optional[str]
    
    # Database path
    plan: Optional[AviationPlan]
    tool_result: Optional[Dict]
    
    # Common
    final_answer: str
    thinking: str
    ui_payload: Optional[Dict]
    error: Optional[str]

def build_enhanced_graph():
    graph = StateGraph(EnhancedAgentState)
    
    # Add nodes
    graph.add_node("router", router_node)
    graph.add_node("rules_agent", rules_agent_node)
    graph.add_node("database_planner", planner_node)
    graph.add_node("database_tool", tool_node)
    graph.add_node("formatter", formatter_node)
    
    # Add edges
    graph.set_entry_point("router")
    
    def route_decision(state):
        decision = state["router_decision"]
        if decision.path == "rules":
            return "rules_agent"
        elif decision.path == "database":
            return "database_planner"
        else:  # both
            return "database_planner"  # Can extend for parallel execution
    
    graph.add_conditional_edges(
        "router",
        route_decision,
        {
            "rules_agent": "rules_agent",
            "database_planner": "database_planner",
        }
    )
    
    graph.add_edge("rules_agent", END)
    graph.add_edge("database_planner", "database_tool")
    graph.add_edge("database_tool", "formatter")
    graph.add_edge("formatter", END)
    
    return graph.compile()
```

### 5.2 Alternative: Keep Simple Routing

For MVP, could use simpler approach:
```python
def enhanced_planner_node(state):
    # Quick classification
    if is_rules_query(state["messages"]):
        return {
            "path": "rules",
            "plan": AviationPlan(
                selected_tool="query_rules_rag",
                arguments={"query": state["messages"][-1].content}
            )
        }
    else:
        # Use existing planner
        return existing_planner(state)
```

---

## 6. Pros and Cons Analysis

### 6.1 Proposed RAG Approach

**Pros:**
✅ **Better Semantic Matching:** "Where do I clear customs?" matches "Point of entry requirements"  
✅ **Efficient Retrieval:** Only retrieve top-k most relevant rules (5-10 instead of 50+)  
✅ **Multi-Country Queries:** Can answer "Customs rules across Europe" by retrieving from multiple countries  
✅ **Reduced Formatter Load:** Formatter receives pre-filtered, relevant context  
✅ **Clear Separation:** Distinct paths for rules vs. database queries  
✅ **Scalability:** Can add more countries/questions without degrading performance  

**Cons:**
❌ **Complexity:** More components (vector DB, embeddings, router)  
❌ **Build Time:** RAG database build adds time to xls_to_rules.py  
❌ **Dependencies:** New dependencies (chromadb, sentence-transformers)  
❌ **Embedding Costs:** If using OpenAI embeddings (~$0.02/1M tokens, but one-time)  
❌ **Storage:** Vector DB adds ~10-50MB (depending on number of rules)  
❌ **Maintenance:** Vector DB needs rebuild when rules change  

### 6.2 Alternative: Enhanced String Matching

**Approach:** Improve current RulesManager with better NLP
- Use spaCy for entity extraction (countries)
- TF-IDF or BM25 for better keyword matching
- Synonym expansion

**Pros:**
✅ Simpler implementation  
✅ No vector DB dependency  
✅ Faster query time  

**Cons:**
❌ Still misses semantic similarity  
❌ Difficult to tune for diverse queries  
❌ Can't handle paraphrases well  

### 6.3 Alternative: LLM-Only (No RAG)

**Approach:** Pass all rules for country to LLM, let it filter

**Pros:**
✅ Simplest implementation  
✅ No retrieval system needed  

**Cons:**
❌ High token costs (50+ rules * 200 tokens = 10K tokens per query)  
❌ Context window limits  
❌ Slower response time  
❌ Doesn't scale beyond ~100 rules  

---

## 7. Technical Specifications

### 7.1 File Structure

```
shared/
  aviation_agent/
    routing.py          # NEW: Router agent
    rules_rag.py        # NEW: RAG retrieval system
    rules_agent.py      # NEW: Rules synthesis agent
    graph.py            # MODIFIED: Add routing
    ... (existing files)
  
  rules_manager.py      # KEEP: Fallback for non-RAG queries

tools/
  xls_to_rules.py       # MODIFIED: Add RAG DB build
  build_rules_rag.py    # NEW: Standalone RAG builder (optional)

cache/
  rules_vector_db/      # NEW: ChromaDB persistence
    chroma.sqlite3
    ...

tests/
  aviation_agent/
    test_routing.py     # NEW
    test_rules_rag.py   # NEW
    test_rules_agent.py # NEW
```

### 7.2 Configuration

Add to `shared/aviation_agent/config.py`:
```python
class RulesRAGSettings(BaseModel):
    enabled: bool = True
    vector_db_path: Path = Field(default_factory=lambda: Path("cache/rules_vector_db"))
    embedding_model: str = "all-MiniLM-L6-v2"  # or "text-embedding-3-small"
    top_k: int = 5
    similarity_threshold: float = 0.5
    
    # Router settings
    router_model: str = "gpt-4o-mini"
    router_enabled: bool = True
```

### 7.3 Dependencies

Add to `requirements.txt`:
```
chromadb>=0.4.22
sentence-transformers>=2.2.0  # For local embeddings
```

---

## 8. Implementation Phases

### Phase 1: RAG Foundation (Week 1)
- [ ] Create `rules_rag.py` with ChromaDB integration
- [ ] Implement embedding generation (local model)
- [ ] Extend xls_to_rules.py to build vector DB
- [ ] Unit tests for RAG retrieval
- [ ] **Deliverable:** Working RAG system for manual testing

### Phase 2: Rules Agent (Week 1-2)
- [ ] Create `rules_agent.py` with LLM synthesis
- [ ] Design prompt template for multi-country answers
- [ ] Add citation and link handling
- [ ] Integration tests with real queries
- [ ] **Deliverable:** Standalone rules agent function

### Phase 3: Router Integration (Week 2)
- [ ] Create `routing.py` with classification logic
- [ ] Implement keyword pre-filter
- [ ] Add country extraction
- [ ] Test router accuracy on labeled dataset
- [ ] **Deliverable:** Router with >90% accuracy

### Phase 4: LangGraph Integration (Week 2-3)
- [ ] Modify `graph.py` to add routing node
- [ ] Update `AgentState` for new flow
- [ ] Add conditional edges based on router decision
- [ ] End-to-end testing
- [ ] **Deliverable:** Working enhanced agent

### Phase 5: Evaluation & Tuning (Week 3)
- [ ] Build test dataset of rules queries
- [ ] Measure retrieval accuracy (precision@5, recall@5)
- [ ] Tune similarity thresholds
- [ ] Compare with baseline (current approach)
- [ ] **Deliverable:** Performance metrics and tuning guide

### Phase 6: Production Readiness (Week 4)
- [ ] Add monitoring/logging
- [ ] Handle edge cases (no results, ambiguous countries)
- [ ] Performance optimization
- [ ] Documentation
- [ ] **Deliverable:** Production-ready feature

---

## 9. Open Questions & Decisions Needed

### Q1: Router Complexity
**Question:** Should we route ALL queries or only obvious rules queries?

**Options:**
- A) Route every query through router (consistent, but adds latency)
- B) Fast pre-filter with keywords, route only ambiguous (faster)
- C) Let planner choose new "query_rules_rag" tool (simpler, but less explicit)

**Recommendation:** B - Keyword pre-filter for obvious cases, router for ambiguous

---

### Q2: Handling "Both" Queries
**Question:** How to handle queries needing both database + rules?

**Example:** "Find customs airports in France with AVGAS"
- Needs: Database query (airports with customs + AVGAS in France)
- Plus: Rules about customs procedures in France

**Options:**
- A) Sequential: Database first → inject results into rules query
- B) Parallel: Run both paths → merge results in formatter
- C) Database only: Trust database flags (has_customs) without rules explanation
- D) Rules override: If rules path, ignore database (force user to ask separately)

**Recommendation:** C for MVP (trust database), A for future enhancement

---

### Q3: Country Extraction
**Question:** How to handle ambiguous country references?

**Examples:**
- "Europe" → Should we query all European countries?
- "Germany and neighboring countries" → How to define "neighboring"?
- No country mentioned → Which country to default to?

**Options:**
- A) Strict: Require explicit country codes, error if ambiguous
- B) Expand: Map regions to countries (Europe → [FR, DE, GB, ...])
- C) Ask: Router returns needs_clarification flag, prompt user
- D) Context: Use conversation history to infer country

**Recommendation:** D + C - Use context, ask if unclear

---

### Q4: RAG Indexing Granularity
**Question:** Should we index questions or question+answer pairs?

**Current Proposal:** Index question text only
- Pro: Query matches question semantically
- Con: Answer content might have relevant keywords not in question

**Alternative:** Index question + answer concatenation
- Pro: Matches on answer keywords too
- Con: Longer documents, potentially noisier matching

**Recommendation:** Start with question-only, add answer if recall is poor

---

### Q5: Caching Strategy
**Question:** Should we cache RAG query results?

**Options:**
- A) No caching (always retrieve fresh)
- B) LRU cache on query string (exact match only)
- C) Semantic cache (cache similar queries)
- D) Pre-compute common queries

**Recommendation:** A for MVP, B for optimization later

---

### Q6: Fallback Behavior
**Question:** What if RAG returns no results (similarity too low)?

**Options:**
- A) Return "I don't know" message
- B) Fallback to current string-matching approach
- C) Broaden search (remove country filter, increase top_k)
- D) Ask user to rephrase

**Recommendation:** C then A - Broaden search, then honest "don't know"

---

### Q7: Multi-Turn Conversations
**Question:** How to handle follow-up questions?

**Example:**
```
User: "What are customs rules in France?"
Agent: [Answer about France]
User: "What about Germany?"
```

Should second query:
- A) Re-route through router (might classify as database query without "rules" keyword)
- B) Remember context that we're in "rules mode"
- C) Always include full conversation history in router

**Recommendation:** C - Router sees full conversation context

---

## 10. Success Metrics

### 10.1 Quantitative Metrics

| Metric | Current Baseline | Target | Measurement |
|--------|-----------------|--------|-------------|
| **Retrieval Precision@5** | N/A (no RAG) | >80% | % of top-5 results relevant to query |
| **Retrieval Recall@5** | N/A | >70% | % of relevant rules in top-5 |
| **Router Accuracy** | N/A | >90% | % of queries routed to correct path |
| **Response Time** | ~2-3s | <3s | P95 latency for rules queries |
| **Token Usage** | ~5K tokens/query | <3K tokens | Average tokens sent to LLM |

### 10.2 Qualitative Metrics

- ✅ Rules answers cite specific countries
- ✅ Multi-country comparisons are coherent
- ✅ Paraphrased questions retrieve same rules
- ✅ No hallucinated regulations
- ✅ Source links included in answers

### 10.3 Test Queries for Evaluation

```python
TEST_QUERIES = [
    # Rules queries
    ("Do I need to file a flight plan in France?", ["FR"], "rules"),
    ("What are customs requirements in Switzerland?", ["CH"], "rules"),
    ("Compare IFR rules between Germany and Austria", ["DE", "AT"], "rules"),
    ("Can I fly VFR at night in the UK?", ["GB"], "rules"),
    
    # Database queries
    ("Airports near Paris", [], "database"),
    ("Find customs airports in France", ["FR"], "database"),
    ("Route from LFPG to LOWI with AVGAS", [], "database"),
    
    # Ambiguous queries
    ("Tell me about France", ["FR"], "rules"),  # Could be either
    ("French airports with customs", ["FR"], "database"),  # Primarily database
]
```

---

## 11. Alternative Architectures (For Consideration)

### 11.1 Hybrid: RAG + Tools

Instead of separate paths, add RAG as a tool in existing planner:

```python
{
    "name": "query_rules_rag",
    "description": "Semantic search for aviation rules using natural language",
    "parameters": {
        "query": "string",
        "countries": "string[]",
    }
}
```

**Pros:**
- Minimal changes to existing graph
- Planner learns when to use RAG vs. other tools
- Can combine RAG with other tools in single query

**Cons:**
- Planner might struggle to learn when to use RAG
- No explicit country extraction in router
- Token overhead of showing all tools to planner

### 11.2 Full RAG: No Database Tools

Extreme approach: Make RAG handle both rules AND airport data

**Approach:**
- Index rules.json questions (as proposed)
- Also index airport descriptions: "LFPG Charles de Gaulle: Major international airport in Paris, France. Customs available. AVGAS available..."
- Single RAG retrieval for all queries

**Pros:**
- Unified architecture
- One retrieval system
- Potentially better for hybrid queries

**Cons:**
- Airport data is structured, not natural language
- Loses precision of SQL queries
- Would need to embed ~10K airports
- Difficult to handle complex filters (runway length > 1200m AND AVGAS AND customs)

### 11.3 LLM Routing at Planner Level

Instead of separate router node, enhance planner prompt:

```python
system_prompt = """
You have two types of tools:
1. Rules tools: For questions about regulations (use when query asks "what are rules", "am I allowed", etc.)
2. Database tools: For questions about airports, locations, facilities

First, classify the query. Then select the appropriate tool.
"""
```

**Pros:**
- Single LLM call (cheaper, faster)
- Leverages planner's tool selection logic

**Cons:**
- Less explicit control
- Harder to tune classification separately
- No structured RouterDecision output

---

## 12. Recommendation Summary

### Recommended Approach

**Phase 1 (MVP):**
1. ✅ Build RAG system with ChromaDB + local embeddings
2. ✅ Integrate RAG build into xls_to_rules.py
3. ✅ Create lightweight router with keyword pre-filter + LLM classifier
4. ✅ Add rules_agent node to LangGraph
5. ✅ Conditional routing: rules path OR database path (not both initially)

**Future Enhancements:**
- Phase 2: Support "both" path (parallel database + rules)
- Phase 3: Upgrade to Qdrant + OpenAI embeddings for production
- Phase 4: Add semantic caching
- Phase 5: Cross-language support (if rules in multiple languages)

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Vector DB** | ChromaDB | Easy setup, good for local development |
| **Embeddings** | all-MiniLM-L6-v2 (local) | Free, fast, good enough for MVP |
| **Router** | LLM-based with keyword pre-filter | Balance of accuracy and speed |
| **RAG Build** | Integrated in xls_to_rules.py | Single workflow for rules updates |
| **Graph Structure** | Add router + rules_agent nodes | Clean separation, easy to test |
| **Retrieval Strategy** | Country-filtered top-k | Efficient and accurate |

---

## 13. Next Steps

1. **Review & Discussion** (This document)
   - Address open questions (Q1-Q7)
   - Validate architecture approach
   - Confirm priorities

2. **Prototype** (Days 1-3)
   - Build standalone RAG retrieval module
   - Test on sample queries
   - Measure retrieval quality

3. **Integrate** (Days 4-7)
   - Add router node
   - Create rules agent
   - Update LangGraph

4. **Evaluate** (Days 8-10)
   - Build test dataset
   - Measure metrics
   - Tune thresholds

5. **Deploy** (Days 11-14)
   - Production hardening
   - Documentation
   - Rollout

---

## Appendix A: Example Queries & Expected Behavior

### Example 1: Simple Rules Query
```
User: "Do I need to file a flight plan in France?"

Router Decision:
  path: "rules"
  countries: ["FR"]
  confidence: 0.95

RAG Retrieval:
  Top 3 matches:
  1. "Is a flight plan required for VFR flights?" (FR) - score: 0.89
  2. "What are flight plan filing requirements?" (FR) - score: 0.85
  3. "Do I need to file IFR flight plan?" (FR) - score: 0.78

Rules Agent Output:
  "In France, flight plan requirements depend on the type of flight:
  
  - **VFR flights**: A flight plan is required if you're leaving the FIR...
  - **IFR flights**: A flight plan is always required...
  
  Sources:
  - [SIA France - Flight Plans](https://...)
  - [EASA regulations](https://...)"
```

### Example 2: Multi-Country Comparison
```
User: "Compare customs rules between France and Switzerland"

Router Decision:
  path: "rules"
  countries: ["FR", "CH"]
  confidence: 0.93

RAG Retrieval:
  Top 5 matches (per country):
  FR:
    1. "Do I need to land at a point of entry?" - score: 0.92
    2. "What are customs clearance procedures?" - score: 0.88
  CH:
    1. "Do I need to land at a point of entry?" - score: 0.92
    2. "What are customs clearance procedures?" - score: 0.87

Rules Agent Output:
  "Here's a comparison of customs rules:
  
  **France (Schengen):**
  - No customs clearance required if arriving from another Schengen country
  - Must land at designated point of entry if arriving from outside Schengen
  
  **Switzerland (Non-Schengen):**
  - Customs clearance required for ALL international flights
  - Must land at one of the designated customs airports
  - PPR may be required at some locations
  
  Key Difference: Switzerland requires customs even from Schengen countries."
```

### Example 3: Database Query (Not Routed to Rules)
```
User: "Find airports near Paris with AVGAS"

Router Decision:
  path: "database"
  countries: ["FR"]
  confidence: 0.88

→ Routes to existing planner/tool flow
→ Uses find_airports_near_location tool
→ No RAG retrieval
```

### Example 4: Ambiguous Query
```
User: "Tell me about flying in Germany"

Router Decision:
  path: "rules"
  countries: ["DE"]
  confidence: 0.65  # Lower confidence, could be either

→ Routes to rules path (default when ambiguous + country mentioned)
→ Retrieves top general rules about Germany
→ Agent provides overview of regulations
```

---

## Appendix B: Prompt Templates

### Router System Prompt
```
You are a query classifier for an aviation assistant. Your job is to determine:
1. Whether the query is about RULES/REGULATIONS or DATABASE/SEARCH
2. Which countries are mentioned (if any)

RULES queries ask about:
- Regulations, requirements, procedures
- "Am I allowed to...", "Do I need to...", "What are the rules..."
- Flight planning rules, customs, airspace, PPR, IFR/VFR rules

DATABASE queries ask about:
- Finding specific airports or locations
- Searching for airports with certain facilities
- "Find airports...", "Show me...", "Route from X to Y"

Extract country codes if mentioned (e.g., "France" → "FR", "Germany" → "DE").

Return a structured classification with:
- path: "rules" or "database"
- countries: list of ISO-2 codes
- confidence: 0.0 to 1.0
- reasoning: brief explanation
```

### Rules Agent System Prompt
```
You are an aviation regulations expert. Answer the pilot's question using ONLY the rules provided below.

Countries in scope: {countries}

Retrieved Rules:
{retrieved_rules}

Instructions:
1. Answer the pilot's specific question
2. Cite which country each rule applies to
3. If rules differ between countries, clearly highlight the differences
4. Include reference links at the end
5. If you don't find relevant rules in the provided context, say "I don't have information about..."
6. Do NOT make up regulations - only use what's provided

Format your answer in clear markdown with:
- Bullet points for lists
- **Bold** for country names and key terms
- Links as [text](url)
```

---

**End of Document**

*This design is intended as a starting point for discussion. Please provide feedback on:*
- *Architecture choices*
- *Open questions (Section 9)*
- *Implementation priorities*
- *Any concerns or alternative approaches*

