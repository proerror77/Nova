import SwiftUI
import Combine

// MARK: - Search ViewModel

@MainActor
@Observable
class SearchViewModel {
    var searchText: String = ""
    var searchResults: [SearchResult] = []
    var recentSearches: [String] = []
    var selectedFilter: SearchFilter = .all
    var isSearching: Bool = false
    var isLoadingRecent: Bool = false
    var errorMessage: String?
    
    private let searchService = SearchService()
    private let friendsService = FriendsService()
    private let userService = UserService.shared
    private var searchTask: Task<Void, Never>?
    
    // MARK: - Search Methods
    
    /// Perform search with debouncing
    func performSearch() {
        // Cancel previous search task
        searchTask?.cancel()
        
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            errorMessage = nil
            return
        }
        
        // Debounce search by 300ms
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            
            guard !Task.isCancelled else { return }
            
            await executeSearch()
        }
    }
    
    /// Execute the actual search API call
    private func executeSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return
        }
        
        isSearching = true
        errorMessage = nil
        
        do {
            switch selectedFilter {
            case .all, .users:
                // 優先使用 FriendsService 搜索用戶 (與 AddFriendsView 相同)
                let users = try await friendsService.searchUsers(query: searchText, limit: 30)
                searchResults = users.map { user in
                    .user(
                        id: user.id,
                        username: user.username,
                        displayName: user.fullName,
                        avatarUrl: user.avatarUrl,
                        isVerified: user.isVerified ?? false
                    )
                }
                
                // 如果搜索返回空結果，嘗試直接用戶名查找
                if searchResults.isEmpty {
                    #if DEBUG
                    print("[SearchView] Search returned empty, trying fallback...")
                    #endif
                    await searchUserByUsernameFallback()
                }
                
            case .posts:
                searchResults = try await searchService.searchPosts(query: searchText, limit: 30)
            case .hashtags:
                searchResults = try await searchService.searchHashtags(query: searchText, limit: 30)
            }
            
            // Save to recent searches if we got results
            if !searchResults.isEmpty {
                searchService.saveRecentSearch(searchText)
            }
            
            #if DEBUG
            print("[SearchView] Search returned \(searchResults.count) results for '\(searchText)'")
            #endif
        } catch {
            // Handle specific error cases - try fallback for service errors
            if case APIError.serverError(let statusCode, _) = error,
               statusCode == 503 || statusCode == 502 || statusCode == 501 || statusCode == 401 {
                #if DEBUG
                print("[SearchView] Search service error (\(statusCode)), trying fallback...")
                #endif
                await searchUserByUsernameFallback()
            } else if case APIError.unauthorized = error {
                #if DEBUG
                print("[SearchView] Search unauthorized, trying fallback...")
                #endif
                await searchUserByUsernameFallback()
            } else {
                // 其他錯誤也嘗試 fallback
                #if DEBUG
                print("[SearchView] Search failed: \(error), trying fallback...")
                #endif
                await searchUserByUsernameFallback()
            }
        }
        
        isSearching = false
    }
    
    /// 備用搜索方案：當 search-service 不可用時，直接通過用戶名查找
    private func searchUserByUsernameFallback() async {
        do {
            // 嘗試通過精確用戶名查找
            let user = try await userService.getUserByUsername(searchText.lowercased())
            searchResults = [
                .user(
                    id: user.id,
                    username: user.username,
                    displayName: user.fullName,
                    avatarUrl: user.avatarUrl,
                    isVerified: user.isVerified ?? false
                )
            ]
            // 成功找到用戶，清除錯誤訊息
            errorMessage = nil
            searchService.saveRecentSearch(searchText)
            #if DEBUG
            print("[SearchView] Fallback search found user: \(user.username)")
            #endif
        } catch {
            // 如果找不到精確匹配，顯示空結果而非錯誤
            searchResults = []
            // 不顯示錯誤，用空結果表示沒找到
            errorMessage = nil
            #if DEBUG
            print("[SearchView] Fallback search: no user found for '\(searchText)'")
            #endif
        }
    }
    
    /// Load recent searches from local storage
    func loadRecentSearches() async {
        isLoadingRecent = true
        
        do {
            recentSearches = try await searchService.getRecentSearches(limit: 10)
        } catch {
            #if DEBUG
            print("[SearchView] Failed to load recent searches: \(error)")
            #endif
        }
        
        isLoadingRecent = false
    }
    
    /// Clear all recent searches
    func clearRecentSearches() {
        searchService.clearRecentSearches()
        recentSearches = []
    }
    
    /// Delete a specific recent search
    func deleteRecentSearch(_ query: String) {
        searchService.deleteRecentSearch(query)
        recentSearches.removeAll { $0 == query }
    }
    
    /// Use a recent search query
    func useRecentSearch(_ query: String) {
        searchText = query
        performSearch()
    }

    /// Save a query to recent searches
    func saveToRecentSearches(_ query: String) {
        searchService.saveRecentSearch(query)
    }
    
    /// Change filter and re-search if needed
    func changeFilter(_ filter: SearchFilter) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        
        if !searchText.isEmpty {
            Task {
                await executeSearch()
            }
        }
    }
}
