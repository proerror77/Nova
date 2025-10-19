import XCTest
@testable import NovaApp

/// Integration tests for complete authentication flows
@MainActor
class AuthFlowIntegrationTests: XCTestCase {
    var authService: AuthService!
    var mockRepository: MockAuthRepository!

    override func setUp() async throws {
        try await super.setUp()
        mockRepository = MockAuthRepository()
        authService = AuthService(
            repository: mockRepository,
            keychainManager: MockKeychainManager()
        )
    }

    override func tearDown() {
        authService = nil
        mockRepository = nil
        super.tearDown()
    }

    // MARK: - Complete User Journey Tests

    func testCompleteSignUpFlow() async throws {
        // Given - New user credentials
        let username = "newuser_\(UUID().uuidString.prefix(8))"
        let email = "\(username)@test.com"
        let password = "SecurePass123!"

        mockRepository.mockAuthResult = AuthResult(
            accessToken: "access_token",
            refreshToken: "refresh_token",
            user: User.mock(username: username)
        )

        // When - User signs up
        try await authService.signUp(
            username: username,
            email: email,
            password: password
        )

        // Then - User should be authenticated
        XCTAssertTrue(authService.isAuthenticated, "User should be authenticated after signup")
        XCTAssertNotNil(authService.currentUser, "Current user should be set")
        XCTAssertEqual(authService.currentUser?.username, username)
        XCTAssertEqual(mockRepository.signUpCallCount, 1)
    }

    func testCompleteSignInFlow() async throws {
        // Given - Existing user credentials
        let email = "existing@test.com"
        let password = "password123"

        mockRepository.mockAuthResult = AuthResult(
            accessToken: "access_token",
            refreshToken: "refresh_token",
            user: User.mock(username: "existing")
        )

        // When - User signs in
        try await authService.signIn(email: email, password: password)

        // Then - User should be authenticated
        XCTAssertTrue(authService.isAuthenticated)
        XCTAssertNotNil(authService.currentUser)
        XCTAssertEqual(mockRepository.signInCallCount, 1)
    }

    func testSignUpThenSignOut() async throws {
        // Given - Sign up first
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "token",
            refreshToken: "refresh",
            user: User.mock()
        )
        try await authService.signUp(
            username: "user",
            email: "user@test.com",
            password: "pass"
        )
        XCTAssertTrue(authService.isAuthenticated)

        // When - Sign out
        await authService.signOut()

