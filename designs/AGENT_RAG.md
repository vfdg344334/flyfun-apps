# Aviation Agent RAG System

> Rules RAG, query router, country extraction, and comparison system.

## Quick Reference

| File | Purpose |
|------|---------|
| `shared/aviation_agent/routing.py` | Query router and country extraction |
| `shared/aviation_agent/rules_rag.py` | RAG retrieval system |
| `shared/aviation_agent/rules_agent.py` | Rules synthesis agent |
| `shared/aviation_agent/answer_comparer.py` | Embedding-based comparison |
| `shared/aviation_agent/comparison_service.py` | High-level comparison API |
| `configs/aviation_agent/prompts/router_v1.md` | Router prompt |
| `configs/aviation_agent/prompts/rules_agent_v1.md` | Rules agent prompt |

**Key Exports:**
- `QueryRouter` - Query classification
- `RulesRAG` - Vector retrieval
- `RulesComparisonService` - Cross-country comparison
- `AnswerComparer` - Embedding similarity

**Prerequisites:** Read `AGENT_ARCHITECTURE.md` first.

---

## Architecture Overview

```
User Query
    ↓
┌─────────────────────────────────────┐
│          Query Router               │
│ • Keyword pre-filter (fast path)    │
│ • LLM classification (ambiguous)    │
│ • Country extraction                │
└─────────────────────────────────────┘
    ↓
    Rules Path
    ↓
┌─────────────────────────────────────┐
│          RAG Retrieval              │
│ • Query embedding                   │
│ • Vector search with filters        │
│ • Optional reranking                │
└─────────────────────────────────────┘
    ↓
┌─────────────────────────────────────┐
│          Rules Agent                │
│ • Synthesize answer from rules      │
│ • Multi-country comparison          │
│ • Citation and links                │
└─────────────────────────────────────┘
```

---

## Query Router

### RouterDecision Schema

```python
class RouterDecision(BaseModel):
    path: Literal["rules", "database", "both"]
    confidence: float  # 0.0 - 1.0
    countries: List[str]  # ISO-2 codes
    reasoning: str
```

### Two-Stage Routing

**Stage 1: Keyword Pre-filter (Fast Path)**

Handles ~80% of queries:

```python
RULES_KEYWORDS = ["rules", "regulations", "allowed", "required", "customs",
                  "flight plan", "IFR", "VFR", "PPR", "clearance"]
DATABASE_KEYWORDS = ["find", "near", "between", "airports with", "runway",
                     "AVGAS", "route from"]
```

**Stage 2: LLM Classification**

For genuinely ambiguous queries (~20%):

```python
class QueryRouter:
    def route(self, messages: List[BaseMessage]) -> RouterDecision:
        # Try keyword pre-filter first
        last_message = messages[-1].content.lower()
        if self._is_clear_rules_query(last_message):
            return RouterDecision(path="rules", confidence=0.95, ...)
        if self._is_clear_database_query(last_message):
            return RouterDecision(path="database", confidence=0.95, ...)

        # Ambiguous - use LLM
        return self._llm_classify(messages)
```

---

## Country Extraction

Extracts countries from multiple sources:

### Country Names

```python
"France" → "FR"
"United Kingdom" → "GB"
"Germany" → "DE"
```

### ISO-2 Codes

```python
"FR", "GB", "DE" → pass through
```

### ICAO Prefixes (Innovation)

```python
"LFMD" → LF → "FR" (France)
"EGKB" → EG → "GB" (UK)
"EDDF" → ED → "DE" (Germany)
```

**ICAO Prefix Map:**

```python
ICAO_PREFIX_TO_COUNTRY = {
    "LF": "FR",  # France
    "EG": "GB",  # UK
    "ED": "DE",  # Germany
    "EH": "NL",  # Netherlands
    "EB": "BE",  # Belgium
    "LI": "IT",  # Italy
    "LE": "ES",  # Spain
    "LP": "PT",  # Portugal
    "LS": "CH",  # Switzerland
    "LO": "AT",  # Austria
    # ... 50+ European prefixes
}
```

