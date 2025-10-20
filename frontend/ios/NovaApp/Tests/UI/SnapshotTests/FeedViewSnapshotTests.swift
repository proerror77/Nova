import XCTest
import SnapshotTesting
import SwiftUI
@testable import NovaApp

/// UI Snapshot Tests for Feed View
/// Uses swift-snapshot-testing for visual regression testing
@MainActor
class FeedViewSnapshotTests: XCTestCase {
    var mockViewModel: FeedViewModel!
    var mockRepository: MockFeedRepository!

    override func setUp() {
        super.setUp()
        mockRepository = MockFeedRepository()
        mockViewModel = FeedViewModel(repository: mockRepository)

        // Set consistent environment for snapshot testing
        isRecording = false // Set to true to record new snapshots
    }

    override func tearDown() {
        mockViewModel = nil
        mockRepository = nil
        super.tearDown()
    }

    // MARK: - Empty State Snapshots

    func testFeedView_EmptyState() {
        // Given
        mockViewModel.posts = []
        mockViewModel.isLoading = false

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.colorScheme, .light)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13Pro)))
    }

    func testFeedView_EmptyState_DarkMode() {
        // Given
        mockViewModel.posts = []
        mockViewModel.isLoading = false

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.colorScheme, .dark)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13Pro)))
    }

    // MARK: - Loading State Snapshots

    func testFeedView_LoadingState() {
        // Given
        mockViewModel.posts = []
        mockViewModel.isLoading = true

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.colorScheme, .light)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13Pro)))
    }

    // MARK: - Content State Snapshots

    func testFeedView_WithPosts() {
        // Given
        mockViewModel.posts = Post.mockList(count: 3)
        mockViewModel.isLoading = false

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.colorScheme, .light)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13Pro)))
    }

    func testFeedView_WithPosts_DarkMode() {
        // Given
        mockViewModel.posts = Post.mockList(count: 3)
        mockViewModel.isLoading = false

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.colorScheme, .dark)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13Pro)))
    }

    // MARK: - Error State Snapshots

    func testFeedView_ErrorState() {
        // Given
        mockViewModel.posts = []
        mockViewModel.error = APIError.mock(message: "Failed to load feed")
        mockViewModel.showError = true

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.colorScheme, .light)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13Pro)))
    }

    // MARK: - Pagination State Snapshots

    func testFeedView_LoadingMore() {
        // Given
        mockViewModel.posts = Post.mockList(count: 10)
        mockViewModel.isLoadingMore = true

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.colorScheme, .light)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13Pro)))
    }

    // MARK: - Device Size Variations

    func testFeedView_iPhone_SE() {
        // Given
        mockViewModel.posts = Post.mockList(count: 2)

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.colorScheme, .light)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhoneSe)))
    }

    func testFeedView_iPhone_ProMax() {
        // Given
        mockViewModel.posts = Post.mockList(count: 2)

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.colorScheme, .light)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13ProMax)))
    }

    // MARK: - Component Snapshots

    func testPostCard_Normal() {
        // Given
        let post = Post.mock(
            id: "post_1",
            author: User.mock(username: "testuser", displayName: "Test User"),
            caption: "Beautiful sunset 🌅",
            likeCount: 1234,
            commentCount: 56,
            isLiked: false
        )

        // When
        let view = PostCardView(post: post, onLike: {}, onComment: {})
            .frame(width: 375) // iPhone 13 Pro width

        // Then
        assertSnapshot(matching: view, as: .image)
    }

    func testPostCard_Liked() {
        // Given
        let post = Post.mock(
            id: "post_1",
            caption: "Liked post",
            likeCount: 100,
            isLiked: true
        )

        // When
        let view = PostCardView(post: post, onLike: {}, onComment: {})
            .frame(width: 375)

        // Then
        assertSnapshot(matching: view, as: .image)
    }

    func testPostCard_LongCaption() {
        // Given
        let longCaption = String(repeating: "This is a very long caption with lots of text. ", count: 10)
        let post = Post.mock(
            id: "post_1",
            caption: longCaption,
            likeCount: 999
        )

        // When
        let view = PostCardView(post: post, onLike: {}, onComment: {})
            .frame(width: 375)

        // Then
        assertSnapshot(matching: view, as: .image)
    }

    // MARK: - Accessibility Snapshots

    func testFeedView_ExtraLargeText() {
        // Given
        mockViewModel.posts = Post.mockList(count: 2)

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.sizeCategory, .accessibilityExtraLarge)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13Pro)))
    }

    func testFeedView_SmallText() {
        // Given
        mockViewModel.posts = Post.mockList(count: 2)

        // When
        let view = FeedView(viewModel: mockViewModel)
            .environment(\.sizeCategory, .extraSmall)

        // Then
        assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13Pro)))
    }
}
