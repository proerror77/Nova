import Foundation
import SwiftUI

// MARK: - Search View Model

@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var searchSuggestions: [SearchSuggestion] = []
    @Published var selectedFilter: SearchFilter = .all
    @Published var isSearching = false
    @Published var errorMessage: String?

    // MARK: - Services

    private let searchService = SearchService()

    // MARK: - Actions

    func performSearch() async {
        guard !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            searchResults = try await searchService.searchAll(
                query: searchQuery,
                filter: selectedFilter,
                limit: 30,
                offset: 0
            )

            // Save to recent searches
            searchService.saveRecentSearch(searchQuery)
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            searchResults = []
        }

        isSearching = false
    }

    func loadSuggestions() async {
        guard !searchQuery.isEmpty else {
            searchSuggestions = []
            return
        }

        do {
            searchSuggestions = try await searchService.getSuggestions(
                query: searchQuery,
                limit: 10
            )
        } catch {
            // Silent fail for suggestions - don't show error to user
            searchSuggestions = []
        }
    }

    func clearSearch() {
        searchQuery = ""
        searchResults = []
        searchSuggestions = []
    }

    func selectFilter(_ filter: SearchFilter) {
        selectedFilter = filter
        Task {
            await performSearch()
        }
    }
}
