import Foundation
import XCTest
@testable import NovaApp

// MARK: - Mock Factories

extension Post {
    static func mock(
        id: String = "post_\(UUID().uuidString.prefix(8))",
        author: User = .mock(),
        imageURL: URL? = URL(string: "https://example.com/image.jpg"),
        caption: String? = "Test caption",
        likeCount: Int = 0,
        commentCount: Int = 0,
        isLiked: Bool = false,
        createdAt: Date = Date()
    ) -> Post {
        Post(
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
        (0..<count).map { index in
            mock(
                id: "post_\(index)",
                likeCount: Int.random(in: 0...100),
                commentCount: Int.random(in: 0...50)
            )
        }
    }
}

extension User {
    static func mock(
        id: String = "user_\(UUID().uuidString.prefix(8))",
        username: String = "testuser",
        displayName: String = "Test User",
        avatarURL: URL? = nil,
        bio: String? = nil,
        followersCount: Int? = 0,
        followingCount: Int? = 0,
        postsCount: Int? = 0
    ) -> User {
        User(
            id: id,
            username: username,
            displayName: displayName,
            avatarURL: avatarURL,
            bio: bio,
            followersCount: followersCount,
            followingCount: followingCount,
            postsCount: postsCount
        )
    }
}

extension Comment {
    static func mock(
        id: String = "comment_\(UUID().uuidString.prefix(8))",
        postId: String = "post_1",
        author: User = .mock(),
        text: String = "Test comment",
        createdAt: Date = Date()
    ) -> Comment {
        Comment(
            id: id,
            postId: postId,
            author: author,
            text: text,
            createdAt: createdAt
        )
    }
}

extension FeedResult {
    static func mock(
        posts: [Post] = Post.mockList(count: 5),
        hasMore: Bool = true
    ) -> FeedResult {
        FeedResult(posts: posts, hasMore: hasMore)
    }
}

// MARK: - Test Utilities

class TestUtilities {
    /// Create a test UIImage with specified size and color
    static func createTestImage(
        size: CGSize = CGSize(width: 100, height: 100),
        color: UIColor = .red
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// Wait for async operation with timeout
    static func waitForAsync(
        timeout: TimeInterval = 5.0,
        operation: @escaping () async throws -> Void
    ) async throws {
        let task = Task {
            try await operation()
        }

        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))

        guard !task.isCancelled else {
            throw TestError.timeout
        }

        try await task.value
    }

    /// Generate random test data
    static func randomString(length: Int = 10) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in letters.randomElement()! })
    }

    static func randomEmail() -> String {
        "\(randomString())@test.com"
    }
}

enum TestError: Error {
    case timeout
    case unexpectedState
}

// MARK: - XCTestCase Extensions

extension XCTestCase {
    /// Assert async throws with specific error type
    func XCTAssertAsyncThrows<T, E: Error>(
        _ expression: @autoclosure () async throws -> T,
        expectedError: E.Type,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error of type \(expectedError) but did not throw", file: file, line: line)
        } catch {
            XCTAssertTrue(error is E, "Expected error of type \(expectedError) but got \(type(of: error))", file: file, line: line)
        }
    }

    /// Wait for published value change
    func waitForPublisher<T: Equatable>(
        _ publisher: Published<T>.Publisher,
        timeout: TimeInterval = 2.0,
        expectedValue: T,
        file: StaticString = #file,
        line: UInt = #line
    ) async {
        let expectation = XCTestExpectation(description: "Publisher value changed")

        let cancellable = publisher.sink { value in
            if value == expectedValue {
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: timeout)
        cancellable.cancel()
    }
}

// MARK: - Date Test Helpers

extension Date {
    static func from(string: String, format: String = "yyyy-MM-dd'T'HH:mm:ssZ") -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.date(from: string) ?? Date()
    }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(seconds: Int) -> Date {
        Calendar.current.date(byAdding: .second, value: seconds, to: self) ?? self
    }
}

// MARK: - JSON Test Helpers

class JSONTestHelper {
    static func loadJSON(from filename: String, bundle: Bundle = .main) -> Data? {
        guard let url = bundle.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return data
    }

    static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(type, from: data)
    }

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8)!
    }
}
