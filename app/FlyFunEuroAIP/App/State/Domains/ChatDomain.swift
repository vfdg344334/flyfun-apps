//
//  ChatDomain.swift
//  FlyFunEuroAIP
//
//  Created by Brice Rosenzweig on 28/11/2025.
//

import Foundation
import OSLog
import RZUtilsSwift

/// Domain: Chat messages and streaming state
/// This is a composed part of AppState, not a standalone ViewModel.
@Observable
@MainActor
final class ChatDomain {
    // MARK: - State
    var messages: [ChatMessage] = []
    var input: String = ""
    var isStreaming: Bool = false
    var currentThinking: String?
    var currentToolCall: String?
    var error: String?

    /// Offline mode toggle
    var isOfflineMode: Bool = false

    /// Follow-up query suggestions from last response
    var suggestedQueries: [SuggestedQuery] = []

    /// ID of the message currently being streamed (to update correct message)
    private var currentStreamingMessageId: UUID?

    /// Tools used during current streaming session
    private var toolsUsed: [String] = []
    
    // MARK: - Cross-Domain Callback
    /// Called when chat produces a visualization payload
    /// AppState wires this to AirportDomain.applyVisualization
    var onVisualization: ((ChatVisualizationPayload) -> Void)?
    
    /// Called when chat is cleared to reset map visualization
    /// AppState wires this to AirportDomain.clearVisualization
    var onClearVisualization: (() -> Void)?
    
    // MARK: - Dependencies
    private var onlineChatbotService: ChatbotService?
    private var offlineChatbotService: OfflineChatbotService?
    private var chatbotService: ChatbotService? {
        isOfflineMode ? offlineChatbotService : onlineChatbotService
    }
    
    // MARK: - Init
    
    init() {}
    
    /// Initialize with a chatbot service
    func configure(service: ChatbotService) {
        self.onlineChatbotService = service
    }
    
    /// Configure offline chatbot service
    func configureOffline(service: OfflineChatbotService) {
        self.offlineChatbotService = service
    }
    
    /// Toggle offline mode
    func setOfflineMode(_ offline: Bool) {
        isOfflineMode = offline
        Logger.app.info("Chat mode: \(offline ? "offline" : "online")")
    }
    
    // MARK: - Actions
    
    /// Send a message to the chatbot
    func send() async {
        let userMessage = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userMessage.isEmpty else { return }
        
        // Check if service is available
        guard let service = chatbotService else {
            Logger.app.warning("Chatbot service not configured")
            addOfflineResponse(for: userMessage)
            return
        }
        
        // Add user message
        messages.append(ChatMessage(role: .user, content: userMessage))
        input = ""
        error = nil
        
        isStreaming = true
        currentThinking = nil
        currentToolCall = nil
        currentStreamingMessageId = nil  // Reset for new stream
        toolsUsed = []  // Reset tools for new message
        suggestedQueries = []  // Clear previous suggestions
        
        Logger.app.info("Sending chat message: \(userMessage)")
        
        do {
            // Stream response from service
            var accumulatedContent = ""
            
            for try await event in service.sendMessage(userMessage, history: messages.dropLast()) {
                await handleEvent(event, accumulatedContent: &accumulatedContent)
            }
            
            // Ensure we have a final message
            if !accumulatedContent.isEmpty {
                finishStreaming(withContent: accumulatedContent)
            } else if !toolsUsed.isEmpty {
                // Backend didn't send text content, but tools were executed
                // Build a helpful fallback message
                let toolsList = toolsUsed.map { formatToolName($0) }.joined(separator: ", ")
                let fallbackContent = """
                ✅ I've executed the following: \(toolsList).
                
                Check the map to see the results. The visualization shows the airports/route based on your query.
                """
                updateLastAssistantMessage(fallbackContent)
                finishStreaming(withContent: fallbackContent)
            }
            
        } catch {
            Logger.app.error("Chat error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            messages.append(ChatMessage(
                role: .assistant,
                content: "Sorry, I encountered an error: \(error.localizedDescription)"
            ))
        }
        
