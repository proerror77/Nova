# Nova iOS - Testing Strategy

## Test Pyramid

```
        /\
       /  \  E2E Tests (5%)
      /----\
     /      \  Integration Tests (25%)
    /--------\
   /          \  Unit Tests (70%)
  /______________\
```

## Unit Tests (70%)

### ViewModels
Test all business logic in isolation using mock repositories.

**Example: FeedViewModel**
```swift
import XCTest
@testable import NovaApp

class FeedViewModelTests: XCTestCase {
    var sut: FeedViewModel!
    var mockRepository: MockFeedRepository!

    override func setUp() {
        super.setUp()
        mockRepository = MockFeedRepository()
        sut = FeedViewModel(repository: mockRepository)
    }

    func testLoadInitial_Success() async {
        // Given
        let mockPosts = [Post.mock()]
        mockRepository.feedResult = FeedResult(posts: mockPosts, hasMore: true)

        // When
        await sut.loadInitial()

        // Then
        XCTAssertEqual(sut.posts.count, 1)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.error)
    }

    func testToggleLike_OptimisticUpdate() async {
        // Given
        sut.posts = [Post.mock(isLiked: false, likeCount: 10)]

        // When
        await sut.toggleLike(postId: "post_1")

        // Then (immediate update)
        XCTAssertTrue(sut.posts[0].isLiked)
        XCTAssertEqual(sut.posts[0].likeCount, 11)
    }

    func testPagination_LoadMore() async {
        // Given
        sut.posts = [Post.mock()]
        mockRepository.feedResult = FeedResult(
            posts: [Post.mock(id: "post_2")],
            hasMore: false
        )

        // When
        await sut.loadMore()

        // Then
        XCTAssertEqual(sut.posts.count, 2)
        XCTAssertFalse(sut.hasMore)
    }
}
```

### Repositories
Test API integration logic with mock APIClient.

**Example: AuthRepository**
```swift
class AuthRepositoryTests: XCTestCase {
    var sut: AuthRepository!
    var mockAPIClient: MockAPIClient!

    func testSignIn_Success() async throws {
        // Given
        let expectedToken = "access_token_123"
        mockAPIClient.mockResponse = AuthResult(
            accessToken: expectedToken,
            refreshToken: "refresh_token_123",
            user: User.mock()
        )

        // When
        let result = try await sut.signIn(email: "test@example.com", password: "password")

        // Then
        XCTAssertEqual(result.accessToken, expectedToken)
        XCTAssertEqual(mockAPIClient.lastEndpoint?.path, "/auth/signin")
    }
}
```

### Services
Test core services (AuthService, CacheManager, etc.)

**Example: CacheManager**
```swift
class CacheManagerTests: XCTestCase {
    func testFeedCache_ExpiresAfter30Seconds() {
        // Given
        let cache = CacheManager.shared
        let feed = FeedResult(posts: [Post.mock()], hasMore: true)
        cache.cacheFeed(feed)

        // When (wait 31 seconds)
        let expectation = XCTestExpectation(description: "Wait for cache expiry")
        DispatchQueue.main.asyncAfter(deadline: .now() + 31) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 32)

        // Then
        XCTAssertNil(cache.getCachedFeed())
    }
}
```

### Models
Test Codable conformance and business logic.

```swift
class PostTests: XCTestCase {
    func testDecode_ValidJSON() throws {
        let json = """
        {
            "id": "post_1",
            "author": { "id": "user_1", "username": "john", "display_name": "John" },
            "image_url": "https://example.com/image.jpg",
            "caption": "Test",
            "like_count": 10,
            "comment_count": 5,
            "is_liked": false,
            "created_at": "2025-10-18T10:30:00Z"
        }
        """
        let data = json.data(using: .utf8)!
        let post = try JSONDecoder().decode(Post.self, from: data)

        XCTAssertEqual(post.id, "post_1")
        XCTAssertEqual(post.likeCount, 10)
    }
}
```

## Integration Tests (25%)

### Auth Flow
```swift
class AuthFlowIntegrationTests: XCTestCase {
    func testSignUpAndSignInFlow() async throws {
        // Sign up
        let username = "testuser_\(UUID().uuidString.prefix(8))"
        let email = "\(username)@example.com"
        let password = "SecurePass123"

        try await authService.signUp(username: username, email: email, password: password)
        XCTAssertTrue(authService.isAuthenticated)

        // Sign out
        await authService.signOut()
        XCTAssertFalse(authService.isAuthenticated)

        // Sign in
        try await authService.signIn(email: email, password: password)
        XCTAssertTrue(authService.isAuthenticated)
    }
}
```

### Feed Flow
```swift
class FeedFlowIntegrationTests: XCTestCase {
    func testFeedLoadAndLike() async throws {
        // Load feed
        let viewModel = FeedViewModel()
        await viewModel.loadInitial()

        XCTAssertFalse(viewModel.posts.isEmpty)

        // Like first post
        let firstPost = viewModel.posts[0]
        await viewModel.toggleLike(postId: firstPost.id)

        XCTAssertTrue(viewModel.posts[0].isLiked)
    }
}
```

### Create Flow
```swift
class CreateFlowIntegrationTests: XCTestCase {
    func testUploadFlow() async throws {
        // Create test image
        let image = UIImage.createTestImage(size: CGSize(width: 1000, height: 1000))
        let imageData = image.jpegData(compressionQuality: 0.85)!

        // Upload
        let viewModel = CreateViewModel()
        try await viewModel.publishPost(imageData: imageData, caption: "Test post")

        // Verify post created
        XCTAssertNotNil(viewModel.uploadedPostId)
    }
}
```

