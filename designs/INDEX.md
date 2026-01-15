# flyfun-rules

> Aviation planning web app with LLM agent, European AIP data, and GA friendliness scoring

## Web App (Frontend)

### Web App Architecture
Core architecture patterns: Zustand store as single source of truth, unidirectional data flow, component communication via store and events. **Read first** before any web UI work.
Key exports: `store`, `AppState`, `VisualizationEngine`, `UIManager`, `ChatbotManager`
→ Full doc: WEB_APP_ARCHITECTURE.md

### Web App State
Zustand store design: state structure, actions, filtering logic, subscriptions, data flow patterns.
Key exports: `store`, `FilterConfig`, `GAState`, `RulesState`
→ Full doc: WEB_APP_STATE.md

### Web App Map
Map visualization: VisualizationEngine, Leaflet integration, markers, routes, highlights, layers, view management.
Key exports: `VisualizationEngine`, marker styles, route rendering
→ Full doc: WEB_APP_MAP.md

### Web App Legends
Legend system: shared configuration, match-function classification, legend modes (notification, airport-type, runway-length, relevance), LLM legend switching.
Key exports: `LegendConfig`, `LegendEntry`, `NOTIFICATION_LEGEND_CONFIG`, `classifyData`, `getColorFromConfig`
→ Full doc: WEB_APP_LEGENDS.md

### Web App Chat Integration
Chatbot integration: ChatbotManager, SSE streaming, UI payload handling, visualization types (markers, route_with_markers, point_with_markers, marker_with_details).
Key exports: `ChatbotManager`, `LLMIntegration`, visualization handlers
→ Full doc: WEB_APP_CHAT.md

### Web App Filters
Filter system: FilterEngine (backend single source), filter types, AIP filtering, adding new filters, filter profile application.
Key exports: `FilterEngine`, `FilterConfig`, filter implementations
→ Full doc: WEB_APP_FILTERS.md

---

## LLM Agent (Backend)

### Aviation Agent Design
Planner-based aviation agent using LangGraph. LLM planner selects tools, tool runner executes, formatter produces UI payloads. Supports airport queries, route planning, and rules lookup.
Key exports: `AviationPlan`, `build_ui_payload`, airport tools, rules tools
→ Full doc: LLM_AGENT_DESIGN.md

### Rules RAG System
RAG-powered rules retrieval with smart router. Classifies queries as rules vs database, uses embeddings for semantic search, supports multi-country comparisons.
Key exports: `QueryRouter`, `RulesRAG`, `compare_rules_between_countries`
→ Full doc: RULES_RAG_AGENT_DESIGN.md

### Aviation Agent Configuration
Configuration system for aviation agent prompts, personas, and tools. YAML-based configs, prompt templates with placeholders.
→ Full doc: AVIATION_AGENT_CONFIGURATION_DESIGN.md

---

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

---

## Mobile (iOS/macOS)

### iOS App Architecture
Core architecture patterns: RZFlight model reuse, composed AppState, domain structure, environment injection. **Read first** before any iOS work.
→ Full doc: IOS_APP_ARCHITECTURE.md

### iOS App Data Layer
Repository pattern, LocalAirportDataSource (KnownAirports), FilterConfig, region-based loading for map performance.
→ Full doc: IOS_APP_DATA.md

### iOS App Map
Map views (online SwiftUI Map, offline MKMapView), legend modes, AirportMarkerView, visualization from chat.
→ Full doc: IOS_APP_MAP.md

### iOS App Chat System
ChatDomain, OnlineChatbotService (SSE), OfflineChatbotService (MediaPipe), LocalToolDispatcher, suggested queries.
→ Full doc: IOS_APP_CHAT.md

### iOS App Offline Mode
Tile caching (CachedTileOverlay, OfflineTileManager), bundled data (airports.db, rules.json), on-device AI (Gemma 2B via MediaPipe).
→ Full doc: IOS_APP_OFFLINE.md

---

## Deployment

### Docker Deployment
Container deployment setup for web server and services.
→ Full doc: DOCKER_DEPLOYMENT.md

---

## Reference

### Architecture Diagrams
Visual diagrams for Rules RAG system flow and component interactions.
→ Full doc: RULES_RAG_ARCHITECTURE_DIAGRAM.md
