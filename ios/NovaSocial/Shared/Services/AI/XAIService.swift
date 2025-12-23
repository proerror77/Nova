import Foundation

// MARK: - X.AI Service
/// Direct integration with X.AI Grok API for text-based LLM interactions
/// API Documentation: https://docs.x.ai/api

@Observable
@MainActor
final class XAIService {

    // MARK: - Singleton
    static let shared = XAIService()

    // MARK: - Configuration
    private let baseURL = "https://api.x.ai/v1"
    private var apiKey: String { GrokVoiceConfig.apiKey }

    /// Available Grok models
    enum Model: String {
        case grok4 = "grok-4-latest"
        case grok3 = "grok-3-latest"
        case grokBeta = "grok-beta"

        static let `default`: Model = .grok4
    }

    // MARK: - Properties
    private(set) var isConfigured: Bool = false
    private var conversationHistory: [XAIChatMessage] = []

    // MARK: - Initialization

    private init() {
        validateConfiguration()
    }

    private func validateConfiguration() {
        isConfigured = GrokVoiceConfig.isConfigured
        #if DEBUG
        if isConfigured {
            print("[XAIService] ✅ API configured")
        } else {
            print("[XAIService] ⚠️ API not configured - please set XAI_API_KEY")
        }
        #endif
    }

    // MARK: - Chat API

    /// Send a chat message to Grok
    /// - Parameters:
    ///   - message: User message
    ///   - systemPrompt: Optional system prompt
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
        guard isConfigured else {
            throw XAIError.notConfigured
        }

        // Build messages array
        var messages: [XAIChatMessage] = []

        // Add system prompt
        let system = systemPrompt ?? XAIConfig.aliceSystemPrompt
        messages.append(XAIChatMessage(role: "system", content: system))

        // Add conversation history
        if maintainHistory {
            messages.append(contentsOf: conversationHistory)
        }

        // Add current user message
        let userMessage = XAIChatMessage(role: "user", content: message)
        messages.append(userMessage)

        // Create request
        let request = XAIChatRequest(
            model: model.rawValue,
            messages: messages,
            temperature: temperature,
            stream: false
        )

        #if DEBUG
        print("[XAIService] Sending chat request to \(model.rawValue)")
        print("[XAIService] Message: \(message.prefix(100))...")
        #endif

        // Execute request
        let response: XAIChatResponse = try await executeRequest(
            endpoint: "/chat/completions",
            body: request
        )

        guard let choice = response.choices.first,
              let content = choice.message.content else {
            throw XAIError.emptyResponse
        }

        // Update conversation history
        if maintainHistory {
            conversationHistory.append(userMessage)
            conversationHistory.append(XAIChatMessage(role: "assistant", content: content))

            // Keep last 20 messages to prevent context overflow
            if conversationHistory.count > 20 {
                conversationHistory = Array(conversationHistory.suffix(20))
            }
        }

        #if DEBUG
        print("[XAIService] Response: \(content.prefix(100))...")
        print("[XAIService] Tokens: \(response.usage?.totalTokens ?? 0)")
        #endif

        return content
    }

    /// Stream chat response from Grok
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
                guard self.isConfigured else {
                    continuation.finish(throwing: XAIError.notConfigured)
                    return
                }

                var messages: [XAIChatMessage] = []

                let system = systemPrompt ?? XAIConfig.aliceSystemPrompt
                messages.append(XAIChatMessage(role: "system", content: system))

                messages.append(contentsOf: self.conversationHistory)
                messages.append(XAIChatMessage(role: "user", content: message))

                let request = XAIChatRequest(
                    model: model.rawValue,
                    messages: messages,
                    temperature: 0.7,
                    stream: true
                )

                do {
                    let stream = try await self.executeStreamRequest(
                        endpoint: "/chat/completions",
                        body: request
                    )

                    var fullResponse = ""

                    for try await chunk in stream {
                        continuation.yield(chunk)
                        fullResponse += chunk
                    }

                    // Update history with full response
                    self.conversationHistory.append(XAIChatMessage(role: "user", content: message))
                    self.conversationHistory.append(XAIChatMessage(role: "assistant", content: fullResponse))

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

    // MARK: - Network Layer

    private func executeRequest<T: Encodable, R: Decodable>(
        endpoint: String,
        body: T
    ) async throws -> R {
        guard let url = URL(string: baseURL + endpoint) else {
            throw XAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw XAIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(XAIErrorResponse.self, from: data) {
                throw XAIError.apiError(httpResponse.statusCode, errorResponse.error.message)
            }
            throw XAIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(R.self, from: data)
    }

    private func executeStreamRequest<T: Encodable>(
        endpoint: String,
        body: T
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let url = URL(string: baseURL + endpoint) else {
            throw XAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw XAIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))

                            if jsonString == "[DONE]" {
                                continuation.finish()
                                return
                            }

                            if let data = jsonString.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(XAIStreamChunk.self, from: data),
                               let content = chunk.choices.first?.delta.content {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Configuration

enum XAIConfig {
    /// Alice AI system prompt for Grok
    static let aliceSystemPrompt = """
    你是 Alice，ICERED 社交平台的 AI 助理。

    你的特點：
    - 友善、有幫助、專業
    - 能夠用自然流暢的方式與用戶對話
    - 擅長提供社交媒體相關的建議
    - 可以幫助用戶創作貼文、回覆留言、分析趨勢

    請用繁體中文回應，除非用戶使用其他語言。
    保持回應簡潔有力，避免過於冗長。
    """
}

// MARK: - Request/Response Models

struct XAIChatMessage: Codable {
    let role: String  // "system", "user", "assistant"
    let content: String
}

struct XAIChatRequest: Codable {
    let model: String
    let messages: [XAIChatMessage]
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
    }
}

struct XAIChatResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [XAIChatChoice]
    let usage: XAIUsage?
}

struct XAIChatChoice: Codable {
    let index: Int
    let message: XAIChatMessageResponse
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct XAIChatMessageResponse: Codable {
    let role: String
    let content: String?
    let refusal: String?
}

struct XAIUsage: Codable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct XAIStreamChunk: Codable {
    let choices: [XAIStreamChoice]
}

struct XAIStreamChoice: Codable {
    let delta: XAIStreamDelta
}

struct XAIStreamDelta: Codable {
    let content: String?
}

struct XAIErrorResponse: Codable {
    let error: XAIAPIError
}

struct XAIAPIError: Codable {
    let message: String
    let type: String?
    let code: String?
}

// MARK: - Errors

enum XAIError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(Int, String)
    case emptyResponse
    case streamingError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "X.AI API 未配置，請設置 API Key"
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
        case .streamingError(let message):
            return "串流錯誤: \(message)"
        }
    }
}
