# Rules RAG Enhancement - Documentation Index

**Version:** 1.0  
**Date:** 2025-12-02  
**Status:** 🔴 Under Review

---

## Quick Start

**New to this proposal?** Start here:
1. 📖 Read [RULES_RAG_SUMMARY.md](./RULES_RAG_SUMMARY.md) (5 min)
2. 📊 View [RULES_RAG_ARCHITECTURE_DIAGRAM.md](./RULES_RAG_ARCHITECTURE_DIAGRAM.md) (visual overview)
3. 🎯 Review [RULES_RAG_DECISIONS.md](./RULES_RAG_DECISIONS.md) (key decisions)
4. 📋 Read full [RULES_RAG_AGENT_DESIGN.md](./RULES_RAG_AGENT_DESIGN.md) (detailed design)

---

## Document Overview

### 1. [RULES_RAG_SUMMARY.md](./RULES_RAG_SUMMARY.md)
**Purpose:** Executive summary and quick reference  
**Read time:** 5 minutes  
**Content:**
- Core concept explanation
- Key components overview
- Main benefits
- Critical decisions (summarized)
- Implementation phases
- Tech stack choices
- Example query flow

**Best for:** Getting a quick understanding of the proposal

---

### 2. [RULES_RAG_ARCHITECTURE_DIAGRAM.md](./RULES_RAG_ARCHITECTURE_DIAGRAM.md)
**Purpose:** Visual representation of architecture  
**Read time:** 10 minutes  
**Content:**
- Current vs. Proposed architecture diagrams
- Data flow through RAG system
- LangGraph structure comparison
- Query routing logic
- Multi-country query example
- Performance comparison charts

**Best for:** Understanding how components fit together

---

### 3. [RULES_RAG_DECISIONS.md](./RULES_RAG_DECISIONS.md)
**Purpose:** Critical decisions and options analysis  
**Read time:** 15-20 minutes  
**Content:**
- 8 key decisions with pros/cons
- Decision priority ranking
- Detailed options for each decision
- Recommendations with rationale
- Implementation sprint planning
- Questions for stakeholder review

**Best for:** Team discussion and decision-making

**Key Decisions:**
1. Router Complexity (HIGH priority) - Keyword + LLM recommended
2. "Both" Path Handling (MEDIUM) - Database-only for MVP
3. Country Extraction (HIGH) - Context-aware recommended
4. RAG Indexing Granularity (LOW) - Question-only recommended
5. Embedding Model (MEDIUM) - Local for MVP, OpenAI for prod
6. Vector DB Choice (LOW) - ChromaDB recommended
7. RAG Build Timing (MEDIUM) - Integrate into xls_to_rules.py
8. Fallback Strategy (LOW) - Broaden then "don't know"

---

### 4. [RULES_RAG_AGENT_DESIGN.md](./RULES_RAG_AGENT_DESIGN.md)
**Purpose:** Comprehensive technical design document  
**Read time:** 45-60 minutes  
**Content:**
- **Section 1-2:** Current state analysis & problem statement
- **Section 3:** Proposed architecture (detailed)
- **Section 4:** Implementation options for each component
- **Section 5:** Integration with LangGraph
- **Section 6:** Pros/cons analysis
- **Section 7:** Technical specifications
- **Section 8:** Implementation phases
- **Section 9:** Open questions (detailed)
- **Section 10:** Success metrics
- **Section 11:** Alternative architectures
- **Section 12:** Recommendations
- **Appendix A:** Example queries & expected behavior
- **Appendix B:** Prompt templates

**Best for:** Implementation teams, deep technical review

---

## Current Status

### ✅ All Phases Complete!
- [x] Problem analysis
- [x] Architecture design
- [x] Options evaluation
- [x] Documentation
- [x] **ALL KEY DECISIONS MADE** - See [RULES_RAG_DECISIONS_FINAL.md](./RULES_RAG_DECISIONS_FINAL.md)
- [x] **Phase 1:** RAG Foundation ✅ COMPLETE
- [x] **Phase 2:** Router & Country Extraction ✅ COMPLETE
- [x] **Phase 3:** Rules Agent & Integration ✅ COMPLETE

