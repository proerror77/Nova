import Foundation

// MARK: - Alice AI Service
// Calls Nova's Alice API endpoints (/api/v2/alice/*)

@Observable
final class AliceService {
    static let shared = AliceService()

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Chat API

    /// Send message to Alice AI and get response
    /// - Parameters:
    ///   - messages: Conversation history
    ///   - model: Model name (currently unused by backend)
    /// - Returns: Alice's response content
    @MainActor
    func sendMessage(
        messages: [AIChatMessage],
        model: String = "gpt-4o-all"
    ) async throws -> String {
        // Convert chat history to single message (backend limitation)
        // Use the last user message as the content
        guard let lastUserMessage = messages.last(where: { $0.role == "user" }) else {
            throw AliceError.emptyMessage
        }

        let request = AliceRequest(
            message: lastUserMessage.content,
            mode: "text"
        )

        #if DEBUG
        print("[AliceService] Sending message to Alice API")
        print("[AliceService] Message: \(request.message)")
        #endif

        do {
            let response: AliceResponse = try await apiClient.request(
                endpoint: APIConfig.Alice.sendMessage,
                method: "POST",
                body: request
            )

            #if DEBUG
            print("[AliceService] Received response: \(response.message)")
            #endif

            return response.message
        } catch {
            #if DEBUG
            print("[AliceService] Error: \(error)")
            #endif
            throw AliceError.from(error)
        }
    }

    /// Check Alice service status
    @MainActor
    func checkStatus() async throws -> AliceStatus {
        #if DEBUG
        print("[AliceService] Checking Alice status")
        #endif

        let status: AliceStatus = try await apiClient.get(
            endpoint: APIConfig.Alice.getStatus
        )

        return status
    }
}

// MARK: - Data Models

/// AI Chat message structure (compatible with OpenAI format)
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

/// Alice API request format
private struct AliceRequest: Codable {
    let message: String
    let mode: String  // "text" or "voice"
}

/// Alice API response format
private struct AliceResponse: Codable {
    let message: String
    let id: String?
    let timestamp: Int?

    // Handle mock response format
    let status: String?
    let echo: String?
}

/// Alice service status
struct AliceStatus: Codable {
    let status: String
    let version: String
    let available: Bool
    let message: String?
}

// MARK: - Errors

enum AliceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case emptyResponse
    case emptyMessage
    case serviceUnavailable(String)

    static func from(_ error: Error) -> AliceError {
        if let apiError = error as? APIError {
            switch apiError {
            case .serverError(let code, _):
                if code == 503 {
                    return .serviceUnavailable("Alice AI service is currently unavailable. Please try again later.")
                }
                return .httpError(code)
            case .decodingError:
                return .invalidResponse
            default:
                return .apiError(error.localizedDescription)
            }
        }
        return .apiError(error.localizedDescription)
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return message
        case .emptyResponse:
            return "Empty response from server"
        case .emptyMessage:
            return "Please enter a message"
        case .serviceUnavailable(let message):
            return message
        }
    }
}