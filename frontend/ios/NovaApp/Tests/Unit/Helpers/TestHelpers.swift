import Foundation
import XCTest
@testable import NovaApp

// MARK: - Test Data Factory

/// Factory for creating test data with consistent defaults
enum TestDataFactory {
    // MARK: - User Factory

    static func createUser(
        id: String = "user_\(UUID().uuidString)",
        username: String = "testuser",
        email: String = "test@example.com",
        displayName: String = "Test User",
        bio: String? = "Test bio",
        avatarURL: URL? = nil,
        followersCount: Int = 100,
        followingCount: Int = 50,
        postsCount: Int = 25
    ) -> User {
        return User(
            id: id,
            username: username,
            email: email,
            displayName: displayName,
            avatarURL: avatarURL,
            bio: bio,
            followersCount: followersCount,
            followingCount: followingCount,
            postsCount: postsCount
        )
    }

    static func createUserList(count: Int) -> [User] {
        return (0..<count).map { index in
            createUser(
                id: "user_\(index)",
                username: "user\(index)",
                email: "user\(index)@example.com",
                displayName: "User \(index)"
            )
        }
    }

    // MARK: - Post Factory

    static func createPost(
        id: String = "post_\(UUID().uuidString)",
        author: User? = nil,
        imageURL: URL? = URL(string: "https://picsum.photos/400/600"),
        caption: String = "Test caption",
        likeCount: Int = 0,
        commentCount: Int = 0,
        isLiked: Bool = false,
        createdAt: Date = Date()
    ) -> Post {
        let postAuthor = author ?? createUser()
        return Post(
            id: id,
            author: postAuthor,
            imageURL: imageURL,
            caption: caption,
            likeCount: likeCount,
            commentCount: commentCount,
            isLiked: isLiked,
            createdAt: createdAt
        )
    }

    static func createPostList(count: Int, author: User? = nil) -> [Post] {
        let postAuthor = author ?? createUser()
        return (0..<count).map { index in
            createPost(
                id: "post_\(index)",
                author: postAuthor,
                caption: "Post \(index) caption",
                likeCount: index * 10,
                commentCount: index * 2
            )
        }
    }

    // MARK: - Comment Factory

    static func createComment(
        id: String = "comment_\(UUID().uuidString)",
        postId: String = "post_123",
        author: User? = nil,
        text: String = "Test comment",
        createdAt: Date = Date()
    ) -> Comment {
        let commentAuthor = author ?? createUser()
        return Comment(
            id: id,
            postId: postId,
            author: commentAuthor,
            text: text,
            createdAt: createdAt
        )
    }

    static func createCommentList(count: Int, postId: String = "post_123") -> [Comment] {
        return (0..<count).map { index in
            createComment(
                id: "comment_\(index)",
                postId: postId,
                text: "Comment \(index) text"
            )
        }
    }

    // MARK: - Error Factory

    static func createAPIError(
        code: String = "TEST_ERROR",
        message: String = "Test error message",
        statusCode: Int = 400
    ) -> APIError {
        return APIError(code: code, message: message, statusCode: statusCode)
    }

    static func createNetworkError() -> Error {
        return NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "No internet connection"]
        )
    }
}

// MARK: - Mock Extensions

extension User {
    static func mock(
        id: String = "user_123",
        username: String = "testuser",
        email: String = "test@example.com",
        displayName: String = "Test User",
        bio: String? = "Test bio",
        avatarURL: URL? = nil,
        followersCount: Int = 100,
        followingCount: Int = 50,
        postsCount: Int = 25
    ) -> User {
        return TestDataFactory.createUser(
            id: id,
            username: username,
            email: email,
            displayName: displayName,
            bio: bio,
            avatarURL: avatarURL,
            followersCount: followersCount,
            followingCount: followingCount,
            postsCount: postsCount
        )
    }

    static func mockList(count: Int) -> [User] {
        return TestDataFactory.createUserList(count: count)
    }
}

extension Post {
    static func mock(
        id: String = "post_123",
        author: User = User.mock(),
        imageURL: URL? = URL(string: "https://picsum.photos/400/600"),
        caption: String = "Test caption",
        likeCount: Int = 0,
        commentCount: Int = 0,
        isLiked: Bool = false,
        createdAt: Date = Date()
    ) -> Post {
        return TestDataFactory.createPost(
            id: id,
            author: author,
            imageURL: imageURL,
            caption: caption,
            likeCount: likeCount,
            commentCount: commentCount,
            isLiked: isLiked,
            createdAt: createdAt
        )
    }

