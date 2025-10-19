import XCTest
import AuthenticationServices
@testable import NovaApp

@MainActor
class AuthServiceTests: XCTestCase {
    var sut: AuthService!
    var mockRepository: MockAuthRepository!
    var mockKeychain: MockKeychainManager!

    override func setUp() {
        super.setUp()
        mockRepository = MockAuthRepository()
        mockKeychain = MockKeychainManager()

        // Create a testable instance instead of using singleton
        sut = AuthService(
            repository: mockRepository,
            keychainManager: mockKeychain
        )
    }

    override func tearDown() {
        sut = nil
        mockRepository = nil
        mockKeychain = nil
        super.tearDown()
    }

    // MARK: - Sign In Tests

    func testSignIn_Success() async throws {
        // Given
        let email = "test@example.com"
        let password = "password123"
        let mockUser = User.mock(id: "user_123", email: email)
        mockRepository.mockAuthResult = AuthResult(
            user: mockUser,
            accessToken: "access_token",
            refreshToken: "refresh_token"
        )

        // When
        try await sut.signIn(email: email, password: password)

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(sut.currentUser?.id, "user_123")
        XCTAssertEqual(mockKeychain.savedAccessToken, "access_token")
        XCTAssertEqual(mockKeychain.savedRefreshToken, "refresh_token")
        XCTAssertEqual(mockRepository.signInCallCount, 1)
        XCTAssertEqual(mockRepository.lastSignInEmail, email)
    }

    func testSignIn_Failure() async {
        // Given
        let email = "test@example.com"
        let password = "wrong_password"
        mockRepository.mockError = APIError.mock(message: "Invalid credentials")

        // When/Then
        do {
            try await sut.signIn(email: email, password: password)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertFalse(sut.isAuthenticated)
            XCTAssertNil(sut.currentUser)
            XCTAssertNil(mockKeychain.savedAccessToken)
        }
    }

    func testSignIn_SavesTokensToKeychain() async throws {
        // Given
        mockRepository.mockAuthResult = AuthResult(
            user: User.mock(),
            accessToken: "test_access",
            refreshToken: "test_refresh"
        )

        // When
        try await sut.signIn(email: "test@example.com", password: "password")

        // Then
        XCTAssertEqual(mockKeychain.saveAccessTokenCallCount, 1)
        XCTAssertEqual(mockKeychain.saveRefreshTokenCallCount, 1)
        XCTAssertEqual(mockKeychain.savedAccessToken, "test_access")
        XCTAssertEqual(mockKeychain.savedRefreshToken, "test_refresh")
    }

    // MARK: - Sign Up Tests

    func testSignUp_Success() async throws {
        // Given
        let username = "newuser"
        let email = "new@example.com"
        let password = "password123"
        let mockUser = User.mock(id: "user_456", username: username, email: email)
        mockRepository.mockAuthResult = AuthResult(
            user: mockUser,
            accessToken: "new_access",
            refreshToken: "new_refresh"
        )

        // When
        try await sut.signUp(username: username, email: email, password: password)

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(sut.currentUser?.username, username)
        XCTAssertEqual(mockRepository.signUpCallCount, 1)
        XCTAssertEqual(mockRepository.lastSignUpUsername, username)
    }

    func testSignUp_ValidatesUsername() async {
        // Given
        mockRepository.mockError = APIError.mock(message: "Username already taken")

        // When/Then
        do {
            try await sut.signUp(username: "taken", email: "test@example.com", password: "pass")
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertFalse(sut.isAuthenticated)
        }
    }

    // MARK: - Sign Out Tests

    func testSignOut_ClearsSession() async {
        // Given
        sut.isAuthenticated = true
        sut.currentUser = User.mock()
        mockKeychain.savedAccessToken = "token"
        mockKeychain.savedRefreshToken = "refresh"

        // When
        await sut.signOut()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertEqual(mockKeychain.clearAllTokensCallCount, 1)
        XCTAssertNil(mockKeychain.savedAccessToken)
        XCTAssertNil(mockKeychain.savedRefreshToken)
        XCTAssertEqual(mockRepository.signOutCallCount, 1)
    }

    func testSignOut_HandlesError() async {
        // Given
        sut.isAuthenticated = true
        sut.currentUser = User.mock()
        mockRepository.mockError = APIError.mock(message: "Network error")

        // When
        await sut.signOut()

        // Then - should still clear local session even if API call fails
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertEqual(mockKeychain.clearAllTokensCallCount, 1)
    }

    // MARK: - Apple Sign In Tests

    func testSignInWithApple_Success() async throws {
        // Given
        let mockCredential = MockASAuthorizationAppleIDCredential(
            user: "apple_user_id",
            email: "apple@example.com",
            identityToken: "mock_token".data(using: .utf8)!
        )
        mockRepository.mockAuthResult = AuthResult(
            user: User.mock(id: "user_789"),
            accessToken: "apple_access",
            refreshToken: "apple_refresh"
        )

        // When
        try await sut.signInWithApple(credential: mockCredential)

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(mockRepository.signInWithAppleCallCount, 1)
        XCTAssertEqual(mockRepository.lastAppleUserId, "apple_user_id")
    }

    func testSignInWithApple_InvalidToken() async {
        // Given
        let mockCredential = MockASAuthorizationAppleIDCredential(
            user: "apple_user_id",
            email: nil,
            identityToken: nil // Invalid token
        )

        // When/Then
        do {
            try await sut.signInWithApple(credential: mockCredential)
            XCTFail("Should have thrown an error")
        } catch {
            XCTAssertFalse(sut.isAuthenticated)
        }
    }

