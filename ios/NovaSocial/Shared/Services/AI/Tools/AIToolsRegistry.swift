import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - AI Tools Registry

/// Central registry for managing AI tools that can access app data
@available(iOS 26.0, *)
@MainActor
final class AIToolsRegistry {

    // MARK: - Singleton

    static let shared = AIToolsRegistry()

    // MARK: - Dependencies

    private let searchService: SearchService
    private let feedService: FeedService

    // MARK: - Tool Instances

    #if canImport(FoundationModels)
    private(set) lazy var searchPostsTool = SearchPostsTool(searchService: searchService)
    private(set) lazy var getUserProfileTool = GetUserProfileTool(searchService: searchService)
    private(set) lazy var trendingTopicsTool = TrendingTopicsTool(searchService: searchService)
    private(set) lazy var feedRecommendationsTool = FeedRecommendationsTool(feedService: feedService)
    #endif

    // MARK: - Initialization

    private init() {
        self.searchService = SearchService()
        self.feedService = FeedService()
    }

    /// Initialize with custom services (for testing)
    init(searchService: SearchService, feedService: FeedService) {
        self.searchService = searchService
        self.feedService = feedService
    }

    // MARK: - Tool Collection

    #if canImport(FoundationModels)
    /// All available tools for session configuration
    var allTools: [any Tool] {
        [
            searchPostsTool,
            getUserProfileTool,
            trendingTopicsTool,
            feedRecommendationsTool
        ]
    }

    /// Get tools by category
    func tools(for category: ToolCategory) -> [any Tool] {
        switch category {
        case .search:
            return [searchPostsTool, getUserProfileTool]
        case .discovery:
            return [trendingTopicsTool, feedRecommendationsTool]
        case .all:
            return allTools
        }
    }
    #endif

    // MARK: - Tool Categories

    enum ToolCategory {
        case search      // Search-related tools
        case discovery   // Content discovery tools
        case all         // All available tools
    }
}

// MARK: - Tool Error Types

/// Errors that can occur during tool execution
enum AIToolError: LocalizedError {
    case executionFailed(toolName: String, reason: String)
    case serviceUnavailable(String)
    case invalidArguments(String)
    case networkRequired
    case rateLimited
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .executionFailed(let toolName, let reason):
            return "Tool '\(toolName)' failed: \(reason)"
        case .serviceUnavailable(let service):
            return "\(service) service is currently unavailable"
        case .invalidArguments(let details):
            return "Invalid arguments: \(details)"
        case .networkRequired:
            return "Network connection required for this operation"
        case .rateLimited:
            return "Too many requests, please try again later"
        case .notFound(let item):
            return "\(item) not found"
        }
    }
}

// MARK: - Tool Result Formatting

/// Helper for formatting tool results for the model
struct ToolResultFormatter {

    /// Format search results into a readable string
    static func formatSearchResults(_ results: [SearchResult], maxResults: Int = 10) -> String {
        guard !results.isEmpty else {
            return "No results found."
        }

        var output = "Found \(results.count) result(s):\n"

        for (index, result) in results.prefix(maxResults).enumerated() {
            switch result {
            case .user(let id, let username, let displayName, _, let isVerified):
                let verified = isVerified ? " (Verified)" : ""
                output += "\n\(index + 1). User: @\(username)\(verified)"
                output += "\n   Name: \(displayName)"

            case .post(let id, let content, let author, let createdAt, let likeCount):
                let preview = String(content.prefix(100))
                output += "\n\(index + 1). Post by @\(author) (\(likeCount) likes)"
                output += "\n   \"\(preview)\(content.count > 100 ? "..." : "")\""

            case .hashtag(let tag, let postCount):
                output += "\n\(index + 1). #\(tag) - \(postCount) posts"
            }
        }

        if results.count > maxResults {
            output += "\n\n... and \(results.count - maxResults) more results."
        }

        return output
    }

    /// Format trending topics into a readable string
    static func formatTrendingTopics(_ topics: [SearchResult], limit: Int = 10) -> String {
        guard !topics.isEmpty else {
            return "No trending topics at the moment."
        }

        var output = "Current trending topics on ICERED:\n"

        for (index, topic) in topics.prefix(limit).enumerated() {
            if case .hashtag(let tag, let postCount) = topic {
                output += "\n\(index + 1). #\(tag) - \(postCount) posts"
            }
        }

        return output
    }
}
