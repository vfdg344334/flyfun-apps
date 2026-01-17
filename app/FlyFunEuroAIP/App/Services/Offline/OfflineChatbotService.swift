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

    - search_airports: Search airports by ICAO code, name, or country ONLY
      Parameters: {"query": "LFPG" or "Charles de Gaulle" or "France", "limit": 10}
      NOTE: Do NOT use for "near" or location-based queries
    
    - get_airport_details: Get detailed information about a specific airport
      Parameters: {"icao": "LFPG"}
    
    - find_airports_near_route: Find airports along a flight route
      Parameters: {"from": "London" or "EGLL", "to": "Paris" or "LFPG", "max_distance_nm": 50}
      NOTE: Accepts city names OR ICAO codes
    
    - find_airports_near_location: Find airports near a city or airport with optional filters
      Parameters: {
        "location_query": "London",
        "max_distance_nm": 50,
        "has_procedures": true,  // Has IFR/ILS approach procedures
        "has_hard_runway": true, // Has paved runway
        "has_ils": true,         // Has ILS approach
        "point_of_entry": true,  // Is customs/border crossing
        "has_avgas": true,       // Has AVGAS fuel
        "has_jet_a": true,       // Has Jet A fuel
        "country": "GB"          // Filter by country
      }
    
    - get_border_crossing_airports: Get customs/border crossing airports
      Parameters: {"country": "FR"}
    
    - find_airports_by_notification: Find airports by notification hours only
      Parameters: {"max_hours": 24, "country": "DE"}
    
    - list_rules_for_country: Get aviation rules for a country
      Parameters: {"country": "FR"}
    
    - compare_rules_between_countries: Compare rules between two countries
      Parameters: {"country1": "FR", "country2": "DE"}

    **CRITICAL - Tool Selection:**
    
    **ILS/PROCEDURES/FEATURES near a location - Use find_airports_near_location with filters:**
    - "Airports with ILS near London" → {"name": "find_airports_near_location", "arguments": {"location_query": "London", "has_procedures": true}}
    - "Airports with procedures near Paris" → {"name": "find_airports_near_location", "arguments": {"location_query": "Paris", "has_procedures": true}}
    - "Airports with hard runway near Rome" → {"name": "find_airports_near_location", "arguments": {"location_query": "Rome", "has_hard_runway": true}}
    - "Customs airports near Berlin" → {"name": "find_airports_near_location", "arguments": {"location_query": "Berlin", "point_of_entry": true}}
    - "Airports with AVGAS near London" → {"name": "find_airports_near_location", "arguments": {"location_query": "London", "has_avgas": true}}
    - "Airports with Jet A fuel near Paris" → {"name": "find_airports_near_location", "arguments": {"location_query": "Paris", "has_jet_a": true}}
    
    **LOCATION + NOTIFICATION - Use find_airports_near_location:**
    - "Airports near EDRR with less than 24h notice" → {"name": "find_airports_near_location", "arguments": {"location_query": "EDRR", "max_hours_notice": 24}}
    
    **NOTIFICATION ONLY (no location) - Use find_airports_by_notification:**
    - "Airports with less than 24h notice in Germany" → {"name": "find_airports_by_notification", "arguments": {"max_hours": 24, "country": "DE"}}
    
    **ROUTE QUERIES - Use find_airports_near_route (accepts city names or ICAO codes):**
    - "Plan a route from Bromley to Nice" → {"name": "find_airports_near_route", "arguments": {"from": "Bromley", "to": "Nice"}}
    - "Airports between London and Paris" → {"name": "find_airports_near_route", "arguments": {"from": "London", "to": "Paris"}}
    - "Airports between EGLL and LFPG" → {"name": "find_airports_near_route", "arguments": {"from": "EGLL", "to": "LFPG"}}
    
    **LOCATION ONLY (no filters) - Use find_airports_near_location:**
    - "Airports near Paris" → {"name": "find_airports_near_location", "arguments": {"location_query": "Paris"}}

    **NAME/CODE SEARCH ONLY - Use search_airports:**
    - "Tell me about EGLL" → {"name": "search_airports", "arguments": {"query": "EGLL"}}
    - "Airports in Germany" → {"name": "search_airports", "arguments": {"query": "Germany"}}

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
        
        // For route queries, add route data by parsing DEPARTURE/DESTINATION from output
        if toolCall.name == "find_airports_near_route" {
            // Parse DEPARTURE and DESTINATION from result text
            let (departureAirport, destinationAirport) = parseRouteEndpoints(from: result.value)
            
            var routeDict: [String: Any] = [:]
            
            if let dep = departureAirport {
                routeDict["departure"] = dep["icao"]
                if let lat = dep["latitude"] as? Double, let lon = dep["longitude"] as? Double {
                    routeDict["from"] = ["icao": dep["icao"] ?? "", "lat": lat, "lon": lon]
                }
            }
            
            if let dest = destinationAirport {
                routeDict["destination"] = dest["icao"]
                if let lat = dest["latitude"] as? Double, let lon = dest["longitude"] as? Double {
                    routeDict["to"] = ["icao": dest["icao"] ?? "", "lat": lat, "lon": lon]
                }
            }
            
            // Add route coordinates for the polyline
            if let depLat = departureAirport?["latitude"] as? Double,
               let depLon = departureAirport?["longitude"] as? Double,
               let destLat = destinationAirport?["latitude"] as? Double,
               let destLon = destinationAirport?["longitude"] as? Double {
                routeDict["coordinates"] = [
                    ["latitude": depLat, "longitude": depLon],
                    ["latitude": destLat, "longitude": destLon]
                ]
            }
            
            if !routeDict.isEmpty {
                visualization["route"] = routeDict
            }
        }
        
        // Build final payload
        let vizDict: [String: Any] = [
            "kind": "list",
            "visualization": visualization
        ]
        
        return ChatVisualizationPayload(from: vizDict)
    }
    
    /// Parse DEPARTURE and DESTINATION airports from route result text
    private func parseRouteEndpoints(from text: String) -> (departure: [String: Any]?, destination: [String: Any]?) {
        var departure: [String: Any]?
        var destination: [String: Any]?
        
        let lines = text.components(separatedBy: "\n")
        let pattern = "^(DEPARTURE|DESTINATION):\\s+([A-Z]{4})\\s+\\(([^)]+)\\)\\s+-\\s+(-?\\d+\\.\\d+)°?,\\s*(-?\\d+\\.\\d+)°?"
        
        for line in lines {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                
                guard let typeRange = Range(match.range(at: 1), in: line),
                      let icaoRange = Range(match.range(at: 2), in: line),
                      let nameRange = Range(match.range(at: 3), in: line),
                      let latRange = Range(match.range(at: 4), in: line),
                      let lonRange = Range(match.range(at: 5), in: line) else { continue }
                
                let type = String(line[typeRange])
                let icao = String(line[icaoRange])
                let name = String(line[nameRange])
                let lat = Double(line[latRange]) ?? 0
                let lon = Double(line[lonRange]) ?? 0
                
                let airport: [String: Any] = [
                    "icao": icao,
                    "name": name,
                    "latitude": lat,
                    "longitude": lon
                ]
                
                if type == "DEPARTURE" {
                    departure = airport
                } else if type == "DESTINATION" {
                    destination = airport
                }
            }
        }
        
        return (departure, destination)
    }
    
    /// Parse airport data from tool result text
    /// Extracts ICAO codes and coordinates from the formatted output
    private func parseAirportsFromResult(_ resultText: String) -> [[String: Any]] {
        var airports: [[String: Any]] = []
        
        // Parse lines in two formats:
        // 1. Old format: "EDDB (Berlin Brandenburg) - 52.3667°, 13.5033° - ..."
        // 2. New format: "- ICAO: EGLC (51.5053°, -0.0553°)"
        let lines = resultText.components(separatedBy: "\n")
        
        var currentAirportName: String?
        
        for line in lines {
            // Check for numbered airport name: "1. London City Airport"
            if let regex = try? NSRegularExpression(pattern: "^\\d+\\.\\s+(.+)$"),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let nameRange = Range(match.range(at: 1), in: line) {
                currentAirportName = String(line[nameRange])
                continue
            }
            
            // Check for ICAO line with coordinates: "- ICAO: EGLC (51.5053°, -0.0553°)"
            if line.contains("ICAO:") {
                let icaoPattern = "ICAO:\\s*([A-Z]{4})\\s*\\((-?\\d+\\.\\d+)°?,\\s*(-?\\d+\\.\\d+)°?\\)"
                if let regex = try? NSRegularExpression(pattern: icaoPattern),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    
                    guard let icaoRange = Range(match.range(at: 1), in: line),
                          let latRange = Range(match.range(at: 2), in: line),
                          let lonRange = Range(match.range(at: 3), in: line) else { continue }
                    
                    let icao = String(line[icaoRange])
                    if let lat = Double(line[latRange]),
                       let lon = Double(line[lonRange]) {
                        let airport: [String: Any] = [
                            "icao": icao,
                            "name": currentAirportName ?? icao,
                            "latitude": lat,
                            "longitude": lon,
                            "style": "result"
                        ]
                        airports.append(airport)
                    }
                }
                continue
            }
            
            // Fallback: Old format "ICAO (Name) - lat°, lon°"
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
