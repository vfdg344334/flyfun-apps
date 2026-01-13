# flyfun-rules

> Aviation planning web app with LLM agent, European AIP data, and GA friendliness scoring

## Core Architecture

### LLM Agent Design
Planner-based aviation agent using LangGraph. LLM planner selects tools, tool runner executes, formatter produces UI payloads. Supports airport queries, route planning, and rules lookup.
Key exports: `AviationPlan`, `build_ui_payload`, airport tools, rules tools
→ Full doc: LLM_AGENT_DESIGN.md

### Rules RAG System
RAG-powered rules retrieval with smart router. Classifies queries as rules vs database, uses embeddings for semantic search, supports multi-country comparisons.
Key exports: `QueryRouter`, `RulesRAG`, `compare_rules_between_countries`
→ Full doc: RULES_RAG_AGENT_DESIGN.md

### UI Filter State Management
Zustand-based reactive state management for airport explorer. Unidirectional data flow, store subscriptions, event-driven component communication.
Key exports: `store`, `FilterConfig`, `UIManager`, `VisualizationEngine`
→ Full doc: UI_FILTER_STATE_DESIGN.md

## Data & Scoring

### GA Friendliness System
Persona-based airport scoring using reviews, fees, and AIP data. Separate enrichment database (`ga_persona.db`), LLM-extracted features, configurable personas.
Key exports: `GAFriendlinessService`, `PersonaManager`, `AirportFeatureScores`
→ Full doc: GA_FRIENDLINESS_DESIGN.md

### AIP Field Search
Structured search on preprocessed AIP data. Integer encoding for hospitality fields (-1=unknown, 0=none, 1=vicinity, 2=at_airport), filter semantics where "vicinity" includes "at_airport".
Key exports: `HotelFilter`, `RestaurantFilter`, `get_icaos_by_hospitality`
→ Full doc: AIP_FIELD_SEARCH_DESIGN.md

### GA Notification Agent
Waterfall parser for PPR/customs notification requirements. Regex patterns handle simple cases (H24, O/R, hours notice), LLM fallback for complex rules. Outputs factual rules to `ga_notifications.db` and hassle scores to `ga_persona.db`.
Key exports: `NotificationParser`, `NotificationScorer`, `NotificationBatchProcessor`, `get_notification_config`
→ Full doc: NOTIFICATION_PARSING_DESIGN.md

## Deployment & Configuration

### Aviation Agent Configuration
Configuration system for aviation agent prompts, personas, and tools. YAML-based configs, prompt templates with placeholders.
→ Full doc: AVIATION_AGENT_CONFIGURATION_DESIGN.md

### Docker Deployment
Container deployment setup for web server and services.
→ Full doc: DOCKER_DEPLOYMENT.md

## Mobile

### iOS App
Native iOS application for aviation data. SwiftUI interface, offline-capable, integrates with euro_aip data.
→ Full doc: IOS_APP_DESIGN.md

## Reference

### Chatbot Web UI
Web-based chat interface with map visualization, filter panels, and airport cards.
→ Full doc: CHATBOT_WEBUI_DESIGN.md

### Architecture Diagrams
Visual diagrams for Rules RAG system flow and component interactions.
→ Full doc: RULES_RAG_ARCHITECTURE_DIAGRAM.md

