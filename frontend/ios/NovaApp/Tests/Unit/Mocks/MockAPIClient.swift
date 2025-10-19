import Foundation
@testable import NovaApp

/// Mock API Client for testing network layer
class MockAPIClient: APIClient {
    // MARK: - Mock Data
    var mockResponse: Any?
    var mockError: Error?
    var requestDelay: TimeInterval = 0

    // MARK: - Call Tracking
    var requestCallCount = 0
    var lastEndpoint: Endpoint?
    var allEndpoints: [Endpoint] = []

    // MARK: - Mock Response
    override func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        requestCallCount += 1
        lastEndpoint = endpoint
        allEndpoints.append(endpoint)

        // Simulate network delay
        if requestDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(requestDelay * 1_000_000_000))
        }

        // Throw error if configured
        if let error = mockError {
            throw error
        }

        // Return mock response
        guard let response = mockResponse as? T else {
            throw APIError.decodingError(
                NSError(domain: "MockAPIClient", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Mock response type mismatch"
                ])
            )
        }

        return response
    }

    // MARK: - Upload Mock
    var uploadProgress: ((Double) -> Void)?
    var uploadResponse: Data?

    override func upload(_ endpoint: Endpoint, data: Data, onProgress: ((Double) -> Void)?) async throws -> Data {
        requestCallCount += 1
        lastEndpoint = endpoint
        allEndpoints.append(endpoint)

        // Simulate upload progress
        if let progressCallback = onProgress ?? uploadProgress {
            for progress in stride(from: 0.0, through: 1.0, by: 0.2) {
                progressCallback(progress)
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }
        }

        if let error = mockError {
            throw error
        }

        return uploadResponse ?? Data()
    }

    // MARK: - Download Mock
    var downloadResponse: Data?

    override func download(_ endpoint: Endpoint) async throws -> Data {
        requestCallCount += 1
        lastEndpoint = endpoint
        allEndpoints.append(endpoint)

        if let error = mockError {
            throw error
        }

        return downloadResponse ?? Data()
    }

    // MARK: - Reset
    func reset() {
        mockResponse = nil
        mockError = nil
        requestDelay = 0
        requestCallCount = 0
        lastEndpoint = nil
        allEndpoints = []
        uploadProgress = nil
        uploadResponse = nil
        downloadResponse = nil
    }

    // MARK: - Helpers
    func didRequest(path: String) -> Bool {
        allEndpoints.contains { $0.path == path }
    }

    func requestCount(for path: String) -> Int {
        allEndpoints.filter { $0.path == path }.count
    }
}

// MARK: - API Error Mock
enum APIError: Error {
    case networkError(Error)
    case decodingError(Error)
    case unauthorized
    case notFound
    case serverError(Int)
    case unknown

    static func mock() -> APIError {
        .networkError(NSError(domain: "test", code: -1))
    }
}

// MARK: - Endpoint Mock
struct Endpoint {
    let path: String
    let method: HTTPMethod
    let headers: [String: String]?
    let body: Data?
    let queryParams: [String: String]?

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
        case patch = "PATCH"
    }
}

// MARK: - Mock Endpoints
class Endpoints {
    static func fetchFeed(page: Int, limit: Int) -> Endpoint {
        Endpoint(
            path: "/feed",
            method: .get,
            headers: nil,
            body: nil,
            queryParams: ["page": "\(page)", "limit": "\(limit)"]
        )
    }

    static func likePost(postId: String) -> Endpoint {
        Endpoint(
            path: "/posts/\(postId)/like",
            method: .post,
            headers: nil,
            body: nil,
            queryParams: nil
        )
    }

    static func unlikePost(postId: String) -> Endpoint {
        Endpoint(
            path: "/posts/\(postId)/like",
            method: .delete,
            headers: nil,
            body: nil,
            queryParams: nil
        )
    }

    static func deletePost(postId: String) -> Endpoint {
        Endpoint(
            path: "/posts/\(postId)",
            method: .delete,
            headers: nil,
            body: nil,
            queryParams: nil
        )
    }

    static func signIn(email: String, password: String) -> Endpoint {
        let body = try? JSONEncoder().encode([
            "email": email,
            "password": password
        ])
        return Endpoint(
            path: "/auth/signin",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            queryParams: nil
        )
    }

    static func signUp(username: String, email: String, password: String) -> Endpoint {
        let body = try? JSONEncoder().encode([
            "username": username,
            "email": email,
            "password": password
        ])
        return Endpoint(
            path: "/auth/signup",
            method: .post,
            headers: ["Content-Type": "application/json"],
            body: body,
            queryParams: nil
        )
    }
}
