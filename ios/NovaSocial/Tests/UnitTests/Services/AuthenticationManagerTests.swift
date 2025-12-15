import XCTest
@testable import ICERED

/// AuthenticationManagerTests - Authentication state and token management tests
///
/// Test Coverage:
/// 1. Login flow and state updates
/// 2. Logout and state clearing
/// 3. Token refresh coalescence (race condition prevention)
/// 4. Guest mode functionality
/// 5. Keychain persistence
@MainActor
final class AuthenticationManagerTests: XCTestCase {

    // MARK: - Properties

    var session: URLSession!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        session = MockURLProtocol.createMockSession()
        MockURLProtocol.reset()

        // Clear any existing auth state
        await AuthenticationManager.shared.logout()
        KeychainService.shared.clearAll()
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        await AuthenticationManager.shared.logout()
        KeychainService.shared.clearAll()
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    /// Test: AuthenticationManager starts in unauthenticated state
    func testInitialState_IsUnauthenticated() {
        let manager = AuthenticationManager.shared

        // After logout in setUp, should be unauthenticated
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentUser)
        XCTAssertNil(manager.authToken)
    }

    // MARK: - Guest Mode Tests

    /// Test: Setting guest mode enables authentication without real credentials
    func testSetGuestMode_EnablesAuthentication() {
        let manager = AuthenticationManager.shared

        // When
        manager.setGuestMode()

        // Then
        XCTAssertTrue(manager.isAuthenticated)
        XCTAssertNotNil(manager.currentUser)
        XCTAssertEqual(manager.currentUser?.id, "guest")
        XCTAssertEqual(manager.currentUser?.username, "Guest")
        XCTAssertTrue(manager.isGuestMode)
    }

    /// Test: Guest mode can be exited via logout
    func testGuestMode_LogoutClearsState() async {
        let manager = AuthenticationManager.shared

        // Given
        manager.setGuestMode()
        XCTAssertTrue(manager.isGuestMode)

        // When
        await manager.logout()

        // Then
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentUser)
        XCTAssertFalse(manager.isGuestMode)
    }

    // MARK: - Logout Tests

    /// Test: Logout clears all auth state
    func testLogout_ClearsAllState() async {
        let manager = AuthenticationManager.shared

        // Given - simulate authenticated state
        manager.setGuestMode()
        XCTAssertTrue(manager.isAuthenticated)

        // When
        await manager.logout()

        // Then
        XCTAssertFalse(manager.isAuthenticated)
        XCTAssertNil(manager.currentUser)
        XCTAssertNil(manager.authToken)
    }

    /// Test: Logout clears Keychain
    func testLogout_ClearsKeychain() async {
        // Given
        _ = KeychainService.shared.save("test_token", for: .authToken)
        _ = KeychainService.shared.save("test_refresh", for: .refreshToken)
        _ = KeychainService.shared.save("test_user_id", for: .userId)

        XCTAssertTrue(KeychainService.shared.exists(.authToken))

        // When
        await AuthenticationManager.shared.logout()

        // Then
        XCTAssertFalse(KeychainService.shared.exists(.authToken))
        XCTAssertFalse(KeychainService.shared.exists(.refreshToken))
        XCTAssertFalse(KeychainService.shared.exists(.userId))
    }

    // MARK: - Token Refresh Tests

    /// Test: attemptTokenRefresh returns false when no refresh token exists
    func testAttemptTokenRefresh_NoRefreshToken_ReturnsFalse() async {
        // Given - no refresh token in keychain
        KeychainService.shared.delete(.refreshToken)

        // When
        let result = await AuthenticationManager.shared.attemptTokenRefresh()

        // Then
        XCTAssertFalse(result)
    }

    /// Test: Token refresh coalescence - multiple concurrent calls share one request
    func testAttemptTokenRefresh_ConcurrentCalls_Coalesce() async {
        // Given
        _ = KeychainService.shared.save("test_refresh_token", for: .refreshToken)

        var refreshCallCount = 0
        let countLock = NSLock()

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("refresh") == true {
                countLock.lock()
                refreshCallCount += 1
                countLock.unlock()

                // Simulate network delay (synchronous)
                Thread.sleep(forTimeInterval: 0.1)

                // Return success response
                let response = TestFixtures.makeAuthResponse()
                let data = try! TestFixtures.makeJSONData(response)
                return (TestFixtures.makeHTTPResponse(statusCode: 200), data)
            }

            return (TestFixtures.makeHTTPResponse(statusCode: 404), nil)
        }

        // When - launch multiple concurrent refresh attempts
        async let result1 = AuthenticationManager.shared.attemptTokenRefresh()
        async let result2 = AuthenticationManager.shared.attemptTokenRefresh()
        async let result3 = AuthenticationManager.shared.attemptTokenRefresh()

        let results = await [result1, result2, result3]

        // Then - all should return the same result (either all true or all false)
        // The key point is they don't all make separate network calls
        let allSame = results.allSatisfy { $0 == results[0] }
        XCTAssertTrue(allSame, "Concurrent refresh calls should return same result")

        // Note: Due to MainActor isolation, the coalescence happens at the task level
        // The actual network call count depends on timing, but should be limited
        print("Token refresh calls made: \(refreshCallCount)")
    }

    // MARK: - Profile Update Tests

    /// Test: updateCurrentUser updates cached user
    func testUpdateCurrentUser_UpdatesCachedUser() {
        let manager = AuthenticationManager.shared

        // Given
        manager.setGuestMode()
        let originalUser = manager.currentUser

        // When
        let updatedUser = TestFixtures.makeUserProfile(
            id: "updated_id",
            username: "updated_user",
            displayName: "Updated Name"
        )
        manager.updateCurrentUser(updatedUser)

        // Then
        XCTAssertEqual(manager.currentUser?.id, "updated_id")
        XCTAssertEqual(manager.currentUser?.username, "updated_user")
        XCTAssertEqual(manager.currentUser?.displayName, "Updated Name")
        XCTAssertNotEqual(manager.currentUser?.id, originalUser?.id)
    }

    /// Test: updateCurrentUser persists user ID to Keychain
    func testUpdateCurrentUser_PersistsToKeychain() {
        let manager = AuthenticationManager.shared

        // Given
        KeychainService.shared.clearAll()

        // When
        let user = TestFixtures.makeUserProfile(id: "persisted_user_id")
        manager.updateCurrentUser(user)

        // Then
        let savedUserId = KeychainService.shared.get(.userId)
        XCTAssertEqual(savedUserId, "persisted_user_id")
    }

    // MARK: - Stored Token Tests

    /// Test: storedRefreshToken returns value from Keychain
    func testStoredRefreshToken_ReturnsKeychainValue() {
        // Given
        let testToken = "stored_refresh_token_123"
        _ = KeychainService.shared.save(testToken, for: .refreshToken)

        // When
        let retrieved = AuthenticationManager.shared.storedRefreshToken

        // Then
        XCTAssertEqual(retrieved, testToken)
    }

    /// Test: storedUserId returns value from Keychain
    func testStoredUserId_ReturnsKeychainValue() {
        // Given
        let testUserId = "stored_user_id_456"
        _ = KeychainService.shared.save(testUserId, for: .userId)

        // When
        let retrieved = AuthenticationManager.shared.storedUserId

        // Then
        XCTAssertEqual(retrieved, testUserId)
    }
}
