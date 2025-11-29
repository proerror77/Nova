import Foundation

// MARK: - API Client

/// Base HTTP client for all API requests
/// Handles authentication, JSON encoding/decoding, and error handling
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
    private func executeRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
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
                throw APIError.unauthorized
            case 404:
                throw APIError.notFound
            case 408, 504:
                throw APIError.timeout
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
            // Don't log full JSON response - may contain sensitive user data
            print("[API] Response size: \(data.count) bytes")
            #endif
            throw APIError.decodingError(error)
        }
    }
}
