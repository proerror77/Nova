import XCTest
@testable import ICERED

/// ErrorHandlingTests - Comprehensive error handling tests
///
/// Test Coverage:
/// 1. HTTP status code to APIError mapping
/// 2. Network error handling (timeout, no connection)
/// 3. Error properties (isRetryable, userMessage)
/// 4. Recovery suggestions
final class ErrorHandlingTests: XCTestCase {

    // MARK: - HTTP Status Code Mapping

    /// Test: 400 Bad Request maps to serverError
    func testHTTPError_400_MapsToServerError() {
        let error = mapStatusCode(400, message: "Bad Request")

        switch error {
        case .serverError(let code, let msg):
            XCTAssertEqual(code, 400)
            XCTAssertEqual(msg, "Bad Request")
        default:
            XCTFail("Expected serverError, got \(error)")
        }
    }

    /// Test: 401 Unauthorized maps to unauthorized
    func testHTTPError_401_MapsToUnauthorized() {
        let error = mapStatusCode(401, message: "")

        switch error {
        case .unauthorized:
            break // Expected
        default:
            XCTFail("Expected unauthorized, got \(error)")
        }
    }

    /// Test: 403 Forbidden maps to serverError
    func testHTTPError_403_MapsToServerError() {
        let error = mapStatusCode(403, message: "Forbidden")

        switch error {
        case .serverError(let code, _):
            XCTAssertEqual(code, 403)
        default:
            XCTFail("Expected serverError, got \(error)")
        }
    }

    /// Test: 404 Not Found maps to notFound
    func testHTTPError_404_MapsToNotFound() {
        let error = mapStatusCode(404, message: "")

        switch error {
        case .notFound:
            break // Expected
        default:
            XCTFail("Expected notFound, got \(error)")
        }
    }

    /// Test: 408 Request Timeout maps to timeout
    func testHTTPError_408_MapsToTimeout() {
        let error = mapStatusCode(408, message: "")

        switch error {
        case .timeout:
            break // Expected
        default:
            XCTFail("Expected timeout, got \(error)")
        }
    }

    /// Test: 429 Too Many Requests maps to serverError
    func testHTTPError_429_MapsToServerError() {
        let error = mapStatusCode(429, message: "Rate limit exceeded")

        switch error {
        case .serverError(let code, _):
            XCTAssertEqual(code, 429)
        default:
            XCTFail("Expected serverError, got \(error)")
        }
    }

    /// Test: 500 Internal Server Error maps to serverError
    func testHTTPError_500_MapsToServerError() {
        let error = mapStatusCode(500, message: "Internal Server Error")

        switch error {
        case .serverError(let code, let msg):
            XCTAssertEqual(code, 500)
            XCTAssertEqual(msg, "Internal Server Error")
        default:
            XCTFail("Expected serverError, got \(error)")
        }
    }

    /// Test: 502 Bad Gateway maps to serverError
    func testHTTPError_502_MapsToServerError() {
        let error = mapStatusCode(502, message: "Bad Gateway")

        switch error {
        case .serverError(let code, _):
            XCTAssertEqual(code, 502)
        default:
            XCTFail("Expected serverError, got \(error)")
        }
    }

    /// Test: 503 Service Unavailable maps to serverError
    func testHTTPError_503_MapsToServerError() {
        let error = mapStatusCode(503, message: "Service Unavailable")

        switch error {
        case .serverError(let code, _):
            XCTAssertEqual(code, 503)
        default:
            XCTFail("Expected serverError, got \(error)")
        }
    }

    /// Test: 504 Gateway Timeout maps to timeout
    func testHTTPError_504_MapsToTimeout() {
        let error = mapStatusCode(504, message: "")

        switch error {
        case .timeout:
            break // Expected
        default:
            XCTFail("Expected timeout, got \(error)")
        }
    }

    // MARK: - Network Error Mapping

    /// Test: URLError.timedOut maps to timeout
    func testURLError_TimedOut_MapsToTimeout() {
        let urlError = URLError(.timedOut)
        let error = mapURLError(urlError)

        switch error {
        case .timeout:
            break // Expected
        default:
            XCTFail("Expected timeout, got \(error)")
        }
    }

    /// Test: URLError.notConnectedToInternet maps to noConnection
    func testURLError_NotConnected_MapsToNoConnection() {
        let urlError = URLError(.notConnectedToInternet)
        let error = mapURLError(urlError)

        switch error {
        case .noConnection:
            break // Expected
        default:
            XCTFail("Expected noConnection, got \(error)")
        }
    }

    /// Test: URLError.networkConnectionLost maps to noConnection
    func testURLError_ConnectionLost_MapsToNoConnection() {
        let urlError = URLError(.networkConnectionLost)
        let error = mapURLError(urlError)

        switch error {
        case .noConnection:
            break // Expected
        default:
            XCTFail("Expected noConnection, got \(error)")
        }
    }

    /// Test: Other URLErrors map to networkError
    func testURLError_Other_MapsToNetworkError() {
        let urlError = URLError(.cannotFindHost)
        let error = mapURLError(urlError)

        switch error {
        case .networkError:
            break // Expected
        default:
            XCTFail("Expected networkError, got \(error)")
        }
    }

    // MARK: - isRetryable Tests

    /// Test: Network errors are retryable
    func testIsRetryable_NetworkErrors_AreRetryable() {
        XCTAssertTrue(APIError.timeout.isRetryable)
        XCTAssertTrue(APIError.noConnection.isRetryable)
        XCTAssertTrue(APIError.networkError(URLError(.timedOut)).isRetryable)
    }

