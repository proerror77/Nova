import Foundation

// MARK: - API Client

/// Base HTTP client for all API requests
/// Handles authentication, JSON encoding/decoding, and error handling
/// Automatically refreshes expired tokens on 401 responses
class APIClient {
    static let shared = APIClient()

    private let baseURL = APIConfig.current.baseURL

    /// Shared URLSession for all API requests - use this instead of creating new sessions
    let session: URLSession
    private var authToken: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.current.timeout
        config.timeoutIntervalForResource = APIConfig.current.resourceTimeout
        self.session = URLSession(configuration: config)
    }

    func setAuthToken(_ token: String) {
        self.authToken = token.isEmpty ? nil : token
    }

    func getAuthToken() -> String? {
        return authToken
    }

    /// Build a URLRequest with proper headers and auth token
    func buildRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - Generic Request Methods

    /// Simple POST request (for fire-and-forget analytics)
    func post(endpoint: String, body: Encodable) async throws {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            #if DEBUG
            print("[API] POST \(endpoint) failed")
            #endif
            throw APIError.serverError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, message: "POST failed")
        }

        #if DEBUG
        if APIFeatureFlags.enableRequestLogging {
            print("[API] POST \(endpoint) -> \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        #endif
    }

    /// POST/PUT/DELETE request with JSON body
    func request<T: Decodable>(
        endpoint: String,
        method: String = "POST",
        body: Encodable? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw APIError.decodingError(error)
            }
        }

        return try await executeRequest(request)
    }

    /// GET request with query parameters
    func get<T: Decodable>(
        endpoint: String,
        queryParams: [String: String]? = nil
    ) async throws -> T {
        var urlComponents = URLComponents(string: "\(baseURL)\(endpoint)")

        if let queryParams = queryParams, !queryParams.isEmpty {
            urlComponents?.queryItems = queryParams.map {
                URLQueryItem(name: $0.key, value: $0.value)
            }
        }

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        let request = buildRequest(url: url, method: "GET")
        return try await executeRequest(request)
    }

    /// Execute request and handle response
    /// Automatically attempts token refresh on 401 and retries once
    private func executeRequest<T: Decodable>(_ request: URLRequest, isRetry: Bool = false) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            #if DEBUG
            if APIFeatureFlags.enableRequestLogging {
                print("[\(request.httpMethod ?? "?")] \(request.url?.absoluteString ?? "?") -> \(httpResponse.statusCode)")
            }
            #endif

            switch httpResponse.statusCode {
            case 200...299:
                return try decodeResponse(data)
            case 401:
                // Attempt token refresh on 401, but only once to prevent infinite loops
                if !isRetry {
                    #if DEBUG
                    print("[API] 401 received, attempting token refresh...")
                    #endif

                    let refreshSucceeded = await AuthenticationManager.shared.attemptTokenRefresh()

                    if refreshSucceeded {
                        #if DEBUG
                        print("[API] Token refreshed, retrying request...")
                        #endif

                        // Rebuild request with new token
                        var retryRequest = request
                        if let newToken = authToken {
                            retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        }

                        // Retry with isRetry=true to prevent infinite loop
                        return try await executeRequest(retryRequest, isRetry: true)
                    }
                }

                #if DEBUG
                print("[API] Token refresh failed or already retried, throwing unauthorized")
                #endif
                throw APIError.unauthorized
            case 404:
                throw APIError.notFound
            case 408, 504:
                throw APIError.timeout
            case 503:
                throw APIError.serviceUnavailable
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
            }
        } catch let error as APIError {
            throw error
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                throw APIError.timeout
            case .notConnectedToInternet, .networkConnectionLost:
                throw APIError.noConnection
            default:
                throw APIError.networkError(urlError)
            }
        } catch {
            throw APIError.networkError(error)
        }
    }

    /// Decode JSON response with standard settings
    private func decodeResponse<T: Decodable>(_ data: Data) throws -> T {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("[API] Decoding error: \(error)")
            print("[API] Response size: \(data.count) bytes")
            print("[API] Expected type: \(T.self)")

            // 打印 JSON 响应以帮助调试（仅在调试模式）
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[API] Response JSON: \(jsonString.prefix(500))...")  // 限制长度避免过长
            }
            #endif
            throw APIError.decodingError(error)
        }
    }
}
