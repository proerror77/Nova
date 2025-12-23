import Foundation

// MARK: - X.AI Service (Backend Proxy)
/// Proxies requests through our backend to keep API keys secure
/// API calls: iOS App → Backend (graphql-gateway) → X.AI API

@Observable
@MainActor
final class XAIService {

    // MARK: - Singleton
    static let shared = XAIService()

    // MARK: - Configuration
    private var baseURL: String { APIConfig.current.baseURL }

    /// Available Grok models
    enum Model: String {
        case grok3 = "grok-3-latest"
        case grokBeta = "grok-beta"

        static let `default`: Model = .grok3
    }

    // MARK: - Properties
    private(set) var isAvailable: Bool = false
    private var conversationHistory: [ChatMessage] = []

    // MARK: - Request/Response Models

    struct ChatMessage: Codable {
        let role: String  // "user" or "assistant"
        let content: String
    }

    struct ChatRequest: Codable {
        let message: String
        let model: String
        let systemPrompt: String?
        let temperature: Double
        let conversationHistory: [ChatMessage]?

        enum CodingKeys: String, CodingKey {
            case message, model, temperature
            case systemPrompt = "system_prompt"
            case conversationHistory = "conversation_history"
        }
    }

    struct ChatResponse: Codable {
        let id: String
        let message: String
        let model: String
        let usage: UsageInfo?
    }

    struct UsageInfo: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    struct StatusResponse: Codable {
        let status: String
        let available: Bool
        let models: [String]?
    }

    struct ErrorResponse: Codable {
        let status: String?
        let message: String?
        let details: String?
    }

    // MARK: - Initialization

    private init() {
        Task {
            await checkAvailability()
        }
    }

    /// Check if X.AI service is available on backend
    func checkAvailability() async {
        do {
            let url = URL(string: baseURL + APIConfig.XAI.status)!
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isAvailable = false
                return
            }

            let statusResponse = try JSONDecoder().decode(StatusResponse.self, from: data)
            isAvailable = statusResponse.available

            #if DEBUG
            print("[XAIService] Status: \(statusResponse.status), Available: \(isAvailable)")
            #endif
        } catch {
            isAvailable = false
            #if DEBUG
            print("[XAIService] Failed to check availability: \(error)")
            #endif
        }
    }

    // MARK: - Chat API

    /// Send a chat message to Grok via backend proxy
    /// - Parameters:
    ///   - message: User message
    ///   - systemPrompt: Optional system prompt (uses default Alice prompt if nil)
    ///   - model: Which Grok model to use
    ///   - temperature: Randomness (0-2, default 0.7)
    ///   - maintainHistory: Whether to include conversation history
    /// - Returns: AI response text
    func chat(
        _ message: String,
        systemPrompt: String? = nil,
        model: Model = .default,
        temperature: Double = 0.7,
        maintainHistory: Bool = true
    ) async throws -> String {
        let url = URL(string: baseURL + APIConfig.XAI.chat)!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token if available
        if let token = AuthManager.shared.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build request body
        let chatRequest = ChatRequest(
            message: message,
            model: model.rawValue,
            systemPrompt: systemPrompt,
            temperature: temperature,
            conversationHistory: maintainHistory ? conversationHistory : nil
        )

        request.httpBody = try JSONEncoder().encode(chatRequest)

        #if DEBUG
        print("[XAIService] Sending chat request to \(model.rawValue)")
        print("[XAIService] Message: \(message.prefix(100))...")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw XAIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw XAIError.apiError(httpResponse.statusCode, errorResponse.message ?? "Unknown error")
            }
            throw XAIError.httpError(httpResponse.statusCode)
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)

        // Update conversation history
        if maintainHistory {
            conversationHistory.append(ChatMessage(role: "user", content: message))
            conversationHistory.append(ChatMessage(role: "assistant", content: chatResponse.message))

            // Keep last 20 messages to prevent context overflow
            if conversationHistory.count > 20 {
                conversationHistory = Array(conversationHistory.suffix(20))
            }
        }

        #if DEBUG
        print("[XAIService] Response: \(chatResponse.message.prefix(100))...")
        if let usage = chatResponse.usage {
            print("[XAIService] Tokens: \(usage.totalTokens)")
        }
        #endif

        return chatResponse.message
    }

    /// Stream chat response from Grok (simplified - returns full response)
    /// - Parameters:
    ///   - message: User message
    ///   - systemPrompt: Optional system prompt
    ///   - model: Which Grok model to use
    /// - Returns: Async stream of response chunks
    func streamChat(
        _ message: String,
        systemPrompt: String? = nil,
        model: Model = .default
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // For simplicity, use non-streaming endpoint and yield result
                    // TODO: Implement true SSE streaming when needed
                    let response = try await self.chat(
                        message,
                        systemPrompt: systemPrompt,
                        model: model,
                        maintainHistory: true
                    )
                    continuation.yield(response)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Clear conversation history
    func resetConversation() {
        conversationHistory.removeAll()
        #if DEBUG
        print("[XAIService] Conversation history cleared")
        #endif
    }
}

// MARK: - Errors

enum XAIError: LocalizedError {
    case serviceUnavailable
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "X.AI 服務目前無法使用"
        case .invalidURL:
            return "無效的 API URL"
        case .invalidResponse:
            return "無效的 API 回應"
        case .httpError(let code):
            return "HTTP 錯誤: \(code)"
        case .apiError(_, let message):
            return "API 錯誤: \(message)"
        case .emptyResponse:
            return "API 回應為空"
        }
    }
}
