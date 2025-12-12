import Foundation

// MARK: - API Error Definition

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case networkError(Error)
    case decodingError(Error)
    case serverError(statusCode: Int, message: String)
    case unauthorized
    case notFound
    case timeout
    case noConnection
    case serviceUnavailable

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL"
        case .invalidResponse:
            return "Invalid server response"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError:
            return "Failed to process server response"
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .unauthorized:
            return "Session expired. Please login again."
        case .notFound:
            return "The requested resource was not found"
        case .timeout:
            return "Request timed out. Please try again."
        case .noConnection:
            return "No internet connection. Please check your network."
        case .serviceUnavailable:
            return "Service temporarily unavailable. Please try again later."
        }
    }

    var failureReason: String? {
        switch self {
        case .unauthorized:
            return "Your authentication token has expired or is invalid."
        case .networkError:
            return "Could not connect to the server."
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        default:
            return nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unauthorized:
            return "Please login again to continue."
        case .networkError, .noConnection:
            return "Check your internet connection and try again."
        case .timeout:
            return "The server is taking too long to respond. Try again later."
        case .serverError(let statusCode, _) where statusCode >= 500:
            return "The server is experiencing issues. Try again later."
        default:
            return nil
        }
    }

    // MARK: - User-Friendly Message

    /// Returns a user-friendly message suitable for display in UI
    var userMessage: String {
        errorDescription ?? "An unexpected error occurred"
    }

    /// Returns true if the error is recoverable by retrying
    var isRetryable: Bool {
        switch self {
        case .networkError, .timeout, .noConnection:
            return true
        case .serverError(let statusCode, _):
            return statusCode >= 500
        default:
            return false
        }
    }
}
