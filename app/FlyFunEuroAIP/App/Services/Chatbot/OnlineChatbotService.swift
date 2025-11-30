//
//  OnlineChatbotService.swift
//  FlyFunEuroAIP
//
//  Online chatbot service using the aviation agent API.
//  Streams responses via SSE for real-time updates.
//

import Foundation
import OSLog
import RZUtilsSwift

/// Protocol for chatbot services (online/offline)
protocol ChatbotService: Sendable {
    /// Send a message and stream the response
    func sendMessage(
        _ message: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<ChatEvent, Error>
    
    /// Check if the service is available
    func isAvailable() async -> Bool
}

/// Online chatbot using the aviation agent API
final class OnlineChatbotService: ChatbotService, @unchecked Sendable {
    
    // MARK: - Configuration
    
    private let baseURL: URL
    private let session: URLSession
    
    // MARK: - Init
    
    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }
    
    convenience init(baseURLString: String) throws {
        guard let url = URL(string: baseURLString) else {
            throw ChatbotError.invalidURL(baseURLString)
        }
        self.init(baseURL: url)
    }
    
    // MARK: - ChatbotService
    
    func sendMessage(
        _ message: String,
        history: [ChatMessage]
    ) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await streamChat(message: message, history: history, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func isAvailable() async -> Bool {
        // Check if the API is reachable
        let healthURL = baseURL.appendingPathComponent("api/health")
        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        
        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            Logger.app.warning("Chatbot API not available: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Private
    
    private func streamChat(
        message: String,
        history: [ChatMessage],
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws {
        // Build request
        let url = baseURL.appendingPathComponent("api/aviation-agent/chat/stream")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        
        // Build message history for API
        let chatMessages = history.map { msg -> [String: String] in
            ["role": msg.role == .user ? "user" : "assistant", "content": msg.content]
        } + [["role": "user", "content": message]]
        
        let body: [String: Any] = ["messages": chatMessages]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        Logger.app.info("Sending chat request to \(url.absoluteString)")
        
        // Stream response
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatbotError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw ChatbotError.httpError(httpResponse.statusCode)
        }
        
        // Parse SSE stream
        var currentEvent: String?
        var dataBuffer = ""
        
        for try await line in bytes.lines {
            if line.isEmpty {
                // Empty line = end of event
                if let event = currentEvent, !dataBuffer.isEmpty {
                    let parsedEvent = ChatEvent.parse(
                        event: event,
                        data: dataBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    continuation.yield(parsedEvent)
                    
                    // Check for terminal events
                    if case .done = parsedEvent {
                        continuation.finish()
                        return
                    }
                    if case .error(let msg) = parsedEvent {
                        continuation.finish(throwing: ChatbotError.serverError(msg))
                        return
                    }
                }
                currentEvent = nil
                dataBuffer = ""
            } else if line.hasPrefix("event:") {
                currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if !dataBuffer.isEmpty {
                    dataBuffer += "\n"
                }
                dataBuffer += data
            }
        }
        
        // Yield any remaining event
        if let event = currentEvent, !dataBuffer.isEmpty {
            let parsedEvent = ChatEvent.parse(event: event, data: dataBuffer)
            continuation.yield(parsedEvent)
        }
        
        continuation.finish()
    }
}

// MARK: - Errors

enum ChatbotError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case notAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid chatbot URL: \(url)"
        case .invalidResponse:
            return "Invalid response from chatbot"
        case .httpError(let code):
            return "Chatbot error (HTTP \(code))"
        case .serverError(let message):
            return "Chatbot error: \(message)"
        case .notAvailable:
            return "Chatbot is not available"
        }
    }
}

