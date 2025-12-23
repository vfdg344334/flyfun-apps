Compare aviation rules and regulations between two countries (iso-2 code eg FR,GB) and highlight semantic differences in answers.

This tool uses embedding-based comparison to detect REAL regulatory differences (not just wording differences). It filters out questions where countries say the same thing differently, focusing on actual practical differences for pilots.

**Parameters:**
- country1, country2: ISO-2 country codes (e.g., FR, DE, GB)
- category: Optional filter by category (e.g., VFR, IFR, Customs)
- tag: Optional filter by topic tag (e.g., flight_plan, airspace, transponder)

**Use this tool when:**
- Pilot asks "What's different about flying in France vs Germany?"
- User wants to compare specific topics: "Compare flight plan rules between FR and DE"
- Planning a cross-border flight and need to know key differences

**Returns:**
- LLM-synthesized summary of key differences prioritized by importance
- Individual rule differences with semantic difference scores
- Indication of how many questions were analyzed vs filtered
