//
//  OfflineChatbotService.swift
//  FlyFunEuroAIP
//
//  Offline chatbot using on-device LLM (MediaPipe) and local tools.
//  Implements the same ChatbotService protocol as OnlineChatbotService.
//  Matches Android OfflineChatClient.kt implementation.
//

import Foundation
import OSLog
import RZUtilsSwift

/// Offline chatbot using on-device LLM and local tools
final class OfflineChatbotService: ChatbotService, @unchecked Sendable {
    
    // MARK: - Dependencies
    
    private let inferenceEngine: InferenceEngine
    private let toolDispatcher: LocalToolDispatcher
    private let modelManager: ModelManager
    
    // MARK: - Configuration
    
    private static let maxToolIterations = 5
    
    private static let systemPrompt = """
    You are FlyFun, an expert aviation planning assistant for European pilots.

    ## Available Tools
    Use JSON format to call tools: {"name": "tool_name", "arguments": {...}}

    - search_airports: Search airports by ICAO code, name, or city
      Parameters: {"query": "search term", "limit": 10}
    
    - get_airport_details: Get detailed information about a specific airport
      Parameters: {"icao": "LFPG"}
    
    - find_airports_near_route: Find airports along a flight route
      Parameters: {"from": "LFPG", "to": "EGLL", "max_distance_nm": 50}
    
    - find_airports_near_location: Find airports near a city or airport, optionally filter by notification
      Parameters: {"location_query": "EDRR", "max_distance_nm": 50, "max_hours_notice": 24}
    
    - get_border_crossing_airports: Get customs/border crossing airports
      Parameters: {"country": "FR"}
    
    - find_airports_by_notification: Find airports ONLY by notification (no location), filter by country
      Parameters: {"max_hours": 24, "country": "DE"}
    
    - list_rules_for_country: Get aviation rules for a country
      Parameters: {"country": "FR"}
    
    - compare_rules_between_countries: Compare rules between two countries
      Parameters: {"country1": "FR", "country2": "DE"}

    **CRITICAL - Tool Selection:**
    
    **LOCATION + NOTIFICATION - Use find_airports_near_location:**
    When user mentions a LOCATION (airport ICAO or city) WITH notification/hours:
    - "Airports near EDRR with less than 24h notice" → {"name": "find_airports_near_location", "arguments": {"location_query": "EDRR", "max_hours_notice": 24}}
    - "Airports near Paris with 24h notice" → {"name": "find_airports_near_location", "arguments": {"location_query": "Paris", "max_hours_notice": 24}}
    
    **NOTIFICATION ONLY (no location) - Use find_airports_by_notification:**
    - "Airports with less than 24h notice in Germany" → {"name": "find_airports_by_notification", "arguments": {"max_hours": 24, "country": "DE"}}
    
    **ROUTE QUERIES - Use find_airports_near_route:**
    - "Airports between EGLL and LFPG" → {"name": "find_airports_near_route", "arguments": {"from": "EGLL", "to": "LFPG"}}
    
    **LOCATION ONLY - Use find_airports_near_location:**
    - "Airports near Paris" → {"name": "find_airports_near_location", "arguments": {"location_query": "Paris"}}

    After receiving tool results, provide a helpful answer based on the data.
    Be concise and practical. Focus on information relevant to GA pilots.
    """
    
    // MARK: - Init
    
    init(inferenceEngine: InferenceEngine, toolDispatcher: LocalToolDispatcher, modelManager: ModelManager) {
        self.inferenceEngine = inferenceEngine
        self.toolDispatcher = toolDispatcher
        self.modelManager = modelManager
    }
    
    // MARK: - ChatbotService
    
