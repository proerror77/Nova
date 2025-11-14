import Foundation

// MARK: - API Error Definition

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case serverError(statusCode: Int, message: String)
    case unauthorized
    case notFound
}
