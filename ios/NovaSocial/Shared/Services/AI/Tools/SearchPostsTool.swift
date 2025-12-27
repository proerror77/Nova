import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Search Posts Tool Arguments

/// Arguments for the search posts tool
@available(iOS 26.0, *)
@Generable
struct SearchPostsArguments: Sendable {
    @Guide(description: "Search query keywords to find posts on ICERED")
    var query: String

    @Guide(description: "Maximum number of posts to return, between 1 and 20. Default is 10.")
    var limit: Int?

    @Guide(description: "Filter by content type: all, images, videos, text. Default is all.")
    var contentType: String?
}

// MARK: - Search Posts Tool

/// Tool for searching posts on the ICERED platform
@available(iOS 26.0, *)
struct SearchPostsTool: Tool {

    // MARK: - Tool Protocol

    let name = "search_posts"
    let description = """
        Search for posts on the ICERED social platform by keywords or topics.
        Use this tool when the user asks about specific content, wants to find posts about a topic,
        or needs to discover what people are posting about something.
        Returns a list of matching posts with their content, author, and engagement metrics.
        """

    typealias Arguments = SearchPostsArguments

    // MARK: - Properties

    private let searchService: SearchService

    // MARK: - Initialization

    init(searchService: SearchService) {
        self.searchService = searchService
    }

    // MARK: - Tool Execution

    func call(arguments: SearchPostsArguments) async throws -> String {
        // Validate and normalize arguments
        let limit = min(max(arguments.limit ?? 10, 1), 20)
        let query = arguments.query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            return "Please provide a search query to find posts."
        }

        #if DEBUG
        print("[SearchPostsTool] Searching for: '\(query)' (limit: \(limit))")
        #endif

        do {
            // Perform search
            let results = try await searchService.searchPosts(
                query: query,
                limit: limit
            )

            // Format results for the model
            return ToolResultFormatter.formatSearchResults(results, maxResults: limit)

        } catch {
            #if DEBUG
            print("[SearchPostsTool] Search failed: \(error)")
            #endif
            return "Unable to search posts at the moment. Please try again later."
        }
    }
}

#endif
