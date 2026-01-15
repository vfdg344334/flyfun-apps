# iOS App Chat System

> Chat interface, AI services, and tool execution.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                       ChatDomain                                 │
│  (messages, streaming state, offline toggle)                     │
└─────────────────────────────┬───────────────────────────────────┘
                              │
              ┌───────────────┴───────────────┐
              │ isOfflineMode?                │
              ▼                               ▼
┌─────────────────────────┐     ┌─────────────────────────────────┐
│ OnlineChatbotService    │     │    OfflineChatbotService        │
│                         │     │                                 │
│ - SSE from web API      │     │ - MediaPipe InferenceEngine     │
│ - Server does planning  │     │ - LocalToolDispatcher           │
│ - Full capabilities     │     │ - Bundled rules.json            │
└─────────────────────────┘     └─────────────────────────────────┘
```

## ChatDomain

Manages chat state and delegates to appropriate service:

```swift
@Observable
@MainActor
final class ChatDomain {
    // State
    var messages: [ChatMessage] = []
    var input: String = ""
    var isStreaming: Bool = false
    var currentThinking: String?
    var currentToolCall: String?
    var error: String?

    // Offline mode toggle
    var isOfflineMode: Bool = false

    // Follow-up suggestions from last response
    var suggestedQueries: [SuggestedQuery] = []

    // Cross-domain callbacks
    var onVisualization: ((ChatVisualizationPayload) -> Void)?
    var onClearVisualization: (() -> Void)?

    // Services
    private var onlineChatbotService: ChatbotService?
    private var offlineChatbotService: OfflineChatbotService?

    private var chatbotService: ChatbotService? {
        isOfflineMode ? offlineChatbotService : onlineChatbotService
    }

    func send() async {
        // Stream response from active service
        for try await event in service.sendMessage(userMessage, history: messages.dropLast()) {
            await handleEvent(event, ...)
        }
    }

    func setOfflineMode(_ offline: Bool) {
        isOfflineMode = offline
    }
}
```

## ChatbotService Protocol

Common interface for online/offline services:

```swift
protocol ChatbotService: Sendable {
    func sendMessage(
        _ message: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<ChatEvent, Error>

    func isAvailable() async -> Bool
}
```

## Chat Events

Streaming events from both services:

```swift
enum ChatEvent: Sendable {
    case thinking(content: String)
    case thinkingDone
    case toolCallStart(name: String, arguments: [String: Any])
    case toolCallEnd(name: String, result: ToolResult)
    case message(content: String)
    case uiPayload(ChatVisualizationPayload)
    case plan(PlanData)
    case finalAnswer
    case done(sessionId: String?, tokens: TokenUsage?)
    case error(message: String)
    case unknown(event: String, data: String)
}
```

## OnlineChatbotService

Streams from server API via SSE:

```swift
final class OnlineChatbotService: ChatbotService {
    private let baseURL: URL
    private var sessionId: String?

    func sendMessage(_ message: String, history: [ChatMessage]) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // POST to /api/aviation-agent/chat with SSE streaming
                let request = ChatRequest(messages: history + [.user(message)])

                for try await event in streamSSE(endpoint: .chatStream(request)) {
                    // Parse SSE events and yield ChatEvents
                    continuation.yield(parseEvent(event))
                }
            }
        }
    }
}
```

## OfflineChatbotService

Uses on-device MediaPipe LLM:

```swift
final class OfflineChatbotService: ChatbotService, @unchecked Sendable {
    private let inferenceEngine: InferenceEngine
    private let toolDispatcher: LocalToolDispatcher
    private let modelManager: ModelManager

    func sendMessage(_ message: String, history: [ChatMessage]) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // 1. Ensure model is loaded
                if !inferenceEngine.isLoaded {
                    continuation.yield(.thinking(content: "Loading AI model..."))
                    try await inferenceEngine.loadModel(at: modelManager.modelPath)
                }

                // 2. Generate response with system prompt
                let prompt = buildPrompt(message: message, history: history)
                var response = try await inferenceEngine.generate(prompt: prompt)

                // 3. Tool-calling loop
                while let toolCall = toolDispatcher.parseToolCall(from: response) {
                    continuation.yield(.toolCallStart(name: toolCall.name, arguments: toolCall.arguments))

                    let result = await toolDispatcher.dispatch(request: toolCall)
                    continuation.yield(.toolCallEnd(name: toolCall.name, result: result))

                    // Emit visualization for map
                    if let viz = buildVisualization(for: toolCall, result: result) {
                        continuation.yield(.uiPayload(viz))
                    }

                    // Generate follow-up with tool result
                    response = try await inferenceEngine.generate(prompt: followUpPrompt)
                }

                continuation.yield(.message(content: response))
                continuation.yield(.done(sessionId: nil, tokens: nil))
            }
        }
    }
}
```

## LocalToolDispatcher

Executes tools against local database:

```swift
final class LocalToolDispatcher {
    private var airportDataSource: LocalAirportDataSource?
    private var rulesManager: RulesManager?