### 🚀 Ready for Testing
- [ ] **UI Testing** - See [RULES_RAG_READY_FOR_UI.md](./RULES_RAG_READY_FOR_UI.md)
- [ ] **Phase 5:** Evaluation & Tuning (After UI feedback)
- [ ] **Phase 6:** Production Deployment

---

## Key Questions for Review

### Architecture Questions
1. **Router Approach:** Should we add 200ms latency to all queries with LLM router, or use keyword pre-filter?
   - **Recommendation:** Keyword pre-filter for ~80% of queries, LLM for ambiguous 20%

2. **Country Extraction:** How to handle "Europe" or ambiguous country references?
   - **Recommendation:** Use conversation context, ask if unclear

3. **Compound Queries:** Support "Find customs airports AND tell me customs rules" in MVP?
   - **Recommendation:** No, defer to Phase 2. Choose primary intent for MVP.

### Technical Questions
4. **Embedding Model:** Free local model or pay for OpenAI quality?
   - **Recommendation:** Local for MVP ($0), evaluate quality, upgrade if needed ($1/month)

5. **RAG Build:** Integrate into xls_to_rules.py or separate script?
   - **Recommendation:** Integrate (single workflow, always in sync)

6. **Vector DB:** ChromaDB sufficient or need production-grade (Qdrant)?
   - **Recommendation:** ChromaDB for MVP, sufficient for expected scale

### Product Questions
7. **User Experience:** Is it OK to ask users "Which country?" when ambiguous?
   - Affects Decision 3

8. **Performance:** Is 200-300ms acceptable latency for routing?
   - Affects Decision 1

9. **Scope:** Must MVP support all query types or can we iterate?
   - Affects Decision 2

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1)
**Goal:** Working RAG retrieval system

**Deliverables:**
- `shared/aviation_agent/rules_rag.py` - RAG module
- Vector DB build integrated into `tools/xls_to_rules.py`
- Unit tests for retrieval

**Dependencies:**
- Decision 5 (Embedding model)
- Decision 7 (Build timing)

---

### Phase 2: Router (Week 2)
**Goal:** Query classification system

**Deliverables:**
- `shared/aviation_agent/routing.py` - Router module
- Keyword pre-filter logic
- Country extraction

**Dependencies:**
- Decision 1 (Router complexity)
- Decision 3 (Country extraction)

---

### Phase 3: Rules Agent (Week 2-3)
**Goal:** Rules synthesis and answer generation

**Deliverables:**
- `shared/aviation_agent/rules_agent.py` - Synthesis agent
- Prompt templates
- Citation handling

**Dependencies:**
- Phase 1 complete
- Decision 2 ("Both" handling)

---

### Phase 4: Integration (Week 3)
**Goal:** Full LangGraph integration

**Deliverables:**
- Modified `shared/aviation_agent/graph.py`
- Updated `AgentState`
- Conditional routing edges

**Dependencies:**
- All previous phases

---

### Phase 5: Testing & Tuning (Week 3-4)
**Goal:** Production-ready quality

**Deliverables:**
- Test dataset (100+ queries)
- Evaluation metrics
- Tuning guidelines
- Performance benchmarks

---

### Phase 6: Production (Week 4)
**Goal:** Deploy to production

**Deliverables:**
- Monitoring & logging
- Error handling
- Documentation
- Rollout plan

---

## Success Metrics (Target)

| Metric | Current | Target | Measurement Method |
|--------|---------|--------|-------------------|
| **Retrieval Precision@5** | N/A | >80% | Manual eval on test set |
| **Retrieval Recall@10** | N/A | >70% | Manual eval on test set |
| **Router Accuracy** | N/A | >90% | Labeled query dataset |
| **Response Time (p95)** | ~3s | <3s | Production metrics |
| **Token Usage/Query** | ~5K | <3K | LLM API logs |
| **Cost/Query** | ~$0.015 | <$0.005 | LLM + embedding costs |

---

## Tech Stack Summary

