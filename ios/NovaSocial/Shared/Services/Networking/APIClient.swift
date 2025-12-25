import Foundation

// MARK: - Request Deduplication Actor (Swift 6 Safe)
/// Actor for thread-safe request deduplication storage
private actor RequestDeduplicationStore {
    private var inflightRequests: [String: Task<Data, Error>] = [:]
    private var inflightMutations: [String: Task<Data, Error>] = [:]

    func getExistingTask(for key: String) -> Task<Data, Error>? {
        return inflightRequests[key]
    }

    func storeTask(_ task: Task<Data, Error>, for key: String) {
        inflightRequests[key] = task
    }

    func removeTask(for key: String) {
        inflightRequests.removeValue(forKey: key)
    }
    
    // MARK: - Mutation Deduplication (防止重複提交)
    
    func getExistingMutation(for key: String) -> Task<Data, Error>? {
        return inflightMutations[key]
    }
    
    func storeMutation(_ task: Task<Data, Error>, for key: String) {
        inflightMutations[key] = task
    }
    
    func removeMutation(for key: String) {
        inflightMutations.removeValue(forKey: key)
    }
}

// MARK: - API Client

/// Base HTTP client for all API requests
/// Handles authentication, JSON encoding/decoding, and error handling
/// Features:
/// - Automatic token refresh on 401 responses
/// - GET request deduplication (同時相同請求只發一次)
/// - Mutation deduplication to prevent double-submission (防止重複提交 POST/PUT/DELETE)
/// - Exponential backoff retry for transient errors
class APIClient {
    static let shared = APIClient()

    private let baseURL = APIConfig.current.baseURL

    /// Shared URLSession for all API requests - use this instead of creating new sessions
    private(set) var session: URLSession
    private var authToken: String?