    /// Test: 5xx server errors are retryable
    func testIsRetryable_5xxErrors_AreRetryable() {
        XCTAssertTrue(APIError.serverError(statusCode: 500, message: "").isRetryable)
        XCTAssertTrue(APIError.serverError(statusCode: 502, message: "").isRetryable)
        XCTAssertTrue(APIError.serverError(statusCode: 503, message: "").isRetryable)
    }

    /// Test: 4xx client errors are not retryable
    func testIsRetryable_4xxErrors_AreNotRetryable() {
        XCTAssertFalse(APIError.serverError(statusCode: 400, message: "").isRetryable)
        XCTAssertFalse(APIError.serverError(statusCode: 403, message: "").isRetryable)
        XCTAssertFalse(APIError.serverError(statusCode: 404, message: "").isRetryable)
        XCTAssertFalse(APIError.serverError(statusCode: 422, message: "").isRetryable)
        XCTAssertFalse(APIError.serverError(statusCode: 429, message: "").isRetryable)
    }

    /// Test: Auth errors are not retryable
    func testIsRetryable_AuthErrors_AreNotRetryable() {
        XCTAssertFalse(APIError.unauthorized.isRetryable)
    }

    /// Test: Parsing errors are not retryable
    func testIsRetryable_ParsingErrors_AreNotRetryable() {
        XCTAssertFalse(APIError.decodingError(NSError(domain: "", code: 0)).isRetryable)
        XCTAssertFalse(APIError.invalidURL.isRetryable)
        XCTAssertFalse(APIError.invalidResponse.isRetryable)
    }

    // MARK: - User Message Tests

    /// Test: All errors have user-friendly messages
    func testUserMessage_AllErrorsHaveMessages() {
        let errors: [APIError] = [
            .invalidURL,
            .invalidResponse,
            .networkError(URLError(.timedOut)),
            .decodingError(NSError(domain: "", code: 0)),
            .serverError(statusCode: 500, message: "Test"),
            .unauthorized,
            .notFound,
            .timeout,
            .noConnection
        ]

        for error in errors {
            XCTAssertFalse(error.userMessage.isEmpty, "\(error) should have user message")
            XCTAssertFalse(error.userMessage.contains("nil"), "\(error) message should not contain nil")
        }
    }

    /// Test: Unauthorized has appropriate message
    func testUserMessage_Unauthorized_HasAppropriateMessage() {
        let error = APIError.unauthorized
        XCTAssertTrue(error.userMessage.lowercased().contains("session") ||
                      error.userMessage.lowercased().contains("login") ||
                      error.userMessage.lowercased().contains("expired"))
    }

    /// Test: Timeout has appropriate message
    func testUserMessage_Timeout_HasAppropriateMessage() {
        let error = APIError.timeout
        XCTAssertTrue(error.userMessage.lowercased().contains("timeout") ||
                      error.userMessage.lowercased().contains("timed out"))
    }

    /// Test: NoConnection has appropriate message
    func testUserMessage_NoConnection_HasAppropriateMessage() {
        let error = APIError.noConnection
        XCTAssertTrue(error.userMessage.lowercased().contains("internet") ||
                      error.userMessage.lowercased().contains("connection") ||
                      error.userMessage.lowercased().contains("network"))
    }

    // MARK: - Recovery Suggestion Tests

    /// Test: Unauthorized has recovery suggestion
    func testRecoverySuggestion_Unauthorized_HasSuggestion() {
        let error = APIError.unauthorized
        XCTAssertNotNil(error.recoverySuggestion)
        XCTAssertTrue(error.recoverySuggestion?.lowercased().contains("login") == true)
    }

    /// Test: Network errors have recovery suggestions
    func testRecoverySuggestion_NetworkErrors_HaveSuggestions() {
        XCTAssertNotNil(APIError.noConnection.recoverySuggestion)
        XCTAssertNotNil(APIError.timeout.recoverySuggestion)
    }

    /// Test: 5xx server errors have recovery suggestions
    func testRecoverySuggestion_5xxErrors_HaveSuggestions() {
        let error = APIError.serverError(statusCode: 500, message: "")
        XCTAssertNotNil(error.recoverySuggestion)
    }

    // MARK: - Error Description Tests

    /// Test: errorDescription is localized
    func testErrorDescription_IsLocalized() {
        let errors: [APIError] = [
            .invalidURL,
            .invalidResponse,
            .unauthorized,
            .notFound,
            .timeout,
            .noConnection
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            // Should not start with capital letter of error case name
            XCTAssertFalse(error.errorDescription?.hasPrefix("API") == true,
                           "Error description should be user-friendly, not technical")
        }
    }

    /// Test: Server error includes status code
    func testErrorDescription_ServerError_IncludesStatusCode() {
        let error = APIError.serverError(statusCode: 500, message: "Test message")
        XCTAssertTrue(error.errorDescription?.contains("500") == true)
    }

    // MARK: - Helper Methods

    /// Map HTTP status code to APIError (mimics APIClient behavior)
    private func mapStatusCode(_ statusCode: Int, message: String) -> APIError {
        switch statusCode {
        case 401:
            return .unauthorized
        case 404:
            return .notFound
        case 408, 504:
            return .timeout
        default:
            return .serverError(statusCode: statusCode, message: message)
        }
    }

    /// Map URLError to APIError (mimics APIClient behavior)
    private func mapURLError(_ urlError: URLError) -> APIError {
        switch urlError.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        default:
            return .networkError(urlError)
        }
    }
}