### Core Components
- **Vector DB:** ChromaDB (local persistence)
- **Embeddings:** all-MiniLM-L6-v2 (MVP), text-embedding-3-small (production)
- **Router LLM:** GPT-4o-mini (fast, cheap)
- **Rules Agent LLM:** GPT-4o (quality)
- **Framework:** LangGraph (existing)

### New Dependencies
```python
# requirements.txt additions:
chromadb>=0.4.22
sentence-transformers>=2.2.0  # For local embeddings
```

### Storage Requirements
- Vector DB: ~10-50MB (depending on number of rules)
- Embeddings cache: ~5MB

---

## File Changes Overview

### New Files
```
shared/aviation_agent/
  routing.py              # Router agent (300 lines)
  rules_rag.py            # RAG retrieval system (400 lines)
  rules_agent.py          # Rules synthesis agent (300 lines)

cache/
  rules_vector_db/        # ChromaDB storage directory
    chroma.sqlite3
    ...

tests/aviation_agent/
  test_routing.py         # Router tests
  test_rules_rag.py       # RAG tests
  test_rules_agent.py     # Rules agent tests
```

### Modified Files
```
shared/aviation_agent/
  graph.py               # Add routing node, conditional edges (~50 lines added)
  state.py               # Add RAG-related state fields (~10 lines added)

tools/
  xls_to_rules.py        # Add vector DB build step (~100 lines added)
```

### Unchanged Files
```
shared/
  rules_manager.py       # Keep for backward compatibility/fallback
  airport_tools.py       # No changes needed

shared/aviation_agent/
  tools.py               # No changes (RAG not exposed as tool)
  execution.py           # No changes
  formatting.py          # Minor tweaks for rules path
```

---

## Risk Assessment

### High Risk ⚠️
1. **Router Accuracy:** If <85%, many queries misrouted
   - **Mitigation:** Build test dataset early, tune thresholds, keyword fallback
   
2. **RAG Retrieval Quality:** If precision <70%, poor answers
   - **Mitigation:** Prototype early, evaluate on real queries, tune top-k

### Medium Risk ⚠️
3. **Performance Regression:** If slower than current system
   - **Mitigation:** Benchmark at each phase, optimize critical path
   
4. **Context Window Issues:** Multi-country queries might exceed limits
   - **Mitigation:** Limit countries per query, truncate intelligently

### Low Risk ⚠️
5. **ChromaDB Scaling:** Might not scale beyond 10K rules
   - **Mitigation:** Plan migration to Qdrant if needed (easy with abstraction)

6. **Country Extraction Errors:** Might miss or misidentify countries
   - **Mitigation:** Manual fallback, user can correct in follow-up

---

## Next Steps (Immediate)

### This Week
1. **Review Documents** (Team/Stakeholders)
   - Read summary & decisions
   - Discuss open questions
   - Align on priorities

2. **Make Key Decisions**
   - Decision 1: Router approach
   - Decision 3: Country extraction
   - Decision 5: Embedding model

3. **Prototype RAG Module** (Developer)
   - Build basic rules_rag.py
   - Test retrieval on sample queries
   - Measure quality metrics

### Next Week
4. **Decision Checkpoint**
   - Review prototype results
   - Finalize remaining decisions
   - Approve implementation plan

5. **Sprint 1 Kickoff**
   - Begin Phase 1 implementation
   - Set up test infrastructure
   - Define evaluation dataset

---

## Contact & Questions

**Design Owner:** [Your Name]  
**Implementation Team:** [Team Name]  
**Stakeholders:** [List]

**For Questions:**
- Architecture: See Section 3 of main design doc
- Decisions: See RULES_RAG_DECISIONS.md
- Implementation: See Section 7-8 of main design doc

**Feedback Channels:**
- GitHub Issues: [Link]
- Slack: [Channel]
- Email: [Address]

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2025-12-02 | Initial design | [Your Name] |

---

**Status Legend:**
- 🔴 Needs attention/decision
- 🟡 In progress
- 🟢 Complete
- ⏸️ Blocked/waiting
- ✅ Done
- ⚠️ Risk identified

