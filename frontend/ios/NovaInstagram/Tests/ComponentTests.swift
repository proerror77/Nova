import XCTest
import SwiftUI
@testable import NovaInstagram

// MARK: - Component Unit Tests

/// Unit tests for UI components
final class ComponentTests: XCTestCase {

    // MARK: - Button Tests

    func testPrimaryButtonEnabledState() {
        let button = NovaPrimaryButton(
            title: "Test",
            action: {},
            isEnabled: true
        )

        XCTAssertNotNil(button)
        // Verify button can be created with enabled state
    }

    func testPrimaryButtonDisabledState() {
        let button = NovaPrimaryButton(
            title: "Test",
            action: {},
            isEnabled: false
        )

        XCTAssertNotNil(button)
        // Verify button can be created with disabled state
    }

    func testPrimaryButtonLoadingState() {
        let button = NovaPrimaryButton(
            title: "Test",
            action: {},
            isLoading: true
        )

        XCTAssertNotNil(button)
        // Verify button can be created with loading state
    }

    // MARK: - TextField Tests

    func testTextFieldCreation() {
        @State var text = ""
        let textField = NovaTextField(
            placeholder: "Test",
            text: $text,
            icon: "person"
        )

        XCTAssertNotNil(textField)
    }

    func testSearchFieldCreation() {
        @State var text = ""
        let searchField = NovaSearchField(text: $text)

        XCTAssertNotNil(searchField)
    }

    // MARK: - Card Tests

    func testUserCardCreation() {
        let card = NovaUserCard(
            avatar: "👤",
            username: "Test User",
            subtitle: "Subtitle"
        )

        XCTAssertNotNil(card)
    }

    func testStatsCardCreation() {
        let stats = [
            NovaStatsCard.Stat(title: "Posts", value: "100"),
            NovaStatsCard.Stat(title: "Followers", value: "500")
        ]
        let card = NovaStatsCard(stats: stats)

        XCTAssertNotNil(card)
    }

    func testActionCardCreation() {
        let card = NovaActionCard(
            icon: "gear",
            title: "Settings",
            subtitle: "Preferences",
            action: {}
        )

        XCTAssertNotNil(card)
    }

    // MARK: - Loading State Tests

    func testLoadingSpinnerCreation() {
        let spinner = NovaLoadingSpinner(size: 24)
        XCTAssertNotNil(spinner)
    }

    func testLoadingOverlayCreation() {
        let overlay = NovaLoadingOverlay(message: "Loading...")
        XCTAssertNotNil(overlay)
    }

    func testSkeletonCreation() {
        let skeleton = NovaPostCardSkeleton()
        XCTAssertNotNil(skeleton)
    }

    // MARK: - Empty State Tests

    func testEmptyStateCreation() {
        let emptyState = NovaEmptyState(
            icon: "photo",
            title: "No Posts",
            message: "Start creating content"
        )

        XCTAssertNotNil(emptyState)
    }

    func testErrorStateCreation() {
        let error = NSError(domain: "test", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Test error"
        ])
        let errorState = NovaErrorState(error: error)

        XCTAssertNotNil(errorState)
    }
}

// MARK: - ViewModel Tests

@MainActor
final class FeedViewModelTests: XCTestCase {

    var viewModel: FeedViewModel!

    override func setUp() async throws {
        viewModel = FeedViewModel()
    }

    override func tearDown() {
        viewModel = nil
    }

    func testInitialState() {
        // ViewModel initializes and auto-loads
        // After init, state should transition from idle
        XCTAssertNotNil(viewModel)
    }

    func testLoadInitialFeed() async {
        await viewModel.loadInitialFeed()

        // Should have loaded posts or be in empty state
        switch viewModel.state {
        case .loaded(let posts):
            XCTAssertFalse(posts.isEmpty)
        case .empty:
            XCTAssertTrue(true) // Empty state is valid
        default:
            XCTFail("Unexpected state: \(viewModel.state)")
        }
    }

    func testRefresh() async {
        await viewModel.refresh()

        XCTAssertFalse(viewModel.isRefreshing)
    }

