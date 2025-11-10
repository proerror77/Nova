import Foundation

/// Protocol for HTTP client operations
protocol HTTPClientProtocol: Sendable {
    func request<T: Decodable>(endpoint: APIEndpoint) async throws -> T
}

/// HTTPClient handles all API communication with retry logic and error handling
final class HTTPClient: HTTPClientProtocol, Sendable {
    private let session: URLSession
    private let maxRetries = 4
    private let monitor = NetworkMonitor.shared

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Makes an HTTP request to the specified endpoint with automatic retry logic
    func request<T: Decodable>(endpoint: APIEndpoint) async throws -> T {
        var lastError: APIError?
        let startTime = Date()

        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await session.data(for: endpoint.urlRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    let duration = Date().timeIntervalSince(startTime)
                    monitor.logRequest(
                        endpoint: endpoint.description,
                        method: "GET",
                        statusCode: nil,
                        duration: duration,
                        bytesDownloaded: data.count,
                        error: APIError.unknown(NSError(domain: "Invalid response", code: -1))
                    )
                    throw APIError.unknown(NSError(domain: "Invalid response", code: -1))
                }

                // Parse response based on status code
                try validateStatusCode(httpResponse.statusCode)

                // Decode response
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let decodedResponse = try decoder.decode(T.self, from: data)

                // Log successful request
                let duration = Date().timeIntervalSince(startTime)
                monitor.logRequest(
                    endpoint: endpoint.description,
                    method: "GET",
                    statusCode: httpResponse.statusCode,
                    duration: duration,
                    bytesDownloaded: data.count
                )

                return decodedResponse
            } catch let error as APIError {
                lastError = error

                // Don't retry on client errors (4xx) except 429 (rate limited)
                if case .serverError(let statusCode, _) = error, statusCode >= 400 && statusCode < 500 && statusCode != 429 {
                    throw error
                }

                // Don't retry on authorization errors
                if case .unauthorized = error {
                    throw error
                }

                // Retry on network errors and server errors (5xx)
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt))
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
            } catch let error as DecodingError {
                lastError = .decodingError(error)
                throw lastError!
            } catch let error as URLError {
                lastError = .networkError(error)
                // Retry on network errors
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt))
                    try await Task.sleep(for: .seconds(delay))
                    continue
                }
            } catch {
                lastError = .unknown(error)
                throw lastError!
            }
        }

        throw lastError ?? .unknown(NSError(domain: "Unknown error", code: -1))
    }

    /// Validates HTTP status code and throws appropriate errors
    private func validateStatusCode(_ statusCode: Int) throws {
        switch statusCode {
        case 200...299:
            // Success range, no error
            return
        case 400:
            throw APIError.invalidRequest("Bad request")
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            throw APIError.rateLimited(retryAfter: 60)
        case 500...599:
            throw APIError.serverError(statusCode: statusCode, message: "Server error")
        default:
            throw APIError.serverError(statusCode: statusCode, message: "HTTP \(statusCode)")
        }
    }
}
