import Foundation
import CoreLocation

// MARK: - VLM (Vision Language Model) Service
// Calls Nova's VLM API endpoints (/api/v2/vlm/*)
// Uses Google Cloud Vision for image analysis and automatic channel classification
// Enhanced with location-aware tagging capabilities

@Observable
final class VLMService {
    static let shared = VLMService()

    private let apiClient = APIClient.shared
    private let geocoder = CLGeocoder()

    private init() {}

    // MARK: - Location Context

    /// Context information extracted from photo metadata for smarter tagging
    struct LocationContext: Sendable {
        let latitude: Double
        let longitude: Double
        let locationName: String?
        let timestamp: Date?

        /// Format date as season/time of day for tag generation
        var seasonContext: String? {
            guard let date = timestamp else { return nil }
            let calendar = Calendar.current
            let month = calendar.component(.month, from: date)
            let hour = calendar.component(.hour, from: date)

            var context: [String] = []

            // Season (Northern Hemisphere)
            switch month {
            case 3...5: context.append("spring")
            case 6...8: context.append("summer")
            case 9...11: context.append("autumn")
            default: context.append("winter")
            }

            // Time of day
            switch hour {
            case 5...8: context.append("morning")
            case 9...11: context.append("daytime")
            case 12...14: context.append("noon")
            case 15...17: context.append("afternoon")
            case 18...20: context.append("evening")
            case 21...23, 0...4: context.append("night")
            default: break
            }

            return context.joined(separator: ", ")
        }
    }

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

    // MARK: - Enhanced Image Analysis with Location

    /// Analyze an image with photo metadata for location-aware tagging
    /// - Parameters:
    ///   - imageUrl: CDN URL of the uploaded image
    ///   - metadata: Photo metadata containing location and timestamp
    ///   - includeChannels: Whether to include channel suggestions
    ///   - maxTags: Maximum number of tags to return
    /// - Returns: Analysis result with tags enhanced by location context
    @MainActor
    func analyzeImageWithMetadata(
        imageUrl: String,
        metadata: PhotoMetadata,
        includeChannels: Bool = true,
        maxTags: Int = 15
    ) async throws -> VLMAnalysisResult {
        // First, get the standard VLM analysis
        var result = try await analyzeImage(
            imageUrl: imageUrl,
            includeChannels: includeChannels,
            maxTags: maxTags
        )

        // If we have location metadata, add location-based tags
        if metadata.hasAnyMetadata {
            let locationTags = generateLocationTags(from: metadata)
            #if DEBUG
            print("[VLMService] Generated \(locationTags.count) location-based tags")
            #endif

            // Merge location tags with VLM tags (location tags have slightly lower confidence)
            result = VLMAnalysisResult(
                tags: result.tags + locationTags,
                channels: result.channels,
                processingTimeMs: result.processingTimeMs
            )
        }

        return result
    }

    /// Generate tags based on photo location and timestamp
    /// - Parameter metadata: Photo metadata
    /// - Returns: Array of location-based tag suggestions
    private func generateLocationTags(from metadata: PhotoMetadata) -> [TagSuggestion] {
        var tags: [TagSuggestion] = []

        // Add location name as tag (e.g., #Beijing, #Tokyo)
        if let locationName = metadata.locationName {
            // Extract city/country components
            let components = locationName.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for (index, component) in components.enumerated() {
                // Clean component for hashtag use (remove spaces, special chars)
                let cleanTag = component.replacingOccurrences(of: " ", with: "")
                    .filter { $0.isLetter || $0.isNumber }
                if !cleanTag.isEmpty {
                    // City gets higher confidence than country
                    let confidence: Float = index == 0 ? 0.75 : 0.65
                    tags.append(TagSuggestion(
                        tag: cleanTag,
                        confidence: confidence,
                        source: "location"
                    ))
                }
            }
        }

        // Add temporal tags based on creation date
        if let date = metadata.creationDate {
            let calendar = Calendar.current
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)

            // Season tag
            let seasonTag: String
            switch month {
            case 3...5: seasonTag = "Spring"
            case 6...8: seasonTag = "Summer"
            case 9...11: seasonTag = "Autumn"
            default: seasonTag = "Winter"
            }
            tags.append(TagSuggestion(tag: seasonTag, confidence: 0.6, source: "temporal"))

            // Year tag (for throwback posts)
            let currentYear = calendar.component(.year, from: Date())
            if year < currentYear {
                tags.append(TagSuggestion(tag: "Throwback", confidence: 0.5, source: "temporal"))
                tags.append(TagSuggestion(tag: "\(year)", confidence: 0.5, source: "temporal"))
            }
        }

        return tags
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

// APIClient uses .convertFromSnakeCase - no CodingKeys needed for responses
private struct VLMAnalyzeResponse: Codable {
    let tags: [TagResponse]
    let channels: [ChannelResponse]?
    let processingTimeMs: Int
}

private struct TagResponse: Codable {
    let tag: String
    let confidence: Float
    let source: String
}

// APIClient uses .convertFromSnakeCase - no CodingKeys needed for responses
private struct ChannelResponse: Codable {
    let id: String
    let name: String
    let slug: String
    let confidence: Float
    let matchedKeywords: [String]
}

// APIClient uses .convertFromSnakeCase - no CodingKeys needed for responses
private struct PostTagsResponse: Codable {
    let postId: String
    let tags: [TagResponse]
    let channelIds: [String]?
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
struct ChannelSuggestion: Codable, Identifiable {
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