    func testLoadMore() async {
        // First load initial feed
        await viewModel.loadInitialFeed()

        // Then load more
        await viewModel.loadMore()

        XCTAssertFalse(viewModel.isLoadingMore)
    }

    func testLikePost() async {
        await viewModel.loadInitialFeed()

        guard case .loaded(let posts) = viewModel.state,
              let firstPost = posts.first else {
            XCTFail("No posts loaded")
            return
        }

        let initialLikeState = firstPost.isLiked
        let initialLikeCount = firstPost.likes

        viewModel.likePost(firstPost)

        guard case .loaded(let updatedPosts) = viewModel.state,
              let updatedPost = updatedPosts.first(where: { $0.id == firstPost.id }) else {
            XCTFail("Post not found after like")
            return
        }

        XCTAssertNotEqual(updatedPost.isLiked, initialLikeState)
        XCTAssertNotEqual(updatedPost.likes, initialLikeCount)
    }

    func testSavePost() async {
        await viewModel.loadInitialFeed()

        guard case .loaded(let posts) = viewModel.state,
              let firstPost = posts.first else {
            XCTFail("No posts loaded")
            return
        }

        let initialSaveState = firstPost.isSaved

        viewModel.savePost(firstPost)

        guard case .loaded(let updatedPosts) = viewModel.state,
              let updatedPost = updatedPosts.first(where: { $0.id == firstPost.id }) else {
            XCTFail("Post not found after save")
            return
        }

        XCTAssertNotEqual(updatedPost.isSaved, initialSaveState)
    }

    func testDeletePost() async {
        await viewModel.loadInitialFeed()

        guard case .loaded(let posts) = viewModel.state,
              let firstPost = posts.first else {
            XCTFail("No posts loaded")
            return
        }

        let initialCount = posts.count

        await viewModel.deletePost(firstPost)

        switch viewModel.state {
        case .loaded(let updatedPosts):
            XCTAssertEqual(updatedPosts.count, initialCount - 1)
            XCTAssertFalse(updatedPosts.contains(where: { $0.id == firstPost.id }))
        case .empty:
            // Valid if it was the last post
            XCTAssertEqual(initialCount, 1)
        default:
            XCTFail("Unexpected state after delete")
        }
    }

    func testViewStateIsLoading() {
        let loadingState = ViewState<[String]>.loading
        XCTAssertTrue(loadingState.isLoading)

        let idleState = ViewState<[String]>.idle
        XCTAssertFalse(idleState.isLoading)
    }

    func testViewStateData() {
        let data = ["test"]
        let loadedState = ViewState.loaded(data)

        XCTAssertEqual(loadedState.data, data)

        let emptyState = ViewState<[String]>.empty
        XCTAssertNil(emptyState.data)
    }

    func testViewStateError() {
        let error = NSError(domain: "test", code: -1)
        let errorState = ViewState<[String]>.error(error)

        XCTAssertNotNil(errorState.error)

        let idleState = ViewState<[String]>.idle
        XCTAssertNil(idleState.error)
    }
}

// MARK: - Performance Tests

final class PerformanceTests: XCTestCase {

    func testPostCardRenderingPerformance() {
        let post = PostModel(
            id: "1",
            author: "Test User",
            avatar: "👤",
            caption: "Test caption",
            likes: 100,
            comments: 10,
            imageEmoji: "🎨",
            timestamp: Date(),
            isLiked: false,
            isSaved: false
        )

        measure {
            _ = EnhancedPostCard(
                post: post,
                onLike: {},
                onSave: {},
                onDelete: {}
            )
        }
    }

    @MainActor
    func testFeedLoadPerformance() async {
        let viewModel = FeedViewModel()

        await measureAsync {
            await viewModel.loadInitialFeed()
        }
    }
}

// MARK: - Test Helpers

extension XCTestCase {
    func measureAsync(block: @escaping () async -> Void) async {
        let start = Date()
        await block()
        let duration = Date().timeIntervalSince(start)
        print("⏱️ Async operation took: \(duration)s")
    }
}
