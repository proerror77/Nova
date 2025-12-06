import Foundation

// MARK: - Alice AI Service
// 调用 Chat Completions API 的服务

@Observable
final class AliceService {
    static let shared = AliceService()

    private let baseURL = "https://api.tu-zi.com/v1"
    private let apiKey = "your-api-key-here"  // TODO: 从配置或环境变量读取

    private init() {}

    // MARK: - Chat Completions API

    /// 发送消息到 AI 模型并获取回复
    /// - Parameters:
    ///   - messages: 对话历史消息数组
    ///   - model: 使用的模型名称
    /// - Returns: AI 的回复内容
    @MainActor
    func sendMessage(
        messages: [AIChatMessage],
        model: String = "gpt-4o-all"
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw AliceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: messages
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestBody)

        #if DEBUG
        print("[AliceService] Sending request to \(url)")
        print("[AliceService] Model: \(model)")
        print("[AliceService] Messages count: \(messages.count)")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliceError.invalidResponse
        }

        #if DEBUG
        print("[AliceService] Response status: \(httpResponse.statusCode)")
        #endif

        guard httpResponse.statusCode == 200 else {
            // 尝试解析错误信息
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw AliceError.apiError(errorResponse.error.message)
            }
            throw AliceError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let completionResponse = try decoder.decode(ChatCompletionResponse.self, from: data)

        guard let firstChoice = completionResponse.choices.first else {
            throw AliceError.emptyResponse
        }

        let content = firstChoice.message.content

        #if DEBUG
        print("[AliceService] Received response: \(content.prefix(100))...")
        #endif

        return content
    }
}

// MARK: - Data Models

/// AI Chat message structure
struct AIChatMessage: Codable, Sendable {
    let role: String  // "system", "user", or "assistant"
    let content: String

    static func system(_ content: String) -> AIChatMessage {
        AIChatMessage(role: "system", content: content)
    }

    static func user(_ content: String) -> AIChatMessage {
        AIChatMessage(role: "user", content: content)
    }

    static func assistant(_ content: String) -> AIChatMessage {
        AIChatMessage(role: "assistant", content: content)
    }
}

/// Chat completion request
struct ChatCompletionRequest: Codable, Sendable {
    let model: String
    let messages: [AIChatMessage]
}

/// Chat completion response
struct ChatCompletionResponse: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable, Sendable {
        let index: Int
        let message: AIChatMessage
        let finishReason: String?
    }

    struct Usage: Codable, Sendable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
    }
}

/// Error response
struct ErrorResponse: Codable, Sendable {
    let error: ErrorDetail

    struct ErrorDetail: Codable, Sendable {
        let message: String
        let type: String?
        let code: String?
    }
}

// MARK: - Errors

enum AliceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .emptyResponse:
            return "Empty response from server"
        }
    }
}
