import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Trending Topics Tool Arguments

/// Arguments for the trending topics tool
@available(iOS 26.0, *)
@Generable
struct TrendingTopicsArguments: Sendable {
    @Guide(description: "Number of trending topics to return, between 1 and 10. Default is 5.")
    var limit: Int?

    @Guide(description: "Optional category to filter by: fashion, travel, tech, food, sports, entertainment, or all. Default is all.")
    var category: String?
}

// MARK: - Trending Topics Tool

/// Tool for getting current trending topics and hashtags on Icered
@available(iOS 26.0, *)
struct TrendingTopicsTool: Tool {

    // MARK: - Tool Protocol

    let name = "get_trending_topics"
    let description = """
        Get the current trending topics and hashtags on Icered.
        Use this tool when the user asks what's trending, wants to know popular topics,
        or needs ideas for engaging content based on current trends.
        Returns a list of trending hashtags with their post counts.
        """

    typealias Arguments = TrendingTopicsArguments

    // MARK: - Properties

    private let searchService: SearchService

    // MARK: - Initialization

    init(searchService: SearchService) {
        self.searchService = searchService
    }

    // MARK: - Tool Execution

    func call(arguments: TrendingTopicsArguments) async throws -> String {
        let limit = min(max(arguments.limit ?? 5, 1), 10)
        let category = arguments.category?.lowercased()

        #if DEBUG
        print("[TrendingTopicsTool] Getting top \(limit) trending topics" +
              (category != nil ? " in category: \(category!)" : ""))
        #endif

        do {
            // Get trending topics
            let results = try await searchService.getTrendingTopics(limit: limit)

            guard !results.isEmpty else {
                return "No trending topics found at the moment. Check back later!"
            }

            // Format the results
            var output = "Current trending topics on Icered:\n"

            for (index, result) in results.enumerated() {
                if case .hashtag(let tag, let postCount) = result {
                    output += "\n\(index + 1). #\(tag)"
                    output += "\n   \(postCount) posts"

                    // Add engagement indicator
                    if postCount > 1000 {
                        output += " - Very popular"
                    } else if postCount > 500 {
                        output += " - Trending up"
                    } else if postCount > 100 {
                        output += " - Growing"
                    }
                }
            }

            output += "\n\nTip: Use these hashtags to increase your post visibility!"

            return output

        } catch {
            #if DEBUG
            print("[TrendingTopicsTool] Failed to get trending topics: \(error)")
            #endif
            return "Unable to fetch trending topics at the moment. Please try again later."
        }
    }
}

#endif