    #if DEBUG
    /// Configure session for testing with custom protocol classes
    /// - Parameter protocolClasses: Array of URLProtocol subclasses to intercept requests
    func configureForTesting(protocolClasses: [AnyClass]) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = protocolClasses
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// Reset session to default configuration after testing
    func resetSessionToDefault() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.current.timeout
        config.timeoutIntervalForResource = APIConfig.current.resourceTimeout
        self.session = URLSession(configuration: config)
    }
    #endif

    // MARK: - Request Deduplication (請求去重) - Actor-based for Swift 6 compatibility
    private let deduplicationStore = RequestDeduplicationStore()

    // MARK: - Retry Configuration (重試配置)
    // Issue #9: Consolidated retry logic with exponential backoff
    // - Retries transient errors (network issues, timeouts, 5xx server errors)
    // - Uses exponential backoff: 0.5s, 1s, 2s (max 3 attempts)
    // - Adds jitter to prevent thundering herd
    private let maxRetryAttempts = 3
    private let baseRetryDelay: TimeInterval = 0.5  // 500ms base delay

    /// 可重試的錯誤類型
    private let retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.current.timeout
        config.timeoutIntervalForResource = APIConfig.current.resourceTimeout

        // Configure URLCache for HTTP response caching
        // Memory: 20MB, Disk: 100MB - reduces redundant network requests
        let cache = URLCache(
            memoryCapacity: 20_000_000,
            diskCapacity: 100_000_000,
            diskPath: "api_cache"
        )
        config.urlCache = cache
        config.requestCachePolicy = .useProtocolCachePolicy

        // HTTP/2 connection pooling optimization
        // Modern iOS uses HTTP/2 and HTTP/3 which handle connection multiplexing automatically
        // Max concurrent connections per host (default is 6, but explicit for clarity)
        config.httpMaximumConnectionsPerHost = 6
        // Enable connection reuse (keep-alive)
        config.httpShouldSetCookies = true
        // Allow cellular access
        config.allowsCellularAccess = true
        // Use HTTP/2 when available (default in modern iOS, but explicit)
        config.multipathServiceType = .none  // Multipath disabled for better HTTP/2 behavior

        self.session = URLSession(configuration: config)
    }

    // MARK: - Request Key Generation (生成請求唯一鍵)
    private func requestKey(for request: URLRequest) -> String {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        let bodyHash = request.httpBody?.hashValue ?? 0
        return "\(method):\(url):\(bodyHash)"
    }

    // MARK: - Exponential Backoff Delay (指數退避延遲)
    private func retryDelay(attempt: Int) -> TimeInterval {
        // Exponential backoff: 0.5s, 1s, 2s + jitter
        let exponentialDelay = baseRetryDelay * pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...0.3) * exponentialDelay
        return min(exponentialDelay + jitter, 10.0)  // Cap at 10 seconds
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

    /// Execute request with deduplication and retry
    /// - Deduplicates identical concurrent requests (只發送一次)
    /// - Deduplicates mutation requests to prevent double-submission (防止重複提交)
    /// - Retries transient errors with exponential backoff
    /// - Automatically attempts token refresh on 401
    private func executeRequest<T: Decodable>(
        _ request: URLRequest,
        isRetry: Bool = false,
        enableDeduplication: Bool = true
    ) async throws -> T {
        let key = requestKey(for: request)
        let method = request.httpMethod ?? "GET"

        // MARK: - GET Request Deduplication (Actor-based for Swift 6)
        if enableDeduplication && method == "GET" {
            // Check for inflight request
            if let existingTask = await deduplicationStore.getExistingTask(for: key) {
                #if DEBUG
                print("[API] 🔄 Deduplicating GET request: \(request.url?.path ?? "?")")
                #endif
                let data = try await existingTask.value
                return try decodeResponse(data)
            }

            // Create new task and store it
            let task = Task<Data, Error> {
                try await self.performRequestWithRetry(request, isTokenRetry: isRetry)
            }
            await deduplicationStore.storeTask(task, for: key)

            do {
                let data = try await task.value
                await deduplicationStore.removeTask(for: key)
                return try decodeResponse(data)
            } catch {
                await deduplicationStore.removeTask(for: key)
                throw error
            }
        }

        // MARK: - Mutation Deduplication (防止重複提交 POST/PUT/DELETE)
        // Prevents double-likes, double-follows, etc. from rapid taps
        if enableDeduplication && (method == "POST" || method == "PUT" || method == "DELETE") {
            // Check for inflight identical mutation
            if let existingTask = await deduplicationStore.getExistingMutation(for: key) {
                #if DEBUG
                print("[API] 🛡️ Blocking duplicate \(method) request: \(request.url?.path ?? "?")")
                #endif
                // Return the same result as the inflight mutation
                let data = try await existingTask.value
                return try decodeResponse(data)
            }

            // Create new mutation task and store it
            let task = Task<Data, Error> {
                try await self.performRequestWithRetry(request, isTokenRetry: isRetry)
            }
            await deduplicationStore.storeMutation(task, for: key)

            do {
                let data = try await task.value
                await deduplicationStore.removeMutation(for: key)
                return try decodeResponse(data)
            } catch {
                await deduplicationStore.removeMutation(for: key)
                throw error
            }
        }

        // Deduplication disabled - execute directly
        let data = try await performRequestWithRetry(request, isTokenRetry: isRetry)
        return try decodeResponse(data)
    }

    /// Perform request with exponential backoff retry
    private func performRequestWithRetry(
        _ request: URLRequest,
        isTokenRetry: Bool = false,
        attempt: Int = 0
    ) async throws -> Data {
        do {
            return try await performSingleRequest(request, isTokenRetry: isTokenRetry)
        } catch let error as APIError {
            // Check if error is retryable
            let shouldRetry = isRetryableError(error) && attempt < maxRetryAttempts

            if shouldRetry {
                let delay = retryDelay(attempt: attempt)
                #if DEBUG
                print("[API] ⏳ Retry \(attempt + 1)/\(maxRetryAttempts) after \(String(format: "%.2f", delay))s for: \(request.url?.path ?? "?")")
                #endif

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequestWithRetry(request, isTokenRetry: isTokenRetry, attempt: attempt + 1)
            }

            throw error
        } catch {
            // Network errors - check if retryable
            if attempt < maxRetryAttempts, isRetryableNetworkError(error) {
                let delay = retryDelay(attempt: attempt)
                #if DEBUG
                print("[API] ⏳ Network retry \(attempt + 1)/\(maxRetryAttempts) after \(String(format: "%.2f", delay))s")
                #endif

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                return try await performRequestWithRetry(request, isTokenRetry: isTokenRetry, attempt: attempt + 1)
            }

            throw error
        }
    }

    /// Check if API error is retryable
    private func isRetryableError(_ error: APIError) -> Bool {
        switch error {
        case .timeout, .serviceUnavailable:
            return true
        case .serverError(let statusCode, _):
            return retryableStatusCodes.contains(statusCode)
        default:
            return false
        }
    }

    /// Check if network error is retryable
    private func isRetryableNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    /// Perform single request (核心請求邏輯)
    private func performSingleRequest(_ request: URLRequest, isTokenRetry: Bool) async throws -> Data {
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
            return data
        case 401:
            // Parse error response for more details
            let errorBody = String(data: data, encoding: .utf8) ?? "No body"
            
            print("╔════════════════════════════════════════════════════════════")
            print("║ [API] ⚠️ 401 UNAUTHORIZED RECEIVED")
            print("║ URL: \(request.url?.absoluteString ?? "?")")
            print("║ Method: \(request.httpMethod ?? "?")")
            print("║ Is retry attempt: \(isTokenRetry)")
            print("║ Response body: \(errorBody.prefix(200))")
            print("╚════════════════════════════════════════════════════════════")
            
            // Attempt token refresh on 401, but only once to prevent infinite loops
            if !isTokenRetry {
                print("[API] 🔄 Attempting token refresh...")

                let refreshSucceeded = await AuthenticationManager.shared.attemptTokenRefresh()

                if refreshSucceeded {
                    print("[API] ✅ Token refreshed successfully, retrying original request...")

                    // Rebuild request with new token
                    var retryRequest = request
                    if let newToken = authToken {
                        retryRequest.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                        print("[API] 🔑 New token applied to retry request")
                    } else {
                        print("[API] ⚠️ Warning: No new token available after refresh")
                    }

                    // Retry with isTokenRetry=true to prevent infinite loop
                    return try await performSingleRequest(retryRequest, isTokenRetry: true)
                } else {
                    print("[API] ❌ Token refresh failed")
                }
            } else {
                print("[API] ❌ Already retried after refresh, not retrying again (prevents infinite loop)")
            }

            print("[API] 🚫 Throwing unauthorized error - user will be redirected to login")
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 408, 504:
            throw APIError.timeout
        case 429:
            // Rate limited - extract retry-after if available
            if let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After"),
               let seconds = Double(retryAfter) {
                #if DEBUG
                print("[API] Rate limited, retry after \(seconds)s")
                #endif
            }
            throw APIError.serverError(statusCode: 429, message: "Rate limited")
        case 503:
            throw APIError.serviceUnavailable
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
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
