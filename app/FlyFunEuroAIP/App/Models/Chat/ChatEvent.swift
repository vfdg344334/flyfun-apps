//
//  ChatEvent.swift
//  FlyFunEuroAIP
//
//  SSE event types from the aviation agent API.
//  Matches the events from /api/aviation-agent/chat/stream
//

import Foundation

/// SSE events from the aviation agent streaming API
enum ChatEvent: Sendable {
    /// Planner selected a tool
    case plan(PlanData)
    
    /// Planning reasoning/thinking
    case thinking(content: String)
    
    /// Tool execution starting
    case toolCallStart(name: String, arguments: [String: Any])
    
    /// Tool execution completed
    case toolCallEnd(name: String, result: ToolResult)
    
    /// Streaming message content (character by character)
    case message(content: String)
    
    /// Thinking phase complete
    case thinkingDone
    
    /// Visualization data for the map
    case uiPayload(ChatVisualizationPayload)
    
    /// Final answer with complete state
    case finalAnswer(state: [String: Any])
    
    /// Stream complete
    case done(sessionId: String?, tokens: TokenUsage?)
    
    /// Error occurred
    case error(message: String)
    
    /// Unknown event type
    case unknown(event: String, data: String)
}

// MARK: - Plan Data

struct PlanData: Codable, Sendable {
    let selectedTool: String?
    let arguments: [String: AnyCodableValue]?
    let planningReasoning: String?
    
    enum CodingKeys: String, CodingKey {
        case selectedTool = "selected_tool"
        case arguments
        case planningReasoning = "planning_reasoning"
    }
}

// MARK: - Tool Result

struct ToolResult: Sendable {
    let airports: [AirportSummary]?
    let visualization: VisualizationData?
    let raw: [String: Any]
    
    init(from dict: [String: Any]) {
        self.raw = dict
        
        // Parse airports if present
        if let airportsData = dict["airports"] as? [[String: Any]] {
            self.airports = airportsData.compactMap { AirportSummary(from: $0) }
        } else {
            self.airports = nil
        }
        
        // Parse visualization if present
        if let vizData = dict["visualization"] as? [String: Any] {
            self.visualization = VisualizationData(from: vizData)
        } else {
            self.visualization = nil
        }
    }
}

// MARK: - Airport Summary (from tool results)

struct AirportSummary: Sendable {
    let ident: String
    let name: String?
    let latitude: Double?
    let longitude: Double?
    let country: String?
    
    init?(from dict: [String: Any]) {
        guard let ident = dict["ident"] as? String ?? dict["icao"] as? String else {
            return nil
        }
        self.ident = ident
        self.name = dict["name"] as? String
        self.latitude = dict["latitude_deg"] as? Double ?? dict["latitude"] as? Double
        self.longitude = dict["longitude_deg"] as? Double ?? dict["longitude"] as? Double
        self.country = dict["iso_country"] as? String ?? dict["country"] as? String
    }
}

// MARK: - Token Usage

struct TokenUsage: Codable, Sendable {
    let input: Int
    let output: Int
    let total: Int
}

// MARK: - Event Parsing

extension ChatEvent {
    /// Parse an SSE event from event name and JSON data
    static func parse(event: String, data: String) -> ChatEvent {
        guard let jsonData = data.data(using: .utf8) else {
            return .unknown(event: event, data: data)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            switch event {
            case "plan":
                let plan = try decoder.decode(PlanData.self, from: jsonData)
                return .plan(plan)
                
            case "thinking":
                if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let content = dict["content"] as? String {
                    return .thinking(content: content)
                }
                return .unknown(event: event, data: data)
                
            case "tool_call_start":
                if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let name = dict["name"] as? String {
                    let args = dict["arguments"] as? [String: Any] ?? [:]
                    return .toolCallStart(name: name, arguments: args)
                }
                return .unknown(event: event, data: data)
                
            case "tool_call_end":
                if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let name = dict["name"] as? String,
                   let result = dict["result"] as? [String: Any] {
                    return .toolCallEnd(name: name, result: ToolResult(from: result))
                }
                return .unknown(event: event, data: data)
                
            case "message", "content", "answer", "response", "text_chunk":
                // Support multiple event names and JSON field names for text content
                if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    // Try multiple field names for the text content
                    if let content = dict["content"] as? String {
                        return .message(content: content)
                    } else if let text = dict["text"] as? String {
                        return .message(content: text)
                    } else if let response = dict["response"] as? String {
                        return .message(content: response)
                    } else if let chunk = dict["chunk"] as? String {
                        return .message(content: chunk)
                    }
                }
                // Maybe it's just raw text, not JSON
                if !data.hasPrefix("{") && !data.hasPrefix("[") && !data.isEmpty {
                    return .message(content: data)
                }
                return .unknown(event: event, data: data)
                
            case "thinking_done":
                return .thinkingDone
                
            case "ui_payload":
                if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    return .uiPayload(ChatVisualizationPayload(from: dict))
                }
                return .unknown(event: event, data: data)
                
            case "final_answer":
                if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let state = dict["state"] as? [String: Any] {
                    return .finalAnswer(state: state)
                }
                return .unknown(event: event, data: data)
                
            case "done":
                if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    let sessionId = dict["session_id"] as? String
                    var tokens: TokenUsage? = nil
                    if let tokensDict = dict["tokens"] as? [String: Any] {
                        tokens = TokenUsage(
                            input: tokensDict["input"] as? Int ?? 0,
                            output: tokensDict["output"] as? Int ?? 0,
                            total: tokensDict["total"] as? Int ?? 0
                        )
                    }
                    return .done(sessionId: sessionId, tokens: tokens)
                }
                return .unknown(event: event, data: data)
                
            case "error":
                if let dict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let message = dict["message"] as? String {
                    return .error(message: message)
                }
                return .unknown(event: event, data: data)
                
            default:
                return .unknown(event: event, data: data)
            }
        } catch {
            return .unknown(event: event, data: data)
        }
    }
}

// MARK: - Helper for Any Codable

/// Wrapper for encoding/decoding arbitrary JSON values in Codable structs
enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dict)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodableValue")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .dictionary(let v): try container.encode(v)
        }
    }
}