        isStreaming = false
        currentThinking = nil
        currentToolCall = nil
    }
    
    /// Handle a streaming event
    private func handleEvent(_ event: ChatEvent, accumulatedContent: inout String) async {
        switch event {
        case .thinking(let content):
            currentThinking = content
            Logger.app.info("Thinking: \(content.prefix(100))...")
            
        case .thinkingDone:
            currentThinking = nil
            
        case .toolCallStart(let name, _):
            currentToolCall = name
            // Track all tools used (avoid duplicates)
            if !toolsUsed.contains(name) {
                toolsUsed.append(name)
            }
            Logger.app.info("Tool call: \(name)")
            
        case .toolCallEnd(let name, _):
            if currentToolCall == name {
                currentToolCall = nil
            }
            
        case .message(let content):
            // Append content for streaming (online API sends chunks)
            // Offline service sends complete content in one message, so append still works
            accumulatedContent += content
            updateLastAssistantMessage(accumulatedContent)
            
        case .uiPayload(let payload):
            Logger.app.info("Received visualization: \(payload.kind.rawValue)")
            // Capture suggested queries from payload
            if let queries = payload.suggestedQueries, !queries.isEmpty {
                suggestedQueries = queries
                Logger.app.info("Received \(queries.count) suggested queries")
            }
            onVisualization?(payload)
            
        case .plan(let plan):
            if let tool = plan.selectedTool {
                Logger.app.info("Plan: \(tool)")
            }
            
        case .finalAnswer:
            // Final state received - streaming is complete
            break
            
        case .done(let sessionId, let tokens):
            if let tokens = tokens {
                Logger.app.info("Chat complete. Tokens: \(tokens.total) (session: \(sessionId ?? "unknown"))")
            }
            
        case .error(let message):
            Logger.app.error("Chat error event: \(message)")
            error = message
            
        case .unknown(let event, let data):
            Logger.app.warning("Unknown chat event: \(event) with data: \(data.prefix(200))")
        }
    }
    
    /// Add a fallback response when offline
    private func addOfflineResponse(for message: String) {
        messages.append(ChatMessage(role: .user, content: message))
        input = ""
        
        // Simple offline response
        let response = """
        I'm currently offline and can't process complex queries. \
        Here are some things you can do:
        
        • Use the search bar to find airports by ICAO or name
        • Use filters to narrow down airports
        • Tap an airport on the map for details
        
        Once you're online, I can help with questions like:
        • "Find airports near London with ILS approaches"
        • "Show me border crossing airports in France"
        • "What procedures does EGLL have?"
        """
        
        messages.append(ChatMessage(role: .assistant, content: response))
    }
    
    /// Clear chat history
    func clear() {
        messages = []
        currentThinking = nil
        currentToolCall = nil
        error = nil
        suggestedQueries = []
        // Clear map visualization when chat is cleared
        onClearVisualization?()
    }

    /// Use a suggested query - sets input and optionally sends
    func useSuggestion(_ query: SuggestedQuery, autoSend: Bool = true) async {
        input = query.text
        suggestedQueries = []  // Clear suggestions after use
        if autoSend {
            await send()
        }
    }
    
    /// Add a message programmatically
    func addMessage(_ message: ChatMessage) {
        messages.append(message)
    }
    
    /// Update the current streaming assistant message (creates new if none)
    func updateLastAssistantMessage(_ content: String) {
        // If we have a tracked streaming message, update it
        if let messageId = currentStreamingMessageId,
           let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index] = ChatMessage(
                id: messageId,
                role: .assistant,
                content: content,
                isStreaming: true
            )
            return
        }
        
        // Otherwise, create a new message and track its ID
        let newMessage = ChatMessage(role: .assistant, content: content, isStreaming: true)
        currentStreamingMessageId = newMessage.id
        messages.append(newMessage)
    }
    
    /// Finish streaming for the last message
    func finishStreaming(withContent finalContent: String? = nil) {
        guard let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) else {
            Logger.app.warning("finishStreaming: No assistant message found")
            return
        }
        let message = messages[lastIndex]
        
        // Use provided content or fall back to existing message content
        let contentToUse = finalContent ?? message.content
        Logger.app.info("finishStreaming: content length = \(contentToUse.count) chars")
        
        // Create final message with tools used
        messages[lastIndex] = ChatMessage(
            id: message.id,  // Preserve the same ID
            role: message.role,
            content: contentToUse,
            isStreaming: false,
            toolsUsed: toolsUsed
        )
        isStreaming = false
        Logger.app.info("Finished streaming. Tools used: \(toolsUsed)")
    }
    
    /// Format a tool name for display
    private func formatToolName(_ toolName: String) -> String {
        switch toolName {
        case "find_airports_near_route": return "Route Search"
        case "find_airports_near_location": return "Nearby Airports"
        case "get_border_crossing_airports": return "Border Crossing Airports"
        case "search_airports": return "Airport Search"
        case "get_airport_details": return "Airport Details"
        case "find_airports_by_notification": return "Notification Search"
        case "list_rules_for_country": return "Country Rules"
        case "compare_rules_between_countries": return "Rules Comparison"
        default:
            return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    let isStreaming: Bool
    let toolsUsed: [String]
    
    enum Role: String, Sendable {
        case user
        case assistant
        case system
    }
    
    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        toolsUsed: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.toolsUsed = toolsUsed
    }
}

// MARK: - Array Extension for History

extension Array where Element == ChatMessage {
    /// Convert to format expected by API
    func toAPIFormat() -> [[String: String]] {
        map { msg in
            ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
        }
    }
}
