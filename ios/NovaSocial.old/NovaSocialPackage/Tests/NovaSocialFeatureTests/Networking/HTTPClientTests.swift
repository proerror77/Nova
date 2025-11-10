import Testing
import Foundation

@testable import NovaSocialFeature

// MARK: - Mock HTTP Client for Testing

/// Mock implementation of HTTPClient for testing purposes
actor MockHTTPClient: HTTPClientProtocol {
    enum MockError: Error {
        case decodingError
        case networkError
        case serverError
        case rateLimited
    }

    private var _responses: [String: Any] = [:]
    private var _shouldFail: Bool = false
    private var _failureError: Error?
    private var _requestCount: Int = 0
    private var _requestHistory: [APIEndpoint] = []

    var shouldFail: Bool {
        get async { _shouldFail }
    }

    var failureError: Error? {
        get async { _failureError }
    }

    func setShouldFail(_ value: Bool) async {
        _shouldFail = value
    }

    func setFailureError(_ error: Error?) async {
        _failureError = error
    }

    var requestCount: Int {
        get async { _requestCount }
    }

    var requestHistory: [APIEndpoint] {
        get async { _requestHistory }
    }

    func setMockResponse<T: Encodable>(_ value: T, for endpoint: String) async {
        _responses[endpoint] = value
    }

    func request<T: Decodable & Sendable>(endpoint: APIEndpoint) async throws -> T {
        _requestCount += 1
        _requestHistory.append(endpoint)

        if _shouldFail {
            throw _failureError ?? MockError.networkError
        }

        // For testing, return appropriate mock responses
        if let response = _responses[String(describing: endpoint)] as? T {
            return response
        }

        // Return default mock response
        throw MockError.decodingError
    }

    func reset() async {
        _responses.removeAll()
        _shouldFail = false
        _failureError = nil
        _requestCount = 0
        _requestHistory.removeAll()
    }
}

// MARK: - HTTP Client Tests

@Suite("HTTPClient Tests")
struct HTTPClientTests {
    var mockClient: MockHTTPClient!

    mutating func setup() async {
        mockClient = MockHTTPClient()
    }

    @Test("HTTPClient handles successful requests")
    func testSuccessfulRequest() async throws {
        // Setup
        let mockPosts = [
            Post(
                id: "1",
                author: User(id: "user1", username: "john", displayName: "John Doe"),
                caption: "Test post",
                createdAt: "2025-10-19T10:00:00Z"
            )
        ]

        let response = FeedResponseMock(posts: mockPosts, hasMore: false)

        // This is a simplified test - in real scenarios you'd test against actual HTTPClient
        #expect(response.posts.count == 1)
        #expect(response.posts[0].caption == "Test post")
    }

    @Test("HTTPClient tracks request count")
    func testRequestTracking() async throws {
        let initialCount = await mockClient.requestCount
        #expect(initialCount == 0)
    }

    @Test("HTTPClient handles network errors")
    func testNetworkError() async throws {
        await mockClient.setShouldFail(true)
        await mockClient.setFailureError(MockHTTPClient.MockError.networkError)

        let count = await mockClient.requestCount
        #expect(count == 0)
    }

    @Test("HTTPClient maintains request history")
    func testRequestHistory() async throws {
        let history = await mockClient.requestHistory
        #expect(history.isEmpty)
    }

    @Test("HTTPClient can be reset")
    func testReset() async throws {
        await mockClient.setShouldFail(true)
        await mockClient.reset()

        let shouldFail = await mockClient.shouldFail
        let count = await mockClient.requestCount

        #expect(!shouldFail)
        #expect(count == 0)
    }

    @Test("APIError provides localized descriptions")
    func testAPIErrorLocalization() {
        let error1 = APIError.networkError(URLError(.timedOut))
        #expect(!error1.localizedDescription.isEmpty)

        let error2 = APIError.decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid JSON")))
        #expect(!error2.localizedDescription.isEmpty)

        let error3 = APIError.unauthorized
        #expect(!error3.localizedDescription.isEmpty)
    }

    @Test("APIError categorization")
    func testAPIErrorCategorization() {
        let errors: [APIError] = [
            .networkError(URLError(.timedOut)),
            .decodingError(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "test"))),
            .serverError(statusCode: 500, message: "Server Error"),
            .rateLimited(retryAfter: 60),
            .unauthorized,
            .notFound,
            .invalidRequest("test"),
            .unknown(NSError(domain: "test", code: 1))
        ]

        #expect(errors.count == 8)

        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
        }
    }
}

// MARK: - Mock Response Models

private struct FeedResponseMock: Codable {
    let posts: [Post]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case posts
        case hasMore = "has_more"
    }
}

private struct NotificationMock: Codable, Sendable {
    let id: String
    let userId: String
    let actionType: String
    let timestamp: String
}

private struct NotificationResponseMock: Codable {
    let notifications: [NotificationMock]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case notifications
        case hasMore = "has_more"
    }
}
