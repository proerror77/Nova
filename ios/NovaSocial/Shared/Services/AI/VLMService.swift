import Foundation

// MARK: - VLM (Vision Language Model) Service
// Calls Nova's VLM API endpoints (/api/v2/vlm/*)
// Uses Google Cloud Vision for image analysis and automatic channel classification

@Observable
final class VLMService {
    static let shared = VLMService()

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Image Analysis API

    /// Analyze an image and get tag/channel suggestions
    /// - Parameters:
    ///   - imageUrl: CDN URL of the uploaded image
    ///   - includeChannels: Whether to include channel suggestions
    ///   - maxTags: Maximum number of tags to return
    /// - Returns: Analysis result with tags and optional channel suggestions
    @MainActor
    func analyzeImage(
        imageUrl: String,
        includeChannels: Bool = true,
        maxTags: Int = 15
    ) async throws -> VLMAnalysisResult {
        let request = VLMAnalyzeRequest(
            imageUrl: imageUrl,
            includeChannels: includeChannels,
            maxTags: maxTags
        )

        #if DEBUG
        print("[VLMService] Analyzing image: \(imageUrl)")
        #endif

        do {
            let response: VLMAnalyzeResponse = try await apiClient.request(
                endpoint: APIConfig.VLM.analyze,
                method: "POST",
                body: request
            )

            #if DEBUG
            print("[VLMService] Received \(response.tags.count) tags, \(response.channels?.count ?? 0) channels")
            print("[VLMService] Processing time: \(response.processingTimeMs)ms")
            #endif

            return VLMAnalysisResult(
                tags: response.tags.map { TagSuggestion(tag: $0.tag, confidence: $0.confidence, source: $0.source) },
                channels: response.channels?.map { ChannelSuggestion(id: $0.id, name: $0.name, slug: $0.slug, confidence: $0.confidence, matchedKeywords: $0.matchedKeywords) },
                processingTimeMs: response.processingTimeMs
            )
        } catch {
            #if DEBUG
            print("[VLMService] Error: \(error)")
            #endif
            throw VLMError.from(error)
        }
    }

    // MARK: - Post Tags API

    /// Get tags for a specific post
    /// - Parameter postId: The post ID
    /// - Returns: List of tags for the post
    @MainActor
    func getPostTags(postId: String) async throws -> [TagSuggestion] {
        #if DEBUG
        print("[VLMService] Getting tags for post: \(postId)")
        #endif

        do {
            let response: PostTagsResponse = try await apiClient.get(
                endpoint: APIConfig.VLM.getPostTags(postId)
            )

            return response.tags.map { TagSuggestion(tag: $0.tag, confidence: $0.confidence, source: $0.source) }
        } catch {
            #if DEBUG
            print("[VLMService] Error getting post tags: \(error)")
            #endif
            throw VLMError.from(error)
        }
    }

    /// Update tags and channels for a post
    /// - Parameters:
    ///   - postId: The post ID
    ///   - tags: Tags to set
    ///   - channelIds: Channel IDs to associate
    /// - Returns: Updated tags response
    @MainActor
    func updatePostTags(
        postId: String,
        tags: [String],
        channelIds: [String]
    ) async throws -> [TagSuggestion] {
        let request = UpdatePostTagsRequest(
            tags: tags,
            channelIds: channelIds
        )

        #if DEBUG
        print("[VLMService] Updating tags for post: \(postId)")
        print("[VLMService] Tags: \(tags)")
        print("[VLMService] Channels: \(channelIds)")
        #endif

        do {
            let response: PostTagsResponse = try await apiClient.request(
                endpoint: APIConfig.VLM.updatePostTags(postId),
                method: "PUT",
                body: request
            )

            return response.tags.map { TagSuggestion(tag: $0.tag, confidence: $0.confidence, source: $0.source) }
        } catch {
            #if DEBUG
            print("[VLMService] Error updating post tags: \(error)")
            #endif
            throw VLMError.from(error)
        }
    }
}

// MARK: - Request Models

private struct VLMAnalyzeRequest: Codable {
    let imageUrl: String
    let includeChannels: Bool
    let maxTags: Int

    enum CodingKeys: String, CodingKey {
        case imageUrl = "image_url"
        case includeChannels = "include_channels"
        case maxTags = "max_tags"
    }
}

private struct UpdatePostTagsRequest: Codable {
    let tags: [String]
    let channelIds: [String]

    enum CodingKeys: String, CodingKey {
        case tags
        case channelIds = "channel_ids"
    }
}

// MARK: - Response Models

private struct VLMAnalyzeResponse: Codable {
    let tags: [TagResponse]
    let channels: [ChannelResponse]?
    let processingTimeMs: Int

    enum CodingKeys: String, CodingKey {
        case tags
        case channels
        case processingTimeMs = "processing_time_ms"
    }
}

private struct TagResponse: Codable {
    let tag: String
    let confidence: Float
    let source: String
}

private struct ChannelResponse: Codable {
    let id: String
    let name: String
    let slug: String
    let confidence: Float
    let matchedKeywords: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case confidence
        case matchedKeywords = "matched_keywords"
    }
}

private struct PostTagsResponse: Codable {
    let postId: String
    let tags: [TagResponse]
    let channelIds: [String]?

    enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case tags
        case channelIds = "channel_ids"
    }
}

// MARK: - Public Models

/// A tag suggestion from VLM analysis
struct TagSuggestion: Identifiable, Hashable {
    let tag: String
    let confidence: Float
    let source: String

    var id: String { tag }

    /// Confidence as percentage string
    var confidencePercent: String {
        String(format: "%.0f%%", confidence * 100)
    }
}

/// A channel suggestion from VLM analysis
struct ChannelSuggestion: Identifiable {
    let id: String
    let name: String
    let slug: String
    let confidence: Float
    let matchedKeywords: [String]

    /// Confidence as percentage string
    var confidencePercent: String {
        String(format: "%.0f%%", confidence * 100)
    }
}

/// Result from VLM image analysis
struct VLMAnalysisResult {
    let tags: [TagSuggestion]
    let channels: [ChannelSuggestion]?
    let processingTimeMs: Int
}

// MARK: - Errors

enum VLMError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case serviceUnavailable(String)
    case notConfigured

    static func from(_ error: Error) -> VLMError {
        if let apiError = error as? APIError {
            switch apiError {
            case .serverError(let code, _):
                if code == 503 {
                    return .serviceUnavailable("VLM service is currently unavailable. Please try again later.")
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
        case .serviceUnavailable(let message):
            return message
        case .notConfigured:
            return "VLM service is not configured"
        }
    }
}
