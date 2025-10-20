import XCTest
import AuthenticationServices
@testable import NovaApp

@MainActor
class AuthServiceTests: XCTestCase {
    var sut: AuthService!
    var mockRepository: MockAuthRepository!
    var mockKeychainManager: MockKeychainManager!

    override func setUp() {
        super.setUp()
        mockRepository = MockAuthRepository()
        mockKeychainManager = MockKeychainManager()
        sut = AuthService(
            repository: mockRepository,
            keychainManager: mockKeychainManager
        )
    }

    override func tearDown() {
        sut = nil
        mockRepository = nil
        mockKeychainManager = nil
        super.tearDown()
    }

    // MARK: - Sign In Tests

    func testSignIn_Success() async throws {
        // Given
        let email = "test@example.com"
        let password = "SecurePass123"
        let mockUser = User.mock(username: "testuser")
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "access_token_123",
            refreshToken: "refresh_token_456",
            user: mockUser
        )

        // When
        try await sut.signIn(email: email, password: password)

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(sut.currentUser?.id, mockUser.id)
        XCTAssertEqual(mockRepository.signInCallCount, 1)
        XCTAssertEqual(mockRepository.lastSignInEmail, email)
        XCTAssertEqual(mockKeychainManager.savedAccessToken, "access_token_123")
        XCTAssertEqual(mockKeychainManager.savedRefreshToken, "refresh_token_456")
    }

    func testSignIn_InvalidCredentials() async {
        // Given
        mockRepository.mockError = AuthError.invalidCredential

        // When/Then
        await XCTAssertAsyncThrows(
            try await sut.signIn(email: "test@example.com", password: "wrong"),
            expectedError: AuthError.self
        )

        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
    }

    func testSignIn_NetworkError() async {
        // Given
        mockRepository.mockError = APIError.networkError(
            NSError(domain: "test", code: -1)
        )

        // When/Then
        await XCTAssertAsyncThrows(
            try await sut.signIn(email: "test@example.com", password: "password"),
            expectedError: APIError.self
        )

        XCTAssertFalse(sut.isAuthenticated)
    }

    // MARK: - Sign Up Tests

    func testSignUp_Success() async throws {
        // Given
        let username = "newuser"
        let email = "new@example.com"
        let password = "SecurePass123"
        let mockUser = User.mock(username: username)
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "new_access",
            refreshToken: "new_refresh",
            user: mockUser
        )

        // When
        try await sut.signUp(username: username, email: email, password: password)

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertEqual(sut.currentUser?.username, username)
        XCTAssertEqual(mockRepository.signUpCallCount, 1)
        XCTAssertEqual(mockRepository.lastSignUpUsername, username)
        XCTAssertEqual(mockRepository.lastSignUpEmail, email)
    }

    func testSignUp_DuplicateUsername() async {
        // Given
        mockRepository.mockError = APIError.serverError(409) // Conflict

        // When/Then
        await XCTAssertAsyncThrows(
            try await sut.signUp(
                username: "existing",
                email: "test@example.com",
                password: "password"
            ),
            expectedError: APIError.self
        )

        XCTAssertFalse(sut.isAuthenticated)
    }

    func testSignUp_InvalidEmail() async {
        // Given
        mockRepository.mockError = APIError.serverError(400) // Bad Request

        // When/Then
        await XCTAssertAsyncThrows(
            try await sut.signUp(
                username: "user",
                email: "invalid-email",
                password: "password"
            ),
            expectedError: APIError.self
        )
    }

    // MARK: - Sign Out Tests

    func testSignOut_Success() async {
        // Given
        sut.isAuthenticated = true
        sut.currentUser = User.mock()
        mockKeychainManager.savedAccessToken = "token"
        mockKeychainManager.savedRefreshToken = "refresh"

        // When
        await sut.signOut()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertTrue(mockKeychainManager.didClearTokens)
        XCTAssertEqual(mockRepository.signOutCallCount, 1)
    }

    func testSignOut_ClearsSessionEvenOnError() async {
        // Given
        sut.isAuthenticated = true
        sut.currentUser = User.mock()
        mockRepository.mockError = APIError.networkError(
            NSError(domain: "test", code: -1)
        )

        // When
        await sut.signOut()

        // Then - should clear local session even if API call fails
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertTrue(mockKeychainManager.didClearTokens)
    }

    // MARK: - Token Refresh Tests

    func testRefreshToken_Success() async throws {
        // Given
        mockKeychainManager.savedRefreshToken = "old_refresh"
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "new_access",
            refreshToken: "new_refresh",
            user: User.mock()
        )

        // When
        try await sut.refreshToken()

        // Then
        XCTAssertEqual(mockRepository.refreshTokenCallCount, 1)
        XCTAssertEqual(mockKeychainManager.savedAccessToken, "new_access")
        XCTAssertEqual(mockKeychainManager.savedRefreshToken, "new_refresh")
    }

    func testRefreshToken_NoRefreshToken() async {
        // Given
        mockKeychainManager.savedRefreshToken = nil

        // When/Then
        await XCTAssertAsyncThrows(
            try await sut.refreshToken(),
            expectedError: AuthError.self
        )
    }

    func testRefreshToken_InvalidRefreshToken() async {
        // Given
        mockKeychainManager.savedRefreshToken = "invalid_token"
        mockRepository.mockError = AuthError.invalidToken

        // When/Then
        await XCTAssertAsyncThrows(
            try await sut.refreshToken(),
            expectedError: AuthError.self
        )
    }

    // MARK: - Session Management Tests

    func testLoadSession_WithValidToken() async {
        // Given
        mockKeychainManager.savedAccessToken = "valid_token"
        mockRepository.mockUser = User.mock(username: "sessionuser")

        // When
        sut.loadSession()

        // Wait for async getCurrentUser call
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        // Note: currentUser will be set asynchronously
    }

    func testLoadSession_NoToken() {
        // Given
        mockKeychainManager.savedAccessToken = nil

        // When
        sut.loadSession()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
    }

    func testClearSession() {
        // Given
        sut.isAuthenticated = true
        sut.currentUser = User.mock()
        mockKeychainManager.savedAccessToken = "token"
        mockKeychainManager.savedRefreshToken = "refresh"

        // When
        sut.clearSession()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertTrue(mockKeychainManager.didClearTokens)
    }

    // MARK: - Update Profile Tests

    func testUpdateProfile_Success() async throws {
        // Given
        sut.currentUser = User.mock(id: "user_1", displayName: "Old Name")
        let newDisplayName = "New Name"
        let newBio = "New bio"
        mockRepository.mockUser = User.mock(
            id: "user_1",
            displayName: newDisplayName,
            bio: newBio
        )

        // When
        try await sut.updateProfile(
            displayName: newDisplayName,
            bio: newBio,
            avatarData: nil
        )

        // Then
        XCTAssertEqual(sut.currentUser?.displayName, newDisplayName)
        XCTAssertEqual(sut.currentUser?.bio, newBio)
        XCTAssertEqual(mockRepository.updateProfileCallCount, 1)
        XCTAssertEqual(mockRepository.lastUpdatedDisplayName, newDisplayName)
    }

    func testUpdateProfile_NotAuthenticated() async {
        // Given
        sut.currentUser = nil

        // When/Then
        await XCTAssertAsyncThrows(
            try await sut.updateProfile(displayName: "New", bio: nil, avatarData: nil),
            expectedError: AuthError.self
        )
    }

    func testUpdateProfile_WithAvatarData() async throws {
        // Given
        sut.currentUser = User.mock(id: "user_1")
        let avatarData = TestUtilities.createTestImage().jpegData(compressionQuality: 0.8)!
        mockRepository.mockUser = User.mock(id: "user_1")

        // When
        try await sut.updateProfile(
            displayName: nil,
            bio: nil,
            avatarData: avatarData
        )

        // Then
        XCTAssertEqual(mockRepository.updateProfileCallCount, 1)
    }

    // MARK: - Delete Account Tests

    func testDeleteAccount_Success() async throws {
        // Given
        sut.isAuthenticated = true
        sut.currentUser = User.mock(id: "user_to_delete")

        // When
        try await sut.deleteAccount()

        // Then
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.currentUser)
        XCTAssertEqual(mockRepository.deleteAccountCallCount, 1)
        XCTAssertTrue(mockKeychainManager.didClearTokens)
    }

    func testDeleteAccount_NotAuthenticated() async {
        // Given
        sut.currentUser = nil

        // When/Then
        await XCTAssertAsyncThrows(
            try await sut.deleteAccount(),
            expectedError: AuthError.self
        )
    }

    // MARK: - Edge Cases

    func testMultipleSimultaneousSignIns_ShouldHandleGracefully() async {
        // Given
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "token",
            refreshToken: "refresh",
            user: User.mock()
        )

        // When - trigger multiple sign ins
        async let signIn1 = try? await sut.signIn(email: "test1@example.com", password: "pass")
        async let signIn2 = try? await sut.signIn(email: "test2@example.com", password: "pass")
        async let signIn3 = try? await sut.signIn(email: "test3@example.com", password: "pass")

        _ = await signIn1
        _ = await signIn2
        _ = await signIn3

        // Then - should be in a consistent state
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertNotNil(sut.currentUser)
    }
}

// MARK: - Mock Keychain Manager

class MockKeychainManager {
    var savedAccessToken: String?
    var savedRefreshToken: String?
    var didClearTokens = false

    func getAccessToken() -> String? {
        savedAccessToken
    }

    func getRefreshToken() -> String? {
        savedRefreshToken
    }

    func saveAccessToken(_ token: String) {
        savedAccessToken = token
    }

    func saveRefreshToken(_ token: String) {
        savedRefreshToken = token
    }

    func clearAllTokens() {
        savedAccessToken = nil
        savedRefreshToken = nil
        didClearTokens = true
    }
}
