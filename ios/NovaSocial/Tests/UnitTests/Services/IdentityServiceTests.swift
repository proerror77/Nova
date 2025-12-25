import XCTest
@testable import ICERED

/// IdentityServiceTests - Identity and authentication service tests
///
/// Test Coverage:
/// 1. Login success and failure scenarios
/// 2. Registration flow
/// 3. Token refresh
/// 4. Logout
/// 5. User profile operations
final class IdentityServiceTests: XCTestCase {

    // MARK: - Properties

    var session: URLSession!
    var identityService: IdentityService!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        // Configure APIClient to use MockURLProtocol for testing
        APIClient.shared.configureForTesting(protocolClasses: [MockURLProtocol.self])
        session = MockURLProtocol.createMockSession()
        identityService = IdentityService()
        MockURLProtocol.reset()
        APIClient.shared.setAuthToken("")
    }

    override func tearDown() {
        MockURLProtocol.reset()
        APIClient.shared.resetSessionToDefault()
        APIClient.shared.setAuthToken("")
        super.tearDown()
    }

    // MARK: - Login Tests

    /// Test: Successful login returns AuthResponse
    func testLogin_Success_ReturnsAuthResponse() async throws {
        // Given
        let expectedUser = TestFixtures.makeUserProfile(
            id: "user123",
            username: "testuser",
            email: "test@example.com"
        )
        let expectedResponse = TestFixtures.makeAuthResponse(
            token: "access_token_123",
            refreshToken: "refresh_token_456",
            user: expectedUser
        )

        try MockURLProtocol.mockJSON(expectedResponse)

        // When
        let response = try await identityService.login(
            username: "testuser",
            password: "password123"
        )

        // Then
        XCTAssertEqual(response.accessToken, "access_token_123")
        XCTAssertEqual(response.refreshToken, "refresh_token_456")
        XCTAssertEqual(response.user.id, "user123")
        XCTAssertEqual(response.user.username, "testuser")
    }

    /// Test: Login sets auth token in APIClient
    func testLogin_Success_SetsAuthToken() async throws {
        // Given
        let response = TestFixtures.makeAuthResponse(token: "new_auth_token")
        try MockURLProtocol.mockJSON(response)

        // When
        _ = try await identityService.login(username: "user", password: "pass")

        // Then
        XCTAssertEqual(APIClient.shared.getAuthToken(), "new_auth_token")
    }

    /// Test: Login with invalid credentials throws unauthorized
    func testLogin_InvalidCredentials_ThrowsUnauthorized() async {
        // Given
        MockURLProtocol.mockError(statusCode: 401)

        // When/Then
        do {
            _ = try await identityService.login(username: "user", password: "wrong")
            XCTFail("Should throw unauthorized error")
        } catch let error as APIError {
            switch error {
            case .unauthorized:
                break // Expected
            default:
                XCTFail("Expected unauthorized error, got \(error)")
            }
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    /// Test: Login request includes correct body
    func testLogin_RequestBody_IsCorrect() async throws {
        // Given
        let response = TestFixtures.makeAuthResponse()
        try MockURLProtocol.mockJSON(response)

        // When
        _ = try await identityService.login(username: "myuser", password: "mypass")

        // Then
        let request = MockURLProtocol.recordedRequests.first
        XCTAssertNotNil(request)

        if let body = request?.httpBody {
            let decoder = JSONDecoder()
            struct LoginRequest: Codable {
                let username: String
                let password: String
            }
            let parsed = try decoder.decode(LoginRequest.self, from: body)
            XCTAssertEqual(parsed.username, "myuser")
            XCTAssertEqual(parsed.password, "mypass")
        } else {
            XCTFail("Request should have body")
        }
    }

    // MARK: - Registration Tests

    /// Test: Successful registration returns AuthResponse
    func testRegister_Success_ReturnsAuthResponse() async throws {
        // Given
        let expectedUser = TestFixtures.makeUserProfile(
            id: "new_user_id",
            username: "newuser",
            email: "new@example.com",
            displayName: "New User"
        )
        let expectedResponse = TestFixtures.makeAuthResponse(
            token: "new_access_token",
            refreshToken: "new_refresh_token",
            user: expectedUser
        )

        try MockURLProtocol.mockJSON(expectedResponse)

        // When
        let response = try await identityService.register(
            username: "newuser",
            email: "new@example.com",
            password: "password123",
            displayName: "New User",
            inviteCode: "INVITE123"
        )

        // Then
        XCTAssertEqual(response.accessToken, "new_access_token")
        XCTAssertEqual(response.user.username, "newuser")
    }

    /// Test: Registration with existing email throws error
    func testRegister_ExistingEmail_ThrowsError() async {
        // Given
        MockURLProtocol.mockError(
            statusCode: 409,
            errorData: "{\"error\":\"Email already exists\"}".data(using: .utf8)
        )

        // When/Then
        do {
            _ = try await identityService.register(
                username: "user",
                email: "existing@example.com",
                password: "pass",
                displayName: "Name"
            )
            XCTFail("Should throw error")
        } catch let error as APIError {
            switch error {
            case .serverError(let code, _):
                XCTAssertEqual(code, 409)
            default:
                XCTFail("Expected serverError, got \(error)")
            }
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    /// Test: Registration request includes invite code
    func testRegister_RequestBody_IncludesInviteCode() async throws {
        // Given
        let response = TestFixtures.makeAuthResponse()
        try MockURLProtocol.mockJSON(response)

        // When
        _ = try await identityService.register(
            username: "user",
            email: "email@test.com",
            password: "pass",
            displayName: "Display",
            inviteCode: "SPECIAL_CODE"
        )

        // Then
        let request = MockURLProtocol.recordedRequests.first
        XCTAssertNotNil(request)

        if let body = request?.httpBody {
            let bodyString = String(data: body, encoding: .utf8) ?? ""
            XCTAssertTrue(bodyString.contains("SPECIAL_CODE") ||
                          bodyString.contains("invite_code"))
        }
    }

    // MARK: - Token Refresh Tests

    /// Test: Successful token refresh returns new tokens
    func testRefreshToken_Success_ReturnsNewTokens() async throws {
        // Given
        let newResponse = TestFixtures.makeAuthResponse(
            token: "refreshed_access_token",
            refreshToken: "refreshed_refresh_token"
        )
        try MockURLProtocol.mockJSON(newResponse)

        // When
        let response = try await identityService.refreshToken(
            refreshToken: "old_refresh_token"
        )

        // Then
        XCTAssertEqual(response.accessToken, "refreshed_access_token")
    }

    /// Test: Token refresh with expired token throws unauthorized
    func testRefreshToken_ExpiredToken_ThrowsUnauthorized() async {
        // Given
        MockURLProtocol.mockError(statusCode: 401)

        // When/Then
        do {
            _ = try await identityService.refreshToken(refreshToken: "expired_token")
            XCTFail("Should throw unauthorized error")
        } catch let error as APIError {
            switch error {
            case .unauthorized:
                break // Expected
            default:
                XCTFail("Expected unauthorized error, got \(error)")
            }
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    /// Test: Token refresh updates APIClient token
    func testRefreshToken_Success_UpdatesAPIClientToken() async throws {
        // Given
        APIClient.shared.setAuthToken("old_token")
        let response = TestFixtures.makeAuthResponse(token: "brand_new_token")
        try MockURLProtocol.mockJSON(response)

        // When
        _ = try await identityService.refreshToken(refreshToken: "refresh")

        // Then
        XCTAssertEqual(APIClient.shared.getAuthToken(), "brand_new_token")
    }

    // MARK: - Logout Tests

    /// Test: Logout clears APIClient token
    func testLogout_ClearsAPIClientToken() async throws {
        // Given
        APIClient.shared.setAuthToken("existing_token")
        MockURLProtocol.mockSuccess(statusCode: 204)

        // When
        try await identityService.logout()

        // Then
        let token = APIClient.shared.getAuthToken()
        XCTAssertTrue(token == nil || token?.isEmpty == true)
    }

    // MARK: - Get User Tests

    /// Test: Get user returns user profile
    func testGetUser_Success_ReturnsUserProfile() async throws {
        // Given
        struct GetUserResponse: Codable {
            let user: UserProfile
        }

        let expectedUser = TestFixtures.makeUserProfile(
            id: "user_456",
            username: "retrieved_user",
            displayName: "Retrieved User"
        )

        try MockURLProtocol.mockJSON(GetUserResponse(user: expectedUser))

        // When
        let user = try await identityService.getUser(userId: "user_456")

        // Then
        XCTAssertEqual(user.id, "user_456")
        XCTAssertEqual(user.username, "retrieved_user")
        XCTAssertEqual(user.displayName, "Retrieved User")
    }

    /// Test: Get user with non-existent ID throws not found
    func testGetUser_NotFound_ThrowsNotFound() async {
        // Given
        MockURLProtocol.mockError(statusCode: 404)

        // When/Then
        do {
            _ = try await identityService.getUser(userId: "nonexistent")
            XCTFail("Should throw notFound error")
        } catch let error as APIError {
            switch error {
            case .notFound:
                break // Expected
            default:
                XCTFail("Expected notFound error, got \(error)")
            }
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    // MARK: - Network Error Tests

    /// Test: Network timeout during login throws timeout error
    func testLogin_NetworkTimeout_ThrowsTimeout() async {
        // Given
        MockURLProtocol.mockTimeout()

        // When/Then
        do {
            _ = try await identityService.login(username: "user", password: "pass")
            XCTFail("Should throw timeout error")
        } catch let error as APIError {
            switch error {
            case .timeout:
                break // Expected
            default:
                XCTFail("Expected timeout error, got \(error)")
            }
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    /// Test: No connection during registration throws noConnection error
    func testRegister_NoConnection_ThrowsNoConnection() async {
        // Given
        MockURLProtocol.mockNoConnection()

        // When/Then
        do {
            _ = try await identityService.register(
                username: "user",
                email: "email@test.com",
                password: "pass",
                displayName: "Name"
            )
            XCTFail("Should throw noConnection error")
        } catch let error as APIError {
            switch error {
            case .noConnection:
                break // Expected
            default:
                XCTFail("Expected noConnection error, got \(error)")
            }
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }
}