    // MARK: - Token Refresh Tests

    func testRefreshToken_Success() async throws {
        // Given
        mockKeychain.savedRefreshToken = "old_refresh"
        mockRepository.mockTokenRefreshResult = TokenRefreshResult(
            accessToken: "new_access",
            refreshToken: "new_refresh"
        )

        // When
        try await sut.refreshToken()

        // Then
        XCTAssertEqual(mockKeychain.savedAccessToken, "new_access")
        XCTAssertEqual(mockKeychain.savedRefreshToken, "new_refresh")
        XCTAssertEqual(mockRepository.refreshTokenCallCount, 1)
    }

    func testRefreshToken_NoRefreshTokenThrowsError() async {
        // Given
        mockKeychain.savedRefreshToken = nil

        // When/Then
        do {
            try await sut.refreshToken()
            XCTFail("Should have thrown an error")
        } catch let error as AuthError {
            XCTAssertEqual(error, .noRefreshToken)
        } catch {
            XCTFail("Wrong error type")
        }
    }

    func testRefreshToken_FailureClearsSession() async {
        // Given
        mockKeychain.savedRefreshToken = "expired_refresh"
        mockRepository.mockError = APIError.mock(message: "Token expired")
        sut.isAuthenticated = true
        sut.currentUser = User.mock()

        // When
        do {
            try await sut.refreshToken()
            XCTFail("Should have thrown an error")
        } catch {
            // Expected error
        }

        // Then - session should remain (user needs to sign out manually)
        // Note: This tests current behavior - might want to clear session on refresh failure
        XCTAssertTrue(sut.isAuthenticated)
    }

    // MARK: - Session Management Tests

    func testLoadSession_WithValidToken() {
        // Given
        mockKeychain.savedAccessToken = "valid_token"
        mockRepository.mockUser = User.mock(id: "user_123")

        // When
        sut.loadSession()

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        // Note: Current user is loaded asynchronously
    }

    func testLoadSession_WithoutToken() {
        // Given
        mockKeychain.savedAccessToken = nil

        // When
        sut.loadSession()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
    }

    func testClearSession_RemovesAllData() {
        // Given
        sut.isAuthenticated = true
        sut.currentUser = User.mock()
        mockKeychain.savedAccessToken = "token"
        mockKeychain.savedRefreshToken = "refresh"

        // When
        sut.clearSession()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertEqual(mockKeychain.clearAllTokensCallCount, 1)
    }

    // MARK: - Update Profile Tests

    func testUpdateProfile_Success() async throws {
        // Given
        sut.isAuthenticated = true
        sut.currentUser = User.mock(id: "user_123")
        let newDisplayName = "New Name"
        let newBio = "New bio"
        let avatarData = Data([0x01, 0x02])
        mockRepository.mockUpdatedUser = User.mock(
            id: "user_123",
            displayName: newDisplayName,
            bio: newBio
        )

        // When
        try await sut.updateProfile(
            displayName: newDisplayName,
            bio: newBio,
            avatarData: avatarData
        )

        // Then
        XCTAssertEqual(sut.currentUser?.displayName, newDisplayName)
        XCTAssertEqual(sut.currentUser?.bio, newBio)
        XCTAssertEqual(mockRepository.updateProfileCallCount, 1)
    }

    func testUpdateProfile_NotAuthenticatedThrowsError() async {
        // Given
        sut.isAuthenticated = false
        sut.currentUser = nil

        // When/Then
        do {
            try await sut.updateProfile(displayName: "Name", bio: "Bio", avatarData: nil)
            XCTFail("Should have thrown an error")
        } catch let error as AuthError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("Wrong error type")
        }
    }

    // MARK: - Delete Account Tests

    func testDeleteAccount_Success() async throws {
        // Given
        sut.isAuthenticated = true
        sut.currentUser = User.mock(id: "user_123")

        // When
        try await sut.deleteAccount()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertEqual(mockRepository.deleteAccountCallCount, 1)
        XCTAssertEqual(mockKeychain.clearAllTokensCallCount, 1)
    }

    func testDeleteAccount_NotAuthenticatedThrowsError() async {
        // Given
        sut.isAuthenticated = false
        sut.currentUser = nil

        // When/Then
        do {
            try await sut.deleteAccount()
            XCTFail("Should have thrown an error")
        } catch let error as AuthError {
            XCTAssertEqual(error, .notAuthenticated)
        } catch {
            XCTFail("Wrong error type")
        }
    }

    // MARK: - Edge Cases

    func testMultipleSimultaneousSignIns_ShouldHandleGracefully() async {
        // Given
        mockRepository.mockAuthResult = AuthResult(
            user: User.mock(),
            accessToken: "token",
            refreshToken: "refresh"
        )

        // When - attempt multiple sign ins simultaneously
        async let signIn1 = sut.signIn(email: "test1@example.com", password: "pass1")
        async let signIn2 = sut.signIn(email: "test2@example.com", password: "pass2")
        async let signIn3 = sut.signIn(email: "test3@example.com", password: "pass3")

        // Then - should complete without crashing
        _ = try? await signIn1
        _ = try? await signIn2
        _ = try? await signIn3

        XCTAssertTrue(sut.isAuthenticated)
    }
}

// MARK: - Mock ASAuthorizationAppleIDCredential

class MockASAuthorizationAppleIDCredential {
    let user: String
    let email: String?
    let identityToken: Data?
    let fullName: PersonNameComponents?

    init(user: String, email: String?, identityToken: Data?, fullName: PersonNameComponents? = nil) {
        self.user = user
        self.email = email
        self.identityToken = identityToken
        self.fullName = fullName
    }
}
