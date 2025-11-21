import Foundation

// MARK: - API Client

/// Base HTTP client for all API requests
/// Handles authentication, JSON encoding/decoding, and error handling
class APIClient {
    static let shared = APIClient()

    private var baseURL: String {
        APIConfig.current.baseURL
    }

    private let session: URLSession
    private var authToken: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.current.timeout
        config.timeoutIntervalForResource = 300

        // Staging traffic must bypass any system HTTP proxies (e.g., macOS global/Charles)
        // or ELB will reply 502 with a Proxy-Connection header before reaching ingress.
        if APIConfig.current == .staging {
            config.connectionProxyDictionary = [:]
        }

        self.session = URLSession(configuration: config)
    }

    func setAuthToken(_ token: String) {
        self.authToken = token
    }

    /// Enable mock authentication for development/testing
    /// WARNING: This is a temporary solution for testing only
    /// TODO: Replace with real authentication flow once identity-service HTTP API is available
    func enableMockAuth() {
        #if DEBUG
        self.authToken = "mock-dev-token-for-testing"
        print("⚠️ Mock authentication enabled - for testing only!")
        #endif
    }

    // MARK: - Generic Request Method

    func request<T: Decodable>(
        endpoint: String,
        method: String = "POST",
        body: Encodable? = nil,
        allowRetry: Bool = true
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            print("❌ Invalid URL: \(baseURL)\(endpoint)")
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Set Host header for Ingress routing (required for staging environment)
        if APIConfig.current == .staging {
            request.setValue("api.nova.local", forHTTPHeaderField: "Host")
        }

        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            do {
                request.httpBody = try JSONEncoder().encode(body)

                // 🔍 Debug logging
                #if DEBUG
                print("📤 === API REQUEST ===")
                print("📤 URL: \(url.absoluteString)")
                print("📤 Method: \(method)")
                print("📤 Headers: \(request.allHTTPHeaderFields ?? [:])")
                if let bodyString = String(data: request.httpBody!, encoding: .utf8) {
                    print("📤 Body: \(bodyString)")
                }
                print("📤 ===================")
                #endif
            } catch {
                print("❌ JSON Encoding Error: \(error)")
                throw APIError.decodingError(error)
            }
        } else {
            #if DEBUG
            print("📤 === API REQUEST ===")
            print("📤 URL: \(url.absoluteString)")
            print("📤 Method: \(method)")
            print("📤 Headers: \(request.allHTTPHeaderFields ?? [:])")
            print("📤 Body: (none)")
            print("📤 ===================")
            #endif
        }

        do {
            let (data, response) = try await session.data(for: request)

            // 🔍 Debug logging
            #if DEBUG
            print("📥 === API RESPONSE ===")
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Status: \(httpResponse.statusCode)")
                print("📥 Headers: \(httpResponse.allHeaderFields)")
            }
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Body: \(responseString)")
            }
            print("📥 ===================")
            #endif

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                throw APIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let decoder = JSONDecoder()
                    return try decoder.decode(T.self, from: data)
                } catch {
                    print("❌ JSON Decoding Error: \(error)")
                    throw APIError.decodingError(error)
                }
            case 401:
                print("❌ 401 Unauthorized")
                // 尝试刷新 token 一次，然后重试原请求
                if allowRetry {
                    let refreshed = await AuthenticationManager.shared.refreshSessionIfPossible()
                    if refreshed {
                        return try await request(
                            endpoint: endpoint,
                            method: method,
                            body: body,
                            allowRetry: false
                        )
                    }
                }
                throw APIError.unauthorized
            case 404:
                print("❌ 404 Not Found")
                throw APIError.notFound
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("❌ Server Error \(httpResponse.statusCode): \(message)")
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
            }
        } catch let error as APIError {
            print("❌ APIError: \(error)")
            throw error
        } catch let urlError as URLError {
            print("❌ URLError: \(urlError)")
            print("❌ URLError Code: \(urlError.code.rawValue)")
            print("❌ URLError Description: \(urlError.localizedDescription)")
            if let failingURL = urlError.failureURLString {
                print("❌ Failing URL: \(failingURL)")
            }
            throw APIError.networkError(urlError)
        } catch {
            print("❌ Unknown Error: \(error)")
            throw APIError.networkError(error)
        }
    }
}