    func sendMessage(
        _ message: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await processChat(message: message, history: history, continuation: continuation)
                } catch {
                    Logger.app.error("Offline chat error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func isAvailable() async -> Bool {
        // Available if model is loaded or can be loaded
        if inferenceEngine.isLoaded {
            return true
        }
        
        // Check if model file exists
        return modelManager.isModelAvailable
    }
    
    // MARK: - Private
    
    private func processChat(
        message: String,
        history: [ChatMessage],
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws {
        // Immediately show thinking indicator
        continuation.yield(.thinking(content: "Starting..."))
        
        // Ensure model is loaded
        if !inferenceEngine.isLoaded {
            let modelPath = modelManager.modelPath
            continuation.yield(.thinking(content: "Loading AI model (this may take a moment)..."))
            try await inferenceEngine.loadModel(at: modelPath)
            continuation.yield(.thinking(content: "Model loaded. Generating response..."))
        } else {
            continuation.yield(.thinking(content: "Generating response..."))
        }
        
        // Build prompt with system instructions, history, and current message
        let prompt = buildPrompt(message: message, history: history)
        
        Logger.app.info("Sending prompt to LLM (\(prompt.count) chars)")
        
        // Generate initial response
        var response = try await inferenceEngine.generate(prompt: prompt)
        continuation.yield(.thinking(content: "Analyzing response..."))
        
        // Track accumulated content for progressive streaming
        var toolSections: [String] = []
        
        // Tool-calling loop
        var toolIteration = 0
        while let toolCall = toolDispatcher.parseToolCall(from: response),
              toolIteration < Self.maxToolIterations {
            
            toolIteration += 1
            Logger.app.info("Tool call \(toolIteration): \(toolCall.name)")
            
            // Emit toolCallStart event
            continuation.yield(.toolCallStart(name: toolCall.name, arguments: toolCall.arguments))
            
            // Format arguments for display (one per line for clarity)
            let argsFormatted = toolCall.arguments.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
            
            // Build tool header
            let toolHeader = "🔧 **Tool:** \(toolCall.name)\n\n**Arguments:**\n\(argsFormatted)"
            
            // Show executing state
            toolSections.append(toolHeader + "\n\n**Executing...**")
            let executingContent = toolSections.joined(separator: "\n\n━━━━━━━━━━\n\n")
            continuation.yield(.message(content: executingContent))
            
            // Execute tool
            let toolResult = await toolDispatcher.dispatch(request: toolCall)
            
            // For UI display, show truncated preview if result is long
            let maxPreviewLength = 500
            let previewResult = toolResult.value.count > maxPreviewLength
                ? String(toolResult.value.prefix(maxPreviewLength)) + "\n... (truncated, see answer below)"
                : toolResult.value
            
            // Update last section with preview (replace last entry in array)
            toolSections[toolSections.count - 1] = toolHeader + "\n\n**Result:**\n\(previewResult)"
            let resultContent = toolSections.joined(separator: "\n\n━━━━━━━━━━\n\n")
            continuation.yield(.message(content: resultContent))
            
            // Emit toolCallEnd event
            let resultDict: [String: Any] = ["result": toolResult.value]
            continuation.yield(.toolCallEnd(name: toolCall.name, result: ToolResult(from: resultDict)))
            
            // Emit visualization for map plotting (like online version)
            if let visualization = buildVisualization(for: toolCall, result: toolResult) {
                continuation.yield(.uiPayload(visualization))
            }
            
            // For listing tools, use tool result directly (fast)
            // For rules/analysis tools, use LLM to summarize with truncated input
            let directUseTools = ["find_airports_near_location", "find_airports_near_route", 
                               "find_airports_by_notification", "get_border_crossing_airports", 
                               "search_airports", "get_airport_details", "get_airport_runways"]
            
            let llmSummarizeTools = ["list_rules_for_country", "compare_rules_between_countries"]
            
            if directUseTools.contains(toolCall.name) {
                // Use tool result directly as the answer
                response = toolResult.value
            } else if llmSummarizeTools.contains(toolCall.name) {
                // For rules, truncate input to fit token limit and let LLM summarize
                let maxLLMInput = 2000 // Leave room for prompt + output
                let truncatedResult = toolResult.value.count > maxLLMInput
                    ? String(toolResult.value.prefix(maxLLMInput)) + "\n... [data truncated for processing]"
                    : toolResult.value
                
                let followUpPrompt = buildFollowUpPrompt(
                    originalMessage: message,
                    toolCall: toolCall,
                    toolResult: truncatedResult
                )
                
                continuation.yield(.thinking(content: "Summarizing rules..."))
                response = try await inferenceEngine.generate(prompt: followUpPrompt)
            } else {
                // Build follow-up prompt with tool result for analysis
                let followUpPrompt = buildFollowUpPrompt(
                    originalMessage: message,
                    toolCall: toolCall,
                    toolResult: toolResult.value
                )
                
                // Show "Generating..." while waiting
                continuation.yield(.thinking(content: "Analyzing results..."))
                
                // Generate response with tool result
                response = try await inferenceEngine.generate(prompt: followUpPrompt)
            }
        }
        
        // Build final content from tool sections + answer
        var finalContent = ""
        if !toolSections.isEmpty {
            finalContent = toolSections.joined(separator: "\n\n━━━━━━━━━━\n\n")
            finalContent += "\n\n━━━━━━━━━━\n\n💬 **Answer:**\n\n"
        }
        finalContent += response
        
        // Yield final response
        continuation.yield(.message(content: finalContent))
        continuation.yield(.done(sessionId: nil, tokens: nil))
        continuation.finish()
    }
    
    private func buildPrompt(message: String, history: [ChatMessage]) -> String {
        // For now, ignore history to ensure each question triggers appropriate tool call
        // TODO: Implement smarter history handling that doesn't confuse tool selection
        var prompt = Self.systemPrompt + "\n\n"
        prompt += "User: \(message)\nAssistant:"
        return prompt
    }
    
    private func buildFollowUpPrompt(
        originalMessage: String,
        toolCall: LocalToolDispatcher.ToolCallRequest,
        toolResult: String
    ) -> String {
        // Listing tools should preserve all data; analysis tools can let LLM summarize
        let listingTools = ["find_airports_near_location", "find_airports_near_route", 
                           "find_airports_by_notification", "get_border_crossing_airports", 
                           "search_airports", "get_airport_details", "get_airport_runways"]
        
        let shouldPreserveData = listingTools.contains(toolCall.name)
        
        if shouldPreserveData {
            return """
            User asked: \(originalMessage)
            
            Tool "\(toolCall.name)" returned:
            
            \(toolResult)
            
            Present the results above. Include ALL airports with ALL details (ICAO, name, notice hours, summary).
            Do NOT omit any entries. Keep the formatting similar to the tool output.
            
            Assistant:
            """
        } else {
            // Rules and comparison tools - let LLM analyze and summarize
            return """
            User asked: \(originalMessage)
            
            Tool "\(toolCall.name)" returned:
            
            \(toolResult)
            
            Based on these results, provide a helpful answer to the user's question.
            Highlight the key points that are most relevant to pilots.
            
            Assistant:
            """
        }
    }
    
    // MARK: - Visualization Builder
    
    /// Build a visualization payload from tool results for map plotting
    private func buildVisualization(
        for toolCall: LocalToolDispatcher.ToolCallRequest,
        result: LocalToolDispatcher.ToolResult
    ) -> ChatVisualizationPayload? {
        // Only create visualization for airport/location tools
        let visualizableTools = ["find_airports_near_location", "find_airports_near_route",
                                  "find_airports_by_notification", "get_border_crossing_airports",
                                  "search_airports", "get_airport_details"]
        
        guard visualizableTools.contains(toolCall.name) else { return nil }
        
        // Parse airports from the result text
        let airports = parseAirportsFromResult(result.value)
        guard !airports.isEmpty else { return nil }
        
        // Build visualization sub-dictionary first
        var visualization: [String: Any] = [
            "markers": airports
        ]
        
        // Add center point based on first airport
        if let firstAirport = airports.first,
           let lat = firstAirport["latitude"] as? Double,
           let lon = firstAirport["longitude"] as? Double {
            visualization["center"] = ["latitude": lat, "longitude": lon]
        }
        
        // For route queries, add route data
        if toolCall.name == "find_airports_near_route",
           let from = toolCall.arguments["from"] as? String,
           let to = toolCall.arguments["to"] as? String {
            // Find departure and destination in results
            let fromAirport = airports.first { ($0["icao"] as? String) == from }
            let toAirport = airports.first { ($0["icao"] as? String) == to }
            
            var routeDict: [String: Any] = [
                "departure": from,
                "destination": to
            ]
            
            if let fromLat = fromAirport?["latitude"] as? Double,
               let fromLon = fromAirport?["longitude"] as? Double {
                routeDict["from"] = ["icao": from, "lat": fromLat, "lon": fromLon]
            }
            if let toLat = toAirport?["latitude"] as? Double,
               let toLon = toAirport?["longitude"] as? Double {
                routeDict["to"] = ["icao": to, "lat": toLat, "lon": toLon]
            }
            
            visualization["route"] = routeDict
        }
        
        // Build final payload
        let vizDict: [String: Any] = [
            "kind": "list",
            "visualization": visualization
        ]
        
        return ChatVisualizationPayload(from: vizDict)
    }
    
    /// Parse airport data from tool result text
    /// Extracts ICAO codes and coordinates from the formatted output
    private func parseAirportsFromResult(_ resultText: String) -> [[String: Any]] {
        var airports: [[String: Any]] = []
        
        // Parse lines like: "EDDB (Berlin Brandenburg) - 52.3667°, 13.5033° - ..."
        // or: "1. EDDB (Berlin)"
        let lines = resultText.components(separatedBy: "\n")
        
        for line in lines {
            // Look for ICAO codes (4 uppercase letters)
            let pattern = "([A-Z]{4})\\s*\\(([^)]+)\\)"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                
                guard let icaoRange = Range(match.range(at: 1), in: line),
                      let nameRange = Range(match.range(at: 2), in: line) else { continue }
                
                let icao = String(line[icaoRange])
                let name = String(line[nameRange])
                
                // Try to extract coordinates
                var airport: [String: Any] = [
                    "icao": icao,
                    "name": name,
                    "style": "result"
                ]
                
                // Look for coordinates pattern: "52.3667°, 13.5033°" or similar
                let coordPattern = "(-?\\d+\\.\\d+)[°]?,?\\s*(-?\\d+\\.\\d+)[°]?"
                if let coordRegex = try? NSRegularExpression(pattern: coordPattern),
                   let coordMatch = coordRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    
                    if let latRange = Range(coordMatch.range(at: 1), in: line),
                       let lonRange = Range(coordMatch.range(at: 2), in: line),
                       let lat = Double(line[latRange]),
                       let lon = Double(line[lonRange]) {
                        airport["latitude"] = lat
                        airport["longitude"] = lon
                    }
                }
                
                // Only add airports with coordinates
                if airport["latitude"] != nil {
                    airports.append(airport)
                }
            }
        }
        
        return airports
    }
}