    static func mockList(count: Int) -> [Post] {
        return TestDataFactory.createPostList(count: count)
    }
}

extension Comment {
    static func mock(
        id: String = "comment_123",
        postId: String = "post_123",
        author: User = User.mock(),
        text: String = "Test comment",
        createdAt: Date = Date()
    ) -> Comment {
        return TestDataFactory.createComment(
            id: id,
            postId: postId,
            author: author,
            text: text,
            createdAt: createdAt
        )
    }

    static func mockList(count: Int, postId: String = "post_123") -> [Comment] {
        return TestDataFactory.createCommentList(count: count, postId: postId)
    }
}

extension APIError {
    static func mock(
        code: String = "TEST_ERROR",
        message: String = "Test error",
        statusCode: Int = 400
    ) -> APIError {
        return TestDataFactory.createAPIError(
            code: code,
            message: message,
            statusCode: statusCode
        )
    }
}

// MARK: - XCTest Assertions Extensions

extension XCTestCase {
    /// Assert that an async throwing function throws a specific error
    func assertThrowsError<T, E: Error & Equatable>(
        _ expression: @autoclosure () async throws -> T,
        expectedError: E,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected to throw \(expectedError), but no error was thrown", file: file, line: line)
        } catch let error as E {
            XCTAssertEqual(error, expectedError, file: file, line: line)
        } catch {
            XCTFail("Expected to throw \(expectedError), but threw \(error)", file: file, line: line)
        }
    }

    /// Wait for a published value to match a condition
    @MainActor
    func waitForPublishedValue<T>(
        timeout: TimeInterval = 1.0,
        matching condition: @escaping (T) -> Bool,
        publisher: Published<T>.Publisher
    ) async throws {
        let expectation = XCTestExpectation(description: "Waiting for published value")

        var cancellable: AnyCancellable?
        cancellable = publisher.sink { value in
            if condition(value) {
                expectation.fulfill()
                cancellable?.cancel()
            }
        }

        await fulfillment(of: [expectation], timeout: timeout)
    }

    /// Assert that two arrays contain the same elements (ignoring order)
    func assertArraysEqualIgnoringOrder<T: Hashable>(
        _ lhs: [T],
        _ rhs: [T],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(Set(lhs), Set(rhs), file: file, line: line)
    }

    /// Assert that a value is within a range
    func assertInRange<T: Comparable>(
        _ value: T,
        min: T,
        max: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(value, min, file: file, line: line)
        XCTAssertLessThanOrEqual(value, max, file: file, line: line)
    }
}

// MARK: - Async Testing Utilities

/// Utility for testing async/await code
enum AsyncTestUtility {
    /// Wait for a condition to be true
    static func wait(
        timeout: TimeInterval = 1.0,
        pollingInterval: TimeInterval = 0.01,
        until condition: @escaping () -> Bool
    ) async throws {
        let startTime = Date()

        while !condition() {
            if Date().timeIntervalSince(startTime) > timeout {
                throw AsyncTestError.timeout
            }
            try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
        }
    }

    /// Execute code after a delay
    static func delay(_ duration: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
}

enum AsyncTestError: Error {
    case timeout
}

// MARK: - Performance Testing Helpers

class PerformanceTestHelper {
    /// Measure execution time of an async function
    static func measureAsync(
        _ block: () async throws -> Void
    ) async throws -> TimeInterval {
        let start = Date()
        try await block()
        return Date().timeIntervalSince(start)
    }

    /// Assert that an async operation completes within a time limit
    static func assertCompletes(
        within duration: TimeInterval,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async throws {
        let elapsed = try await measureAsync(block)

        XCTAssertLessThan(
            elapsed,
            duration,
            "Operation took \(elapsed)s, expected < \(duration)s",
            file: file,
            line: line
        )
    }
}

// MARK: - Memory Leak Detection

class LeakDetector {
    /// Check if an object is properly deallocated
    static func trackForMemoryLeaks(
        _ instance: AnyObject,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(
                instance,
                "Instance should have been deallocated. Potential memory leak.",
                file: file,
                line: line
            )
        }
    }
}
