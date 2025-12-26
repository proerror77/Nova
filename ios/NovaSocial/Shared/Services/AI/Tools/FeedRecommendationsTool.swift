import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Feed Recommendations Tool Arguments

/// Arguments for the feed recommendations tool
@available(iOS 26.0, *)
@Generable
struct FeedRecommendationsArguments: Sendable {
    @Guide(description: "Type of recommendations to get: creators, posts, or channels")
    var recommendationType: String

    @Guide(description: "Number of recommendations to return, between 1 and 10. Default is 5.")
    var limit: Int?
}

// MARK: - Feed Recommendations Tool

/// Tool for getting personalized recommendations from the feed
@available(iOS 26.0, *)
struct FeedRecommendationsTool: Tool {

    // MARK: - Tool Protocol

    let name = "get_recommendations"
    let description = """
        Get personalized recommendations for creators to follow, posts to engage with, or channels to join.
        Use this tool when the user asks for suggestions, wants to discover new content or creators,
        or needs help finding interesting things on ICERED.
        Returns a list of personalized recommendations based on the user's interests.
        """

    typealias Arguments = FeedRecommendationsArguments

    // MARK: - Properties

    private let feedService: FeedService

    // MARK: - Initialization

    init(feedService: FeedService) {
        self.feedService = feedService
    }

    // MARK: - Tool Execution

    func call(arguments: FeedRecommendationsArguments) async throws -> String {
        let limit = min(max(arguments.limit ?? 5, 1), 10)
        let type = arguments.recommendationType.lowercased().trimmingCharacters(in: .whitespaces)

        #if DEBUG
        print("[FeedRecommendationsTool] Getting \(limit) \(type) recommendations")
        #endif

        do {
            switch type {
            case "creators", "creator", "users", "people":
                return try await getCreatorRecommendations(limit: limit)

            case "channels", "channel", "communities":
                return try await getChannelRecommendations(limit: limit)

            case "posts", "post", "content":
                return try await getPostRecommendations(limit: limit)

            default:
                return """
                    Please specify what type of recommendations you'd like:
                    - "creators" for people to follow
                    - "channels" for communities to join
                    - "posts" for content to explore
                    """
            }

        } catch {
            #if DEBUG
            print("[FeedRecommendationsTool] Failed to get recommendations: \(error)")
            #endif
            return "Unable to fetch recommendations at the moment. Please try again later."
        }
    }

    // MARK: - Recommendation Fetchers

    private func getCreatorRecommendations(limit: Int) async throws -> String {
        let creators = try await feedService.getRecommendedCreators(limit: limit)

        guard !creators.isEmpty else {
            return "No creator recommendations available right now. Try exploring the app to build your interests!"
        }

        var output = "Recommended creators to follow:\n"

        for (index, creator) in creators.enumerated() {
            output += "\n\(index + 1). @\(creator.username)"
            if creator.isVerified {
                output += " (Verified)"
            }
            output += "\n   \(creator.displayName)"
            output += "\n   \(creator.followerCount) followers"

            if let reason = creator.reason, !reason.isEmpty {
                output += "\n   Why: \(reason)"
            }
        }

        return output
    }

    private func getChannelRecommendations(limit: Int) async throws -> String {
        let channels = try await feedService.getChannels(enabledOnly: true, limit: limit)

        guard !channels.isEmpty else {
            return "No channel recommendations available. Check back later for new communities!"
        }

        var output = "Recommended channels to join:\n"

        for (index, channel) in channels.enumerated() {
            output += "\n\(index + 1). \(channel.name)"
            if let description = channel.description, !description.isEmpty {
                output += "\n   \(description)"
            }
            if let subscriberCount = channel.subscriberCount, subscriberCount > 0 {
                output += "\n   \(subscriberCount) subscribers"
            }
        }

        return output
    }

    private func getPostRecommendations(limit: Int) async throws -> String {
        let feed = try await feedService.getExploreFeedWithDetails(limit: limit)

        guard !feed.posts.isEmpty else {
            return "No post recommendations available right now. Check back later!"
        }

        var output = "Recommended posts for you:\n"

        for (index, post) in feed.posts.enumerated() {
            let preview = String(post.content.prefix(80))
            output += "\n\(index + 1). By @\(post.authorName)"
            output += "\n   \"\(preview)\(post.content.count > 80 ? "..." : "")\""
            output += "\n   \(post.likeCount) likes, \(post.commentCount) comments"
        }

        return output
    }
}

#endif
