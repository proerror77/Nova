import Foundation
import UIKit

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

    // MARK: - Post Enhancement API

    /// Enhance post content based on image analysis
    /// - Parameters:
    ///   - image: The image to analyze
    ///   - existingText: Optional existing post text to enhance
    ///   - includeTrending: Whether to include trending suggestions
    /// - Returns: Enhancement suggestions
    @MainActor
    func enhancePost(
        image: UIImage,
        existingText: String? = nil,
        includeTrending: Bool = true
    ) async throws -> AlicePostEnhancementSuggestion {
        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw AliceError.apiError("Failed to process image")
        }
        let base64Image = imageData.base64EncodedString()

        let request = AliceEnhanceRequest(
            imageBase64: base64Image,
            existingText: existingText,
            includeTrending: includeTrending
        )

        #if DEBUG
        print("[AliceService] Sending enhance request")
        print("[AliceService] Image size: \(imageData.count) bytes")
        print("[AliceService] Existing text: \(existingText ?? "none")")
        #endif

        do {
            let response: AliceEnhanceResponse = try await apiClient.request(
                endpoint: APIConfig.Alice.enhancePost,
                method: "POST",
                body: request
            )

            #if DEBUG
            print("[AliceService] Received enhancement suggestions")
            #endif

            return AlicePostEnhancementSuggestion(
                description: response.description,
                hashtags: response.hashtags,
                trendingTopics: response.trendingTopics,
                alternativeDescriptions: response.alternativeDescriptions ?? []
            )
        } catch {
            #if DEBUG
            print("[AliceService] Enhance error: \(error)")
            #endif
            throw AliceError.from(error)
        }
    }

    // MARK: - Convenience Methods for AIRouter

    /// Simple text message to Alice (convenience wrapper)
    /// - Parameter message: The message text
    /// - Returns: Alice response
    @MainActor
    func sendMessage(_ message: String) async throws -> AliceSimpleResponse {
        let response = try await sendMessage(
            messages: [.user(message)],
            model: "gpt-4o-all"
        )
        return AliceSimpleResponse(message: response)
    }

    /// Enhance post content without image (text-only)
    /// - Parameter content: The post content to enhance
    /// - Returns: Enhancement response
    @MainActor
    func enhancePost(content: String) async throws -> AliceTextEnhanceResponse {
        let request = AliceRequest(
            message: "Please enhance this social media post: \(content)",
            mode: "text"
        )

        #if DEBUG
        print("[AliceService] Sending text-only enhance request")
        #endif

        do {
            let response: AliceResponse = try await apiClient.request(
                endpoint: APIConfig.Alice.sendMessage,
                method: "POST",
                body: request
            )

            return AliceTextEnhanceResponse(enhanced_content: response.message)
        } catch {
            throw AliceError.from(error)
        }
    }

    /// Enhance post with image data
    /// - Parameters:
    ///   - content: Post text content
    ///   - imageData: Array of image data
    /// - Returns: Enhancement response
    @MainActor
    func enhancePostWithImage(
        content: String,
        imageData: [Data]
    ) async throws -> AliceTextEnhanceResponse {
        guard let firstImage = imageData.first,
              let image = UIImage(data: firstImage) else {
            // Fall back to text-only enhancement
            return try await enhancePost(content: content)
        }

        let suggestion = try await enhancePost(
            image: image,
            existingText: content,
            includeTrending: true
        )

        return AliceTextEnhanceResponse(enhanced_content: suggestion.fullSuggestion)
    }
}

// MARK: - Response Types for AIRouter

/// Simple response wrapper for AIRouter
struct AliceSimpleResponse {
    let message: String
}

/// Text enhancement response for AIRouter
struct AliceTextEnhanceResponse {
    let enhanced_content: String?
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

/// Alice enhance request format
private struct AliceEnhanceRequest: Codable {
    let imageBase64: String
    let existingText: String?
    let includeTrending: Bool

    enum CodingKeys: String, CodingKey {
        case imageBase64 = "image_base64"
        case existingText = "existing_text"
        case includeTrending = "include_trending"
    }
}

/// Alice enhance response format
/// Note: APIClient uses .convertFromSnakeCase - no CodingKeys needed for responses
private struct AliceEnhanceResponse: Codable {
    let description: String
    let hashtags: [String]
    let trendingTopics: [String]?
    let alternativeDescriptions: [String]?
}

/// Post enhancement suggestion result from Alice API
/// Used by EnhanceSuggestionView for displaying Alice's suggestions
struct PostEnhancementSuggestion {
    let description: String
    let hashtags: [String]
    let trendingTopics: [String]?
    let alternativeDescriptions: [String]

    /// Combined description with hashtags
    var fullSuggestion: String {
        var result = description
        if !hashtags.isEmpty {
            result += "\n\n" + hashtags.map { "#\($0)" }.joined(separator: " ")
        }
        return result
    }
}

/// Alias for backward compatibility
typealias AlicePostEnhancementSuggestion = PostEnhancementSuggestion

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