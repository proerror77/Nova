import Foundation

/// GraphQL API Client for Nova Social
class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.timeoutInterval
        config.timeoutIntervalForResource = APIConfig.timeoutInterval * 2
        self.session = URLSession(configuration: config)

        guard let url = URL(string: APIConfig.baseURL) else {
            fatalError("Invalid API base URL: \(APIConfig.baseURL)")
        }
        self.baseURL = url

        // Configure JSON decoder with ISO8601 date strategy
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        // Configure JSON encoder
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Authentication Token Management

    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: AuthKeys.accessToken) }
        set { UserDefaults.standard.set(newValue, forKey: AuthKeys.accessToken) }
    }

    var isAuthenticated: Bool {
        accessToken != nil
    }

    func saveAuthTokens(accessToken: String, refreshToken: String) {
        UserDefaults.standard.set(accessToken, forKey: AuthKeys.accessToken)
        UserDefaults.standard.set(refreshToken, forKey: AuthKeys.refreshToken)
    }

    func clearAuthTokens() {
        UserDefaults.standard.removeObject(forKey: AuthKeys.accessToken)
        UserDefaults.standard.removeObject(forKey: AuthKeys.refreshToken)
        UserDefaults.standard.removeObject(forKey: AuthKeys.userId)
    }

    // MARK: - GraphQL Request

    func query<T: Codable>(
        _ query: String,
        variables: [String: Any]? = nil,
        responseType: T.Type
    ) async throws -> T {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add authorization header if authenticated
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Build GraphQL request body
        let graphqlRequest = GraphQLRequest(
            query: query,
            variables: variables?.mapValues { AnyCodable($0) },
            operationName: nil
        )

        request.httpBody = try encoder.encode(graphqlRequest)

        if APIConfig.enableLogging {
            print("📤 GraphQL Request:")
            print("Query: \(query)")
            if let vars = variables {
                print("Variables: \(vars)")
            }
        }

        // Execute request
        let (data, response) = try await session.data(for: request)

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        if APIConfig.enableLogging {
            print("📥 GraphQL Response: HTTP \(httpResponse.statusCode)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIClientError.httpError(statusCode: httpResponse.statusCode)
        }

        // Parse GraphQL response
        let graphqlResponse = try decoder.decode(GraphQLResponse<T>.self, from: data)

        // Check for GraphQL errors
        if let errors = graphqlResponse.errors, !errors.isEmpty {
            let errorMessages = errors.map { $0.message }.joined(separator: ", ")
            throw APIClientError.graphQLError(message: errorMessages)
        }

        // Extract data
        guard let responseData = graphqlResponse.data else {
            throw APIClientError.noData
        }

        return responseData
    }

    // MARK: - REST Endpoint (for file uploads)

    func upload(
        image: Data,
        to endpoint: String
    ) async throws -> URL {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")

        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = image

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIClientError.uploadFailed
        }

        // Parse response to get image URL
        struct UploadResponse: Codable {
            let url: String
        }

        let uploadResponse = try decoder.decode(UploadResponse.self, from: data)
        guard let imageURL = URL(string: uploadResponse.url) else {
            throw APIClientError.invalidResponse
        }

        return imageURL
    }
}

// MARK: - API Client Errors

enum APIClientError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case graphQLError(message: String)
    case noData
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .graphQLError(let message):
            return "GraphQL error: \(message)"
        case .noData:
            return "No data received from server"
        case .uploadFailed:
            return "Failed to upload image"
        }
    }
}
