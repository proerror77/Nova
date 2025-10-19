import Foundation

/// APIClient - 核心 HTTP 客户端
/// 职责：构建请求、发送请求、解析响应
/// 不负责：认证管理（AuthManager）、重试逻辑（RetryPolicy）
final class APIClient {
    // MARK: - Properties

    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Initialization

    init(
        baseURL: URL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session

        // 配置 JSON Decoder (处理后端的 snake_case 和 ISO8601 日期)
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .useDefaultKeys // 手动处理 CodingKeys
        self.decoder.dateDecodingStrategy = .iso8601

        // 配置 JSON Encoder
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .useDefaultKeys
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Public API

    /// 发送请求并返回解码后的响应
    func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        authenticated: Bool = true
    ) async throws -> T {
        let urlRequest = try buildRequest(endpoint, authenticated: authenticated)

        Logger.log("🌐 API Request: \(endpoint.method.rawValue) \(endpoint.path)", level: .debug)

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            Logger.log("✅ API Response: \(httpResponse.statusCode) \(endpoint.path)", level: .debug)

            // 处理 HTTP 错误
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.from(statusCode: httpResponse.statusCode, data: data)
            }

            // 解码响应
            do {
                let decoded = try decoder.decode(T.self, from: data)
                return decoded
            } catch {
                Logger.log("❌ Decoding Error: \(error)", level: .error)
                throw APIError.decodingError(error)
            }

        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.from(error: error)
        }
    }

    /// 发送请求并返回原始数据（用于图片上传等场景）
    func requestData(
        _ endpoint: APIEndpoint,
        authenticated: Bool = true
    ) async throws -> Data {
        let urlRequest = try buildRequest(endpoint, authenticated: authenticated)

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.from(statusCode: httpResponse.statusCode, data: data)
            }

            return data

        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.from(error: error)
        }
    }

    /// 发送无响应体的请求（用于 DELETE、logout 等）
    func requestNoResponse(
        _ endpoint: APIEndpoint,
        authenticated: Bool = true
    ) async throws {
        let urlRequest = try buildRequest(endpoint, authenticated: authenticated)

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.from(statusCode: httpResponse.statusCode, data: data)
            }

        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.from(error: error)
        }
    }

    // MARK: - Private Helpers

    private func buildRequest(
        _ endpoint: APIEndpoint,
        authenticated: Bool
    ) throws -> URLRequest {
        // 构建 URL
        var urlComponents = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false)

        // 添加 Query Parameters
        if let queryItems = endpoint.queryItems, !queryItems.isEmpty {
            urlComponents?.queryItems = queryItems
        }

        guard let url = urlComponents?.url else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = 30

        // 添加 Headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // 添加自定义 Headers
        endpoint.headers?.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        // 添加认证 Token
        if authenticated {
            if let accessToken = AuthManager.shared.accessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            } else {
                throw APIError.unauthorized
            }
        }

        // 添加 Body
        if let body = endpoint.body {
            request.httpBody = try encoder.encode(body)
        }

        return request
    }
}

// MARK: - APIEndpoint

/// API 端点定义
struct APIEndpoint {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]?
    let headers: [String: String]?
    let body: Encodable?

    init(
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String]? = nil,
        body: Encodable? = nil
    ) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }
}

// MARK: - HTTPMethod

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

// MARK: - AnyCodable (用于 Encodable body)

struct AnyCodable: Encodable {
    let value: Encodable

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
