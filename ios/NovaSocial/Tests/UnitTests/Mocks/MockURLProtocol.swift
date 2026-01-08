import Foundation

/// MockURLProtocol - Intercepts and mocks network requests for testing
/// TDD: Enables complete control over network responses without real backend
final class MockURLProtocol: URLProtocol {

    // MARK: - Static Configuration

    /// Request handler type
    typealias RequestHandler = (URLRequest) throws -> (HTTPURLResponse, Data?)

    /// Global request handler
    static var requestHandler: RequestHandler?

    /// Simulated response delay (seconds)
    static var responseDelay: TimeInterval = 0

    /// Request history for verification
    private static var requestHistory: [URLRequest] = []
    private static let historyLock = NSLock()

    /// Reset all configuration
    static func reset() {
        requestHandler = nil
        responseDelay = 0
        historyLock.lock()
        requestHistory.removeAll()
        historyLock.unlock()
    }

    /// Get recorded requests for verification
    static var recordedRequests: [URLRequest] {
        historyLock.lock()
        defer { historyLock.unlock() }
        return requestHistory
    }

    // MARK: - URLProtocol Override

    override class func canInit(with request: URLRequest) -> Bool {
        // Intercept all requests
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        // Record request
        MockURLProtocol.historyLock.lock()
        MockURLProtocol.requestHistory.append(request)
        MockURLProtocol.historyLock.unlock()

        // Unit tests run inside a host app process; the app may issue background/network
        // requests before a specific test's setUp() has installed a requestHandler.
        // Default to a safe 200-empty response instead of crashing the entire test run.
        let handler = MockURLProtocol.requestHandler ?? { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, nil)
        }

        // Simulate network delay
        if MockURLProtocol.responseDelay > 0 {
            Thread.sleep(forTimeInterval: MockURLProtocol.responseDelay)
        }

        do {
            let (response, data) = try handler(request)

            // Send response
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            // Send data
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }

            // Finish
            client?.urlProtocolDidFinishLoading(self)

        } catch {
            // Send error
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        // Cleanup resources
    }
}

// MARK: - Convenience Helpers

extension MockURLProtocol {

    /// Configure success response
    static func mockSuccess(statusCode: Int = 200, data: Data? = nil, headers: [String: String]? = nil) {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
            return (response, data)
        }
    }

    /// Configure JSON response
    static func mockJSON<T: Encodable>(_ object: T, statusCode: Int = 200) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(object)

        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, data)
        }
    }

    /// Configure error response
    static func mockError(statusCode: Int, errorData: Data? = nil) {
        requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, errorData)
        }
    }

    /// Configure network timeout
    static func mockTimeout() {
        requestHandler = { _ in
            throw URLError(.timedOut)
        }
    }

    /// Configure no network connection
    static func mockNoConnection() {
        requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
    }

    /// Configure sequence of responses (useful for retry testing)
    static func mockSequence(_ responses: [(Int, Data?)]) {
        var responseIndex = 0
        let lock = NSLock()

        requestHandler = { request in
            lock.lock()
            let index = responseIndex
            responseIndex += 1
            lock.unlock()

            let (statusCode, data) = responses[min(index, responses.count - 1)]
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }
    }

    /// Create a mock URLSession configured to use this protocol
    static func createMockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }
}
