import Foundation
import SwiftUI

// MARK: - Search View Model

@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    // MARK: - Temporary Model (TODO: Move to Shared/Models)

    enum SearchResult: Identifiable {
        case user(id: String, username: String, displayName: String)
        case post(id: String, content: String, author: String)
        case hashtag(tag: String, postCount: Int)

        var id: String {
            switch self {
            case .user(let id, _, _): return "user-\(id)"
            case .post(let id, _, _): return "post-\(id)"
            case .hashtag(let tag, _): return "tag-\(tag)"
            }
        }
    }

    // MARK: - Actions

    func performSearch() async {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        errorMessage = nil

        // TODO: Implement search from backend

        isSearching = false
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
    }
}