### Context-Aware Extraction

Checks last 5 messages for country context:

```python
def extract_countries(self, messages: List[BaseMessage]) -> List[str]:
    countries = set()
    for msg in messages[-5:]:  # Last 5 messages
        countries.update(self._extract_from_text(msg.content))
    return list(countries)
```

---

## RAG Retrieval

### Vector Database

Uses ChromaDB with two collections:

| Collection | Content | Purpose |
|------------|---------|---------|
| `aviation_rules` | Question text embeddings | RAG retrieval |
| `aviation_rules_answers` | Answer text embeddings | Comparison |

### Retrieval Flow

```python
class RulesRAG:
    def retrieve(
        self,
        query: str,
        countries: List[str],
        top_k: int = 5,
        category: Optional[str] = None
    ) -> List[RuleDoc]:
        # 1. Reformulate query (optional)
        if self.config.query_reformulation.enabled:
            query = self.reformulator.reformulate(query)

        # 2. Embed query
        query_embedding = self.embed(query)

        # 3. Search with country filter
        results = self.collection.query(
            query_embeddings=[query_embedding],
            where={"country_code": {"$in": countries}},
            n_results=top_k * len(countries)
        )

        # 4. Rerank (optional)
        if self.config.reranking.enabled:
            results = self.reranker.rerank(query, results, top_k)

        return results
```

### Query Reformulation

Converts colloquial queries to formal questions:

```python
# Input
"Where do I clear customs?"

# Reformulated
"border crossing procedures customs clearance requirements"
```

### Reranking

**Cohere Reranker:**
- Uses specialized cross-encoder models
- Best relevance but requires API key

**OpenAI Reranker:**
- Uses embedding similarity
- No additional API cost

```python
# Selection based on config
if config.reranking.provider == "cohere":
    reranker = CohereReranker(model="rerank-v3.5")
elif config.reranking.provider == "openai":
    reranker = OpenAIReranker(model="text-embedding-3-large")
else:
    reranker = None  # Skip reranking
```

---

## Rules Agent

Synthesizes answers from retrieved rules:

```python
class RulesAgent:
    def synthesize(
        self,
        query: str,
        countries: List[str],
        retrieved_rules: List[RuleDoc]
    ) -> str:
        prompt = f"""You are an aviation regulations expert.

Countries in scope: {', '.join(countries)}

Retrieved Rules:
{self._format_rules(retrieved_rules)}

User Question: {query}

Instructions:
- Cite which country each rule applies to
- Highlight differences between countries
- Include reference links
- Only use provided rules, never make up regulations
"""
        return self.llm.invoke(prompt).content
```

---

## Comparison System

### Architecture

```
User: "Compare VFR rules between France and Germany"
    ↓
Planner (selects compare_rules_between_countries)
    ↓
Tool (returns DATA only via ComparisonService)
    ↓
Formatter (uses comparison_synthesis prompt)
    ↓
Final Answer
```

### AnswerComparer

Low-level embedding comparison:

```python
class AnswerComparer:
    def compare_countries(
        self,
        countries: List[str],
        tag: Optional[str] = None,
        max_questions: int = 15,
        min_difference: float = 0.1
    ) -> ComparisonResult:
        """
        1. Get questions matching tag
        2. Retrieve answer embeddings from vector DB
        3. Compute pairwise cosine distances
        4. Filter to questions with semantic differences > min_difference
        5. Return ranked differences
        """
```

### ComparisonService

High-level API used by tools:

```python
class RulesComparisonService:
    def compare_countries(
        self,
        countries: List[str],
        tag: Optional[str] = None,
        synthesize: bool = False  # Tools pass False
    ) -> SynthesizedComparison:
        # Get differences using AnswerComparer
        differences = self.comparer.compare_countries(countries, tag)

        # Format for synthesis prompt
        rules_context = self._format_for_synthesis(differences)

        return SynthesizedComparison(
            differences=differences,
            rules_context=rules_context,
            countries=countries
        )
```