    // Available tools
    static let availableTools = [
        "search_airports",
        "get_airport_details",
        "find_airports_near_route",
        "find_airports_near_location",
        "get_border_crossing_airports",
        "find_airports_by_notification",
        "list_rules_for_country",
        "compare_rules_between_countries"
    ]

    func parseToolCall(from response: String) -> ToolCallRequest? {
        // Parse JSON tool call from LLM response
        // {"name": "search_airports", "arguments": {"query": "Paris"}}
    }

    func dispatch(request: ToolCallRequest) async -> ToolResult {
        switch request.name {
        case "search_airports":
            let query = request.arguments["query"] as? String ?? ""
            let airports = try? await airportDataSource?.searchAirports(query: query, limit: 50)
            return ToolResult(value: formatAirports(airports))

        case "find_airports_near_location":
            // Use notification filtering if max_hours_notice specified
            // ...

        case "list_rules_for_country":
            let country = request.arguments["country"] as? String ?? ""
            let rules = rulesManager?.rulesForCountry(country)
            return ToolResult(value: formatRules(rules))

        // ... other tools
        }
    }
}
```

## InferenceEngine (MediaPipe)

On-device LLM inference:

```swift
final class InferenceEngine {
    private var llmInference: LlmInference?

    var isLoaded: Bool { llmInference != nil }

    func loadModel(at path: String) async throws {
        let options = LlmInference.Options(modelPath: path)
        options.maxTokens = 2048
        options.temperature = 0.7
        llmInference = try LlmInference(options: options)
    }

    func generate(prompt: String) async throws -> String {
        guard let llm = llmInference else {
            throw InferenceError.modelNotLoaded
        }
        return try llm.generateResponse(inputText: prompt)
    }
}
```

## ModelManager

Manages LLM model files:

```swift
final class ModelManager {
    var isModelAvailable: Bool {
        FileManager.default.fileExists(atPath: modelPath)
    }

    var modelPath: String {
        // Check bundled model first, then downloaded
        if let bundled = Bundle.main.path(forResource: "gemma-2b-it-cpu-int4", ofType: "bin") {
            return bundled
        }
        return downloadedModelPath
    }
}
```

## Suggested Queries

After responses, the service can suggest follow-up queries:

```swift
// In ChatDomain
var suggestedQueries: [SuggestedQuery] = []

// Captured from uiPayload
case .uiPayload(let payload):
    if let queries = payload.suggestedQueries, !queries.isEmpty {
        suggestedQueries = queries
    }
    onVisualization?(payload)

// User can tap to use
func useSuggestion(_ query: SuggestedQuery, autoSend: Bool = true) async {
    input = query.text
    suggestedQueries = []
    if autoSend {
        await send()
    }
}
```

## Chat Visualization Payload

Instructs map what to display:

```swift
struct ChatVisualizationPayload: Sendable {
    let kind: Kind  // airport, route, list, search
    let visualization: VisualizationData?
    let filters: ChatFilters?
    let airports: [String]?  // ICAOs to highlight
    let suggestedQueries: [SuggestedQuery]?

    enum Kind: String { case airport, route, list, search, unknown }
}

struct VisualizationData: Sendable {
    let markers: [[String: Any]]?  // Airport markers
    let route: RouteData?          // Route polyline
    let center: CLLocationCoordinate2D?  // Focus point
}
```

## Offline Mode Toggle

Toggle is in ChatView toolbar:

```swift
// In ChatView toolbar
ToolbarItem(placement: .topBarLeading) {
    Button {
        state?.chat.setOfflineMode(!(state?.chat.isOfflineMode ?? false))
    } label: {
        Label(
            state?.chat.isOfflineMode == true ? "Offline" : "Online",
            systemImage: state?.chat.isOfflineMode == true ? "airplane.circle.fill" : "cloud.fill"
        )
        .foregroundStyle(state?.chat.isOfflineMode == true ? .orange : .blue)
    }
}
```

## System Prompt (Offline)

The offline LLM uses this system prompt for tool selection:

```
You are FlyFun, an expert aviation planning assistant for European pilots.

## Available Tools
Use JSON format to call tools: {"name": "tool_name", "arguments": {...}}

- search_airports: Search airports by ICAO code, name, or city
- get_airport_details: Get detailed information about a specific airport
- find_airports_near_route: Find airports along a flight route
- find_airports_near_location: Find airports near a city or airport
- get_border_crossing_airports: Get customs/border crossing airports
- find_airports_by_notification: Find airports by notification requirements
- list_rules_for_country: Get aviation rules for a country
- compare_rules_between_countries: Compare rules between two countries

[Tool selection examples...]
```

## Related Documents

- [IOS_APP_ARCHITECTURE.md](IOS_APP_ARCHITECTURE.md) - ChatDomain in AppState
- [IOS_APP_MAP.md](IOS_APP_MAP.md) - Map visualization
- [IOS_APP_OFFLINE.md](IOS_APP_OFFLINE.md) - Offline infrastructure
