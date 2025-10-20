import Foundation

/// Errors that can occur during API communication
enum APIError: LocalizedError, Sendable {
    case networkError(URLError)
    case decodingError(DecodingError)
    case serverError(statusCode: Int, message: String)
    case rateLimited(retryAfter: Int)
    case unauthorized
    case notFound
    case invalidRequest(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError:
            return "Failed to decode response from server"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .rateLimited(let retryAfter):
            return "Too many requests. Please retry after \(retryAfter) seconds"
        case .unauthorized:
            return "Authentication required or token invalid"
        case .notFound:
            return "Requested resource not found"
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Check your internet connection and try again"
        case .decodingError:
            return "The server response was invalid. Please try again later"
        case .serverError(let code, _) where code >= 500:
            return "The server is experiencing issues. Please try again later"
        case .rateLimited:
            return "Please wait before making another request"
        case .unauthorized:
            return "Please sign in again with your credentials"
        case .notFound:
            return "The requested resource does not exist"
        case .invalidRequest:
            return "Please check your request and try again"
        default:
            return nil
        }
    }
}