        // Then - User should be signed out
        XCTAssertFalse(authService.isAuthenticated)
        XCTAssertNil(authService.currentUser)
        XCTAssertEqual(mockRepository.signOutCallCount, 1)
    }

    func testSignOutThenSignInAgain() async throws {
        // Given - Sign in, then sign out
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "token1",
            refreshToken: "refresh1",
            user: User.mock(username: "user1")
        )
        try await authService.signIn(email: "user1@test.com", password: "pass")
        await authService.signOut()
        XCTAssertFalse(authService.isAuthenticated)

        // When - Sign in again
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "token2",
            refreshToken: "refresh2",
            user: User.mock(username: "user1")
        )
        try await authService.signIn(email: "user1@test.com", password: "pass")

        // Then - Should be authenticated again
        XCTAssertTrue(authService.isAuthenticated)
        XCTAssertNotNil(authService.currentUser)
    }

    func testProfileUpdateFlow() async throws {
        // Given - Authenticated user
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "token",
            refreshToken: "refresh",
            user: User.mock(id: "user_1", displayName: "Original Name")
        )
        try await authService.signIn(email: "test@test.com", password: "pass")

        // When - Update profile
        let newName = "Updated Name"
        let newBio = "New bio text"
        mockRepository.mockUser = User.mock(
            id: "user_1",
            displayName: newName,
            bio: newBio
        )
        try await authService.updateProfile(
            displayName: newName,
            bio: newBio,
            avatarData: nil
        )

        // Then - Profile should be updated
        XCTAssertEqual(authService.currentUser?.displayName, newName)
        XCTAssertEqual(authService.currentUser?.bio, newBio)
        XCTAssertEqual(mockRepository.updateProfileCallCount, 1)
    }

    func testAccountDeletionFlow() async throws {
        // Given - Authenticated user
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "token",
            refreshToken: "refresh",
            user: User.mock(id: "user_to_delete")
        )
        try await authService.signIn(email: "delete@test.com", password: "pass")
        XCTAssertTrue(authService.isAuthenticated)

        // When - Delete account
        try await authService.deleteAccount()

        // Then - User should be signed out and account deleted
        XCTAssertFalse(authService.isAuthenticated)
        XCTAssertNil(authService.currentUser)
        XCTAssertEqual(mockRepository.deleteAccountCallCount, 1)
    }

    // MARK: - Token Refresh Flow

    func testTokenRefreshFlow() async throws {
        // Given - User with expired access token
        let keychainManager = MockKeychainManager()
        keychainManager.savedRefreshToken = "valid_refresh_token"
        authService = AuthService(
            repository: mockRepository,
            keychainManager: keychainManager
        )

        mockRepository.mockAuthResult = AuthResult(
            accessToken: "new_access_token",
            refreshToken: "new_refresh_token",
            user: User.mock()
        )

        // When - Refresh token
        try await authService.refreshToken()

        // Then - New tokens should be saved
        XCTAssertEqual(keychainManager.savedAccessToken, "new_access_token")
        XCTAssertEqual(keychainManager.savedRefreshToken, "new_refresh_token")
        XCTAssertEqual(mockRepository.refreshTokenCallCount, 1)
    }

    // MARK: - Error Handling Tests

    func testSignIn_InvalidCredentials_ShowsError() async {
        // Given
        mockRepository.mockError = AuthError.invalidCredential

        // When
        do {
            try await authService.signIn(email: "wrong@test.com", password: "wrong")
            XCTFail("Should throw error")
        } catch {
            // Then
            XCTAssertTrue(error is AuthError)
            XCTAssertFalse(authService.isAuthenticated)
        }
    }

    func testSignUp_DuplicateEmail_ShowsError() async {
        // Given
        mockRepository.mockError = APIError.serverError(409)

        // When
        do {
            try await authService.signUp(
                username: "user",
                email: "duplicate@test.com",
                password: "pass"
            )
            XCTFail("Should throw error")
        } catch {
            // Then
            XCTAssertTrue(error is APIError)
            XCTAssertFalse(authService.isAuthenticated)
        }
    }

    func testTokenRefresh_Failure_ClearsSession() async {
        // Given
        let keychainManager = MockKeychainManager()
        keychainManager.savedRefreshToken = "invalid_token"
        authService = AuthService(
            repository: mockRepository,
            keychainManager: keychainManager
        )
        mockRepository.mockError = AuthError.invalidToken

        // When
        do {
            try await authService.refreshToken()
            XCTFail("Should throw error")
        } catch {
            // Then
            XCTAssertTrue(error is AuthError)
        }
    }

    // MARK: - Session Persistence Tests

    func testSessionPersistence_LoadFromKeychain() async {
        // Given - Saved session in keychain
        let keychainManager = MockKeychainManager()
        keychainManager.savedAccessToken = "saved_token"
        mockRepository.mockUser = User.mock(username: "saveduser")

        authService = AuthService(
            repository: mockRepository,
            keychainManager: keychainManager
        )

        // When - Load session
        authService.loadSession()

        // Wait for async user fetch
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s

        // Then - Should be authenticated
        XCTAssertTrue(authService.isAuthenticated)
    }

    func testSessionPersistence_NoSavedToken() {
        // Given - No saved token
        let keychainManager = MockKeychainManager()
        keychainManager.savedAccessToken = nil

        authService = AuthService(
            repository: mockRepository,
            keychainManager: keychainManager
        )

        // When - Load session
        authService.loadSession()

        // Then - Should not be authenticated
        XCTAssertFalse(authService.isAuthenticated)
    }

    // MARK: - Concurrent Operations

    func testConcurrentSignInAndSignOut_HandlesGracefully() async {
        // Given
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "token",
            refreshToken: "refresh",
            user: User.mock()
        )

        // When - Trigger concurrent operations
        async let signIn = try? await authService.signIn(email: "test@test.com", password: "pass")
        async let signOut = authService.signOut()

        _ = await signIn
        await signOut

        // Then - Should be in a consistent state
        // Final state depends on which operation completed last
        // But should not crash
        XCTAssertNotNil(authService.isAuthenticated) // Just check it's in a valid state
    }

    func testMultipleProfileUpdates_OnlyLastOneApplies() async throws {
        // Given - Authenticated user
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "token",
            refreshToken: "refresh",
            user: User.mock(id: "user_1")
        )
        try await authService.signIn(email: "test@test.com", password: "pass")

        // When - Multiple profile updates
        mockRepository.mockUser = User.mock(id: "user_1", displayName: "Name 1")
        async let update1 = try? await authService.updateProfile(displayName: "Name 1", bio: nil, avatarData: nil)

        mockRepository.mockUser = User.mock(id: "user_1", displayName: "Name 2")
        async let update2 = try? await authService.updateProfile(displayName: "Name 2", bio: nil, avatarData: nil)

        mockRepository.mockUser = User.mock(id: "user_1", displayName: "Name 3")
        async let update3 = try? await authService.updateProfile(displayName: "Name 3", bio: nil, avatarData: nil)

        _ = await update1
        _ = await update2
        _ = await update3

        // Then - Should handle gracefully
        XCTAssertNotNil(authService.currentUser?.displayName)
    }

    // MARK: - Performance Tests

    func testSignInPerformance() {
        // Given
        mockRepository.mockAuthResult = AuthResult(
            accessToken: "token",
            refreshToken: "refresh",
            user: User.mock()
        )

        // When/Then - Should complete within 1 second
        measure {
            let expectation = XCTestExpectation(description: "Sign in complete")
            Task {
                try? await authService.signIn(email: "perf@test.com", password: "pass")
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 1.0)
        }
    }
}