### Tool Integration

```python
def compare_rules_between_countries(ctx, countries, category=None, tag=None):
    result = ctx.comparison_service.compare_countries(
        countries=countries,
        tag=tag,
        synthesize=False  # Never synthesize in tool!
    )

    return {
        "_tool_type": "comparison",  # Signals comparison formatter
        "differences": result.differences,
        "rules_context": result.rules_context,
        "countries": countries,
    }
```

---

## Building the RAG Database

```bash
# Build during rules generation
python tools/xls_to_rules.py --build-rag

# Or standalone
python -m shared.aviation_agent.rules_rag --build-rag
```

### Build Process

```python
def build_vector_db(rules_json_path: Path, output_db_path: Path):
    rules = load_rules_json(rules_json_path)
    client = chromadb.PersistentClient(path=str(output_db_path))

    # Questions collection
    questions = client.get_or_create_collection("aviation_rules")

    # Answers collection (for comparison)
    answers = client.get_or_create_collection("aviation_rules_answers")

    for question in rules["questions"]:
        for country_code, answer in question["answers_by_country"].items():
            doc_id = f"{question['question_id']}_{country_code}"

            # Add question embedding
            questions.add(
                documents=[question["question_text"]],
                metadatas=[{
                    "question_id": question["question_id"],
                    "country_code": country_code,
                    "category": question["category"],
                    "answer_html": answer["answer_html"],
                }],
                ids=[doc_id]
            )

            # Add answer embedding
            answers.add(
                documents=[answer["answer_html"]],
                metadatas=[{"question_id": question["question_id"], "country_code": country_code}],
                ids=[f"{doc_id}_answer"]
            )
```

---

## Configuration

```json
{
  "routing": {
    "enabled": true
  },
  "query_reformulation": {
    "enabled": true
  },
  "rag": {
    "embedding_model": "text-embedding-3-small",
    "retrieval": {
      "top_k": 5,
      "similarity_threshold": 0.3,
      "rerank_candidates_multiplier": 2
    }
  },
  "reranking": {
    "enabled": true,
    "provider": "cohere",
    "cohere": {"model": "rerank-v3.5"},
    "openai": {"model": "text-embedding-3-large"}
  },
  "comparison": {
    "max_questions": 15,
    "min_difference": 0.1
  }
}
```

---

## Performance Results

| Metric | Target | Achieved |
|--------|--------|----------|
| Retrieval Precision@5 | >80% | 82% |
| Routing Accuracy | >90% | >95% |
| Country Extraction | >95% | ~98% |
| Response Time | <3s | 37% faster |
| Token Usage | <3K | 80% reduction |

---

## Testing

```python
# test_routing.py
def test_rules_query_routing():
    router = QueryRouter()
    decision = router.route([HumanMessage("VFR rules in France")])
    assert decision.path == "rules"
    assert "FR" in decision.countries


def test_icao_country_extraction():
    router = QueryRouter()
    decision = router.route([HumanMessage("Can I land at LFMD?")])
    assert "FR" in decision.countries


# test_rules_rag.py
def test_rag_retrieval():
    rag = RulesRAG()
    results = rag.retrieve("customs requirements", countries=["FR"])
    assert len(results) > 0
    assert all(r["country_code"] == "FR" for r in results)
```

---

## Debugging

```bash
# Test routing
python -c "
from shared.aviation_agent.routing import QueryRouter
router = QueryRouter()
decision = router.route([HumanMessage('VFR rules in France')])
print(decision)
"

# Test RAG retrieval
python -c "
from shared.aviation_agent.rules_rag import RulesRAG
rag = RulesRAG()
results = rag.retrieve('customs', countries=['FR'])
for r in results[:3]:
    print(r['question_text'])
"
```