## E2E Tests (5%)

### Critical User Journeys
Use XCUITest for end-to-end testing.

**Journey 1: Sign Up → Post → Like**
```swift
class CriticalJourneyTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launch()
    }

    func testSignUpPostLikeJourney() {
        // Sign up
        app.buttons["Get Started"].tap()
        app.buttons["Sign Up"].tap()

        let usernameField = app.textFields["Username"]
        usernameField.tap()
        usernameField.typeText("testuser")

        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText("test@example.com")

        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText("SecurePass123")

        app.buttons["Sign Up"].tap()

        // Wait for feed
        XCTAssertTrue(app.otherElements["FeedView"].waitForExistence(timeout: 5))

        // Like first post
        let firstPost = app.otherElements["PostCard"].firstMatch
        XCTAssertTrue(firstPost.exists)
        firstPost.buttons["Like"].tap()

        // Verify liked state
        XCTAssertTrue(firstPost.buttons["Unlike"].exists)
    }
}
```

## Mock Fixtures

### MockFeedRepository
```swift
class MockFeedRepository: FeedRepository {
    var feedResult: FeedResult = FeedResult(posts: [], hasMore: false)
    var shouldThrowError = false

    override func fetchFeed(page: Int, limit: Int) async throws -> FeedResult {
        if shouldThrowError {
            throw APIError.networkError(NSError(domain: "", code: -1))
        }
        return feedResult
    }
}
```

### MockAPIClient
```swift
class MockAPIClient: APIClient {
    var mockResponse: Any?
    var lastEndpoint: Endpoint?

    override func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        lastEndpoint = endpoint

        guard let response = mockResponse as? T else {
            throw APIError.decodingError(NSError(domain: "", code: -1))
        }

        return response
    }
}
```

### Test Helpers
```swift
extension Post {
    static func mock(
        id: String = "post_1",
        isLiked: Bool = false,
        likeCount: Int = 0
    ) -> Post {
        Post(
            id: id,
            author: User.mock(),
            imageURL: URL(string: "https://example.com/image.jpg"),
            caption: "Test caption",
            likeCount: likeCount,
            commentCount: 0,
            isLiked: isLiked,
            createdAt: Date()
        )
    }
}

extension User {
    static func mock(id: String = "user_1") -> User {
        User(
            id: id,
            username: "testuser",
            displayName: "Test User",
            avatarURL: nil,
            bio: nil,
            followersCount: nil,
            followingCount: nil,
            postsCount: nil
        )
    }
}
```

## Performance Tests

### Feed Load Performance
```swift
func testFeedLoadPerformance() {
    measure {
        let expectation = XCTestExpectation(description: "Feed loaded")
        Task {
            await viewModel.loadInitial()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0) // Should load within 1s
    }
}
```

### Image Compression Performance
```swift
func testImageCompressionPerformance() {
    let image = UIImage.createTestImage(size: CGSize(width: 4000, height: 3000))

    measure {
        let compressed = ImageCompressionService.compress(image, maxSizeMB: 2)
        XCTAssertNotNil(compressed)
    }
}
```

## Accessibility Tests

### VoiceOver Labels
```swift
func testPostCardAccessibility() {
    let post = Post.mock(id: "post_1")
    let card = PostCard(post: post, onTap: {}, onLike: {}, onComment: {})

    XCTAssertNotNil(card.accessibilityLabel)
    XCTAssertTrue(card.accessibilityLabel!.contains(post.author.displayName))
}
```

## Test Coverage Goals

| Layer | Target Coverage | Current |
|-------|----------------|---------|
| ViewModels | 90% | TBD |
| Repositories | 85% | TBD |
| Services | 80% | TBD |
| Models | 70% | TBD |
| Overall | 80% | TBD |

## CI/CD Integration

### GitHub Actions Workflow
```yaml
name: iOS Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2

      - name: Run Unit Tests
        run: |
          xcodebuild test \
            -scheme NovaApp \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -enableCodeCoverage YES

      - name: Upload Coverage
        uses: codecov/codecov-action@v2
```

## Test Execution

### Local
```bash
# Run all tests
xcodebuild test -scheme NovaApp -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test class
xcodebuild test -scheme NovaApp -only-testing:NovaAppTests/FeedViewModelTests

# Run with coverage
xcodebuild test -scheme NovaApp -enableCodeCoverage YES
```

### CI
- All tests run on every PR
- E2E tests run nightly
- Performance tests run weekly

## Test Maintenance

### Best Practices
- [ ] Keep tests independent (no shared state)
- [ ] Use descriptive test names (`test_Scenario_ExpectedOutcome`)
- [ ] Arrange-Act-Assert pattern
- [ ] One assertion per test (when possible)
- [ ] Mock external dependencies
- [ ] Clean up resources in `tearDown()`

### Red Flags
- ❌ Flaky tests (pass/fail randomly)
- ❌ Slow tests (> 1s for unit tests)
- ❌ Tests dependent on order
- ❌ Tests requiring manual setup
- ❌ Tests that modify production data

## Documentation
All complex test scenarios should have inline comments explaining:
- **Given:** Initial state
- **When:** Action performed
- **Then:** Expected outcome

```swift
func testComplexScenario() {
    // Given: User is signed in with 5 posts in feed
    authService.currentUser = User.mock()
    viewModel.posts = Array(repeating: Post.mock(), count: 5)

    // When: User deletes the third post
    await viewModel.deletePost(postId: viewModel.posts[2].id)

    // Then: Feed has 4 posts remaining
    XCTAssertEqual(viewModel.posts.count, 4)
}
```
