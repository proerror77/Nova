import Foundation
import Combine

@MainActor
final class ExploreViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var posts: [Post] = []
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var isSearching = false
    @Published var searchResults: [User] = []
    @Published var errorMessage: String?
    @Published var showError = false

    // MARK: - Private Properties
    private let feedRepository: FeedRepository
    private let userRepository: UserRepository
    private var searchTask: Task<Void, Never>?

    // MARK: - Initialization
    init(
        feedRepository: FeedRepository = FeedRepository(),
        userRepository: UserRepository = UserRepository()
    ) {
        self.feedRepository = feedRepository
        self.userRepository = userRepository
    }

    // MARK: - Public Methods

    func loadExplorePosts() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            posts = try await feedRepository.loadExploreFeed(page: 1, limit: 30)
        } catch {
            showErrorMessage(error.localizedDescription)
        }

        isLoading = false
    }

    func searchUsers() {
        // Cancel previous search
        searchTask?.cancel()

        guard !searchText.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

            guard !Task.isCancelled else { return }

            do {
                let results = try await userRepository.searchUsers(
                    query: searchText,
                    limit: 20
                )

                if !Task.isCancelled {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                if !Task.isCancelled {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
        searchTask?.cancel()
    }

    func clearError() {
        errorMessage = nil
        showError = false
    }

    // MARK: - Private Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
}
