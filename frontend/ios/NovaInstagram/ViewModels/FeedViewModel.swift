import SwiftUI
import Combine

// MARK: - View State Enum

enum ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(Error)
    case empty

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var data: T? {
        if case .loaded(let data) = self { return data }
        return nil
    }

    var error: Error? {
        if case .error(let error) = self { return error }
        return nil
    }
}

// MARK: - Feed ViewModel

@MainActor
class FeedViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var state: ViewState<[PostModel]> = .idle
    @Published private(set) var isRefreshing = false
    @Published private(set) var isLoadingMore = false

    // MARK: - Private Properties

    private var posts: [PostModel] = []
    private var currentPage = 0
    private let pageSize = 10
    private var hasMorePages = true
    private var cancellables = Set<AnyCancellable>()

    // Simulated API delay
    private let apiDelay: TimeInterval = 1.5

    // MARK: - Initialization

    init() {
        // Auto-load on init
        Task {
            await loadInitialFeed()
        }
    }

    // MARK: - Public Methods

    /// Load initial feed
    func loadInitialFeed() async {
        guard !state.isLoading else { return }

        state = .loading
        currentPage = 0
        hasMorePages = true

        do {
            try await Task.sleep(nanoseconds: UInt64(apiDelay * 1_000_000_000))
            let newPosts = generateMockPosts(page: 0)

            posts = newPosts
            state = newPosts.isEmpty ? .empty : .loaded(newPosts)
        } catch {
            state = .error(error)
        }
    }

    /// Refresh feed (pull-to-refresh)
    func refresh() async {
        guard !isRefreshing else { return }

        isRefreshing = true
        currentPage = 0
        hasMorePages = true

        do {
            try await Task.sleep(nanoseconds: UInt64(apiDelay * 1_000_000_000))
            let newPosts = generateMockPosts(page: 0)

            posts = newPosts
            state = newPosts.isEmpty ? .empty : .loaded(newPosts)
        } catch {
            state = .error(error)
        }

        isRefreshing = false
    }

    /// Load more posts (pagination)
    func loadMore() async {
        guard !isLoadingMore && !isRefreshing && hasMorePages else { return }

        isLoadingMore = true

        do {
            try await Task.sleep(nanoseconds: UInt64(apiDelay * 1_000_000_000))
            currentPage += 1
            let newPosts = generateMockPosts(page: currentPage)

            if newPosts.isEmpty {
                hasMorePages = false
            } else {
                posts.append(contentsOf: newPosts)
                state = .loaded(posts)
            }
        } catch {
            // Silently fail for pagination errors
            print("Failed to load more: \(error)")
        }

        isLoadingMore = false
    }

    /// Like a post
    func likePost(_ post: PostModel) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }

        var updatedPost = posts[index]
        updatedPost.isLiked.toggle()
        updatedPost.likes += updatedPost.isLiked ? 1 : -1

        posts[index] = updatedPost
        state = .loaded(posts)
    }

    /// Save a post
    func savePost(_ post: PostModel) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }

        var updatedPost = posts[index]
        updatedPost.isSaved.toggle()

        posts[index] = updatedPost
        state = .loaded(posts)
    }

    /// Delete a post
    func deletePost(_ post: PostModel) async {
        do {
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s delay

            posts.removeAll { $0.id == post.id }
            state = posts.isEmpty ? .empty : .loaded(posts)
        } catch {
            state = .error(error)
        }
    }

    // MARK: - Private Methods

    private func generateMockPosts(page: Int) -> [PostModel] {
        let authors = ["Emma Chen", "Alex Liu", "Sarah Wong", "Mike Chen", "Lisa Park", "David Kim", "Rachel Lee", "Tom Zhang"]
        let avatars = ["🎨", "📱", "🌅", "☕️", "🎬", "🎭", "🎸", "📚"]
        let captions = [
            "新作品上線！設計系統 v2.0 完成 🚀",
            "iOS 開發技巧分享：SwiftUI 的最佳實踐",
            "週末旅行，美景無邊 🏔️",
            "咖啡館工作日常",
            "新 MV 幕後花絮發佈",
            "今天的攝影作品 📸",
            "讀書筆記分享",
            "週末 Coding 時光"
        ]
        let imageEmojis = ["🎨", "📱", "🌅", "☕️", "🎬", "📸", "📚", "💻"]

        // Simulate pagination - no more posts after page 2
        if page > 2 {
            return []
        }

        let startIndex = page * pageSize
        return (0..<pageSize).map { index in
            let globalIndex = startIndex + index
            let authorIndex = globalIndex % authors.count

            return PostModel(
                id: "post_\(globalIndex)",
                author: authors[authorIndex],
                avatar: avatars[authorIndex],
                caption: captions[authorIndex],
                likes: Int.random(in: 100...5000),
                comments: Int.random(in: 10...500),
                imageEmoji: imageEmojis[authorIndex],
                timestamp: Date().addingTimeInterval(-Double(globalIndex * 3600)),
                isLiked: false,
                isSaved: false
            )
        }
    }
}

// MARK: - Enhanced Post Model

struct PostModel: Identifiable, Equatable {
    let id: String
    let author: String
    let avatar: String
    let caption: String
    var likes: Int
    let comments: Int
    let imageEmoji: String
    let timestamp: Date
    var isLiked: Bool
    var isSaved: Bool

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - Network Error

enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case serverError
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "無法連接到網絡"
        case .timeout:
            return "請求超時，請重試"
        case .serverError:
            return "服務器錯誤，請稍後再試"
        case .invalidResponse:
            return "收到無效響應"
        }
    }
}
