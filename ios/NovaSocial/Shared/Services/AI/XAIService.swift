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

    /// Live Search configuration
    struct SearchConfig {
        var enabled: Bool = false
        var sources: [String]? = nil  // "web", "news", "x", "rss"
        var fromDate: String? = nil   // "YYYY-MM-DD"
        var toDate: String? = nil     // "YYYY-MM-DD"

        static let `default` = SearchConfig()
        static let webSearch = SearchConfig(enabled: true, sources: ["web", "news"])
        static let xSearch = SearchConfig(enabled: true, sources: ["x"])
        static let allSources = SearchConfig(enabled: true, sources: ["web", "news", "x"])
    }

    struct ChatRequest: Codable {
        let message: String
        let model: String
        let systemPrompt: String?
        let temperature: Double
        let conversationHistory: [ChatMessage]?
        let enableSearch: Bool?
        let searchSources: [String]?
        let searchFromDate: String?
        let searchToDate: String?

        enum CodingKeys: String, CodingKey {
            case message, model, temperature
            case systemPrompt = "system_prompt"
            case conversationHistory = "conversation_history"
            case enableSearch = "enable_search"
            case searchSources = "search_sources"
            case searchFromDate = "search_from_date"
            case searchToDate = "search_to_date"
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

    // APIClient uses .convertFromSnakeCase - no CodingKeys needed for responses
    struct ErrorResponse: Codable {
        let status: String?
        let errorCode: String?
        let message: String?
        let messageZh: String?
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
            guard let url = URL(string: baseURL + APIConfig.XAI.status) else {
                #if DEBUG
                print("[XAIService] Invalid URL: \(baseURL + APIConfig.XAI.status)")
                #endif
                isAvailable = false
                return
            }

            // Create request with auth token
            var request = URLRequest(url: url)
            if let token = AuthenticationManager.shared.authToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)

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
    ///   - search: Live Search configuration for real-time data from web/news/X
    /// - Returns: AI response text
    func chat(
        _ message: String,
        systemPrompt: String? = nil,
        model: Model = .default,
        temperature: Double = 0.7,
        maintainHistory: Bool = true,
        search: SearchConfig = .default
    ) async throws -> String {
        // Check authentication first
        guard let token = AuthenticationManager.shared.authToken else {
            throw XAIError.authError("請先登入以使用 AI 功能")
        }

        guard let url = URL(string: baseURL + APIConfig.XAI.chat) else {
            throw XAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Build request body
        let chatRequest = ChatRequest(
            message: message,
            model: model.rawValue,
            systemPrompt: systemPrompt,
            temperature: temperature,
            conversationHistory: maintainHistory ? conversationHistory : nil,
            enableSearch: search.enabled ? true : nil,
            searchSources: search.enabled ? search.sources : nil,
            searchFromDate: search.enabled ? search.fromDate : nil,
            searchToDate: search.enabled ? search.toDate : nil
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
                // Check for specific error codes
                if errorResponse.errorCode == "QUOTA_EXCEEDED" {
                    throw XAIError.quotaExceeded(errorResponse.messageZh ?? errorResponse.message ?? "AI 服務配額已用完")
                } else if errorResponse.errorCode == "AUTH_ERROR" {
                    throw XAIError.authError(errorResponse.messageZh ?? errorResponse.message ?? "AI 服務認證失敗")
                }
                // Use Chinese message if available
                let errorMessage = errorResponse.messageZh ?? errorResponse.message ?? "Unknown error"
                throw XAIError.apiError(httpResponse.statusCode, errorMessage)
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
    case quotaExceeded(String)
    case authError(String)

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "X.AI service is currently unavailable"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid API response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(_, let message):
            return message
        case .emptyResponse:
            return "Empty API response"
        case .quotaExceeded(let message):
            return message
        case .authError(let message):
            return message
        }
    }

    /// Whether this error indicates a quota/billing issue
    var isQuotaError: Bool {
        if case .quotaExceeded = self { return true }
        return false
    }
}
