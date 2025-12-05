# iOS NovaSocial Testing Strategy - Detailed Recommendations

**Document**: Test Implementation Guidance
**Date**: December 5, 2025
**Audience**: iOS Development Team, QA

---

## Overview: Quick Reference

| Category | Current | Target | Priority |
|----------|---------|--------|----------|
| **E2EE Encryption** | 0% | 95% | P0 - BLOCKER |
| **WebSocket Chat** | 0% | 90% | P0 - BLOCKER |
| **Token Refresh** | 50% | 100% | P0 - CRITICAL |
| **FeedViewModel** | 0% | 85% | P1 - HIGH |
| **Overall Coverage** | 22% | 75% | Phase 1-4 |

---

## Part 1: Critical Test Requirements (P0)

### 1.1 E2EEService Encryption/Decryption

**Current State**: 0% coverage, 379 LOC, CRITICAL for chat security

**Why It Matters**:
- End-to-end encryption is the core security guarantee for NovaSocial
- Silent encryption failures would compromise all chat messages
- Decryption bugs could leak plaintext
- Key management failures could expose all conversations

**Test File**: `Tests/UnitTests/Services/Security/E2EEServiceTests.swift`
**Estimated LOC**: 300-350 lines of test code
**Test Methods**: 20-25

#### Test Template

```swift
import XCTest
@testable import ICERED

@MainActor
final class E2EEServiceTests: XCTestCase {

    var e2eeService: E2EEService!
    var mockCryptoCore: MockCryptoCore!
    var mockAPIClient: MockAPIClient!
    var keychain: KeychainService!

    override func setUp() async throws {
        try await super.setUp()

        // Clear all keychain state
        keychain = KeychainService.shared
        keychain.clearAll()

        // Initialize service
        e2eeService = E2EEService()

        // Optional: Setup mocks if testing integration
        mockCryptoCore = MockCryptoCore()
        mockAPIClient = MockAPIClient()
    }

    override func tearDown() async throws {
        keychain.clearAll()
        try await super.tearDown()
    }

    // MARK: - Device Initialization

    /// Test: Device initialization generates keypair
    func testInitializeDevice_GeneratesKeypair() async throws {
        // When
        try await e2eeService.initializeDevice()

        // Then
        XCTAssertNotNil(e2eeService.deviceIdentity)
        XCTAssertNotNil(e2eeService.deviceIdentity?.publicKey)
        XCTAssertNotNil(e2eeService.deviceIdentity?.secretKey)
    }

    /// Test: Device initialization persists to keychain
    func testInitializeDevice_PersistsToKeychain() async throws {
        // When
        try await e2eeService.initializeDevice()

        // Then
        let savedKey = keychain.get(.deviceIdentity)
        XCTAssertNotNil(savedKey)
    }

    /// Test: Device initialization is idempotent
    func testInitializeDevice_Idempotent() async throws {
        // When
        try await e2eeService.initializeDevice()
        let firstKey = e2eeService.deviceIdentity?.publicKey

        try await e2eeService.initializeDevice()
        let secondKey = e2eeService.deviceIdentity?.publicKey

        // Then - same keys
        XCTAssertEqual(firstKey, secondKey)
    }

    // MARK: - Encryption/Decryption Round Trip

    /// Test: Encrypt then decrypt recovers original plaintext
    func testEncryptDecryptRoundTrip_RecoversSameText() async throws {
        // Given
        try await e2eeService.initializeDevice()
        let plaintext = "Hello, encrypted world!"
        let conversationId = UUID()

        // When
        let encrypted = try await e2eeService.encryptMessage(
            for: conversationId,
            plaintext: plaintext
        )
        let decrypted = try await e2eeService.decryptMessage(
            encrypted,
            conversationId: conversationId
        )

        // Then
        XCTAssertEqual(decrypted, plaintext)
    }

    /// Test: Different plaintexts produce different ciphertexts
    func testEncrypt_DifferentPlaintexts_ProduceDifferentCiphertexts() async throws {
        // Given
        try await e2eeService.initializeDevice()
        let text1 = "Message one"
        let text2 = "Message two"
        let conversationId = UUID()

        // When
        let encrypted1 = try await e2eeService.encryptMessage(
            for: conversationId,
            plaintext: text1
        )
        let encrypted2 = try await e2eeService.encryptMessage(
            for: conversationId,
            plaintext: text2
        )

        // Then
        XCTAssertNotEqual(encrypted1.ciphertext, encrypted2.ciphertext)
    }

    /// Test: Each encryption produces different nonce
    func testEncrypt_GeneratesUniqueNonces() async throws {
        // Given
        try await e2eeService.initializeDevice()
        let plaintext = "Same text encrypted twice"
        let conversationId = UUID()

        // When
        let encrypted1 = try await e2eeService.encryptMessage(
            for: conversationId,
            plaintext: plaintext
        )
        let encrypted2 = try await e2eeService.encryptMessage(
            for: conversationId,
            plaintext: plaintext
        )

        // Then - nonces should be different (randomized)
        XCTAssertNotEqual(encrypted1.nonce, encrypted2.nonce)
    }

    // MARK: - Error Cases

    /// Test: Decrypt with invalid base64 throws error
    func testDecryptMessage_InvalidBase64_Throws() async throws {
        // Given
        try await e2eeService.initializeDevice()
        var invalidMessage = TestFixtures.makeEncryptedMessage()
        invalidMessage.ciphertext = "not-valid-base64!!!"

        // When/Then
        do {
            _ = try await e2eeService.decryptMessage(
                invalidMessage,
                conversationId: UUID()
            )
            XCTFail("Should throw decryption error")
        } catch let error as E2EEError {
            switch error {
            case .decryptionFailed:
                break // Expected
            default:
                XCTFail("Expected decryptionFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected E2EEError, got \(error)")
        }
    }

    /// Test: Decrypt without initialization throws error
    func testDecryptMessage_NotInitialized_Throws() async throws {
        // Given - not initialized
        let message = TestFixtures.makeEncryptedMessage()

        // When/Then
        do {
            _ = try await e2eeService.decryptMessage(message, conversationId: UUID())
            XCTFail("Should throw notInitialized error")
        } catch let error as E2EEError {
            switch error {
            case .notInitialized:
                break // Expected
            default:
                XCTFail("Expected notInitialized, got \(error)")
            }
        }
    }

    /// Test: Tampered ciphertext decryption fails
    func testDecryptMessage_TamperedCiphertext_FailsDecryption() async throws {
        // Given
        try await e2eeService.initializeDevice()
        let plaintext = "Secret message"
        let conversationId = UUID()

        var encrypted = try await e2eeService.encryptMessage(
            for: conversationId,
            plaintext: plaintext
        )

        // Tamper with ciphertext
        if let data = Data(base64: encrypted.ciphertext) {
            var bytes = [UInt8](data)
            if bytes.count > 0 {
                bytes[0] ^= 0xFF // Flip bits
                encrypted.ciphertext = Data(bytes).base64EncodedString()
            }
        }

        // When/Then - should fail to decrypt
        do {
            _ = try await e2eeService.decryptMessage(
                encrypted,
                conversationId: conversationId
            )
            XCTFail("Should fail to decrypt tampered message")
        } catch {
            // Expected - authentication failure
        }
    }

    // MARK: - Key Management

    /// Test: Conversation key derivation is deterministic
    func testDeriveConversationKey_Deterministic() async throws {
        // Given
        try await e2eeService.initializeDevice()
        let conversationId = UUID()

        // When
        let key1 = try e2eeService.deriveConversationKey(conversationId: conversationId)
        let key2 = try e2eeService.deriveConversationKey(conversationId: conversationId)

        // Then - same key for same conversation
        XCTAssertEqual(key1, key2)
    }

    /// Test: Different conversations have different keys
    func testDeriveConversationKey_DifferentPerConversation() async throws {
        // Given
        try await e2eeService.initializeDevice()
        let conversationId1 = UUID()
        let conversationId2 = UUID()

        // When
        let key1 = try e2eeService.deriveConversationKey(conversationId: conversationId1)
        let key2 = try e2eeService.deriveConversationKey(conversationId: conversationId2)

        // Then
        XCTAssertNotEqual(key1, key2)
    }

    // MARK: - Base64 Encoding

    /// Test: Ciphertext is valid base64
    func testEncryptMessage_ReturnsValidBase64Ciphertext() async throws {
        // Given
        try await e2eeService.initializeDevice()

        // When
        let encrypted = try await e2eeService.encryptMessage(
            for: UUID(),
            plaintext: "test"
        )

        // Then
        XCTAssertNotNil(Data(base64: encrypted.ciphertext))
    }

    /// Test: Nonce is valid base64
    func testEncryptMessage_ReturnsValidBase64Nonce() async throws {
        // Given
        try await e2eeService.initializeDevice()

        // When
        let encrypted = try await e2eeService.encryptMessage(
            for: UUID(),
            plaintext: "test"
        )

        // Then
        XCTAssertNotNil(Data(base64: encrypted.nonce))
    }

    // MARK: - UTF-8 Encoding

    /// Test: Unicode characters encrypted correctly
    func testEncryptMessage_UnicodeCharacters_RoundTrip() async throws {
        // Given
        try await e2eeService.initializeDevice()
        let plaintext = "Hello 世界 🌍 こんにちは"
        let conversationId = UUID()

        // When
        let encrypted = try await e2eeService.encryptMessage(
            for: conversationId,
            plaintext: plaintext
        )
        let decrypted = try await e2eeService.decryptMessage(
            encrypted,
            conversationId: conversationId
        )

        // Then
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: - Large Messages

    /// Test: Large messages (1MB) encrypted/decrypted
    func testEncryptMessage_LargeMessage_RoundTrip() async throws {
        // Given
        try await e2eeService.initializeDevice()
        let plaintext = String(repeating: "X", count: 1_000_000)
        let conversationId = UUID()

        // When
        let encrypted = try await e2eeService.encryptMessage(
            for: conversationId,
            plaintext: plaintext
        )
        let decrypted = try await e2eeService.decryptMessage(
            encrypted,
            conversationId: conversationId
        )

        // Then
        XCTAssertEqual(decrypted, plaintext)
    }
}
```

#### Additional Test Fixtures Needed

```swift
// In TestFixtures.swift

static func makeEncryptedMessage(
    ciphertext: String = "test_ciphertext_base64==",
    nonce: String = "test_nonce_base64==",
    deviceId: String = "test_device_id"
) -> EncryptedMessage {
    EncryptedMessage(
        ciphertext: ciphertext,
        nonce: nonce,
        deviceId: deviceId
    )
}

static func makeDeviceIdentity(
    deviceId: String = UUID().uuidString,
    publicKey: Data = Data(count: 32),
    secretKey: Data = Data(count: 32)
) -> DeviceIdentity {
    DeviceIdentity(
        deviceId: deviceId,
        publicKey: publicKey,
        secretKey: secretKey,
        createdAt: Date()
    )
}
```

---

### 1.2 ChatService WebSocket Tests

**Current State**: 0% coverage, 539 LOC, CRITICAL for real-time chat

**Test File**: `Tests/UnitTests/Services/Chat/ChatServiceWebSocketTests.swift`
**Estimated LOC**: 350-400 lines of test code
**Test Methods**: 25-30

#### Mock WebSocket Infrastructure Required

```swift
// Tests/UnitTests/Mocks/MockWebSocketTask.swift

/// Mock URLSessionWebSocketTask for testing
final class MockWebSocketTask: URLSessionWebSocketTask {

    private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []
    private(set) var closeCode: URLSessionWebSocketTask.CloseCode = .goingAway
    private(set) var closeReason: Data? = nil

    var messagesToReceive: [URLSessionWebSocketTask.Message] = []
    var shouldFailReceive = false
    var receiveError: Error? = nil

    private var isOpen = true

    override func send(
        _ message: URLSessionWebSocketTask.Message,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard isOpen else {
            completionHandler(URLError(.badServerResponse))
            return
        }

        sentMessages.append(message)
        completionHandler(nil)
    }

    override func receive(
        completionHandler: @escaping (Result<URLSessionWebSocketTask.Message, Error>) -> Void
    ) {
        if shouldFailReceive {
            let error = receiveError ?? URLError(.networkConnectionLost)
            completionHandler(.failure(error))
            return
        }

        guard !messagesToReceive.isEmpty else {
            // Simulate hanging connection
            DispatchQueue.main.asyncAfter(deadline: .now() + 100) {
                let error = URLError(.networkConnectionLost)
                completionHandler(.failure(error))
            }
            return
        }

        let message = messagesToReceive.removeFirst()
        completionHandler(.success(message))
    }

    override func close(
        with closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        isOpen = false
        self.closeCode = closeCode
        self.closeReason = reason
    }
}
```

#### Test Template

```swift
import XCTest
@testable import ICERED

@MainActor
final class ChatServiceWebSocketTests: XCTestCase {

    var chatService: ChatService!
    var mockWebSocket: MockWebSocketTask!

    override func setUp() async throws {
        try await super.setUp()
        chatService = ChatService()
        mockWebSocket = MockWebSocketTask()

        // Clear auth state
        APIClient.shared.setAuthToken("test_token")
    }

    override func tearDown() async throws {
        chatService.disconnectWebSocket()
        APIClient.shared.setAuthToken("")
        try await super.tearDown()
    }

    // MARK: - Connection Lifecycle

    /// Test: Connect WebSocket establishes connection
    func testConnectWebSocket_EstablishesConnection() {
        // When
        chatService.connectWebSocket()

        // Then
        XCTAssertTrue(chatService.isConnected)
    }

    /// Test: Connect without auth token fails
    func testConnectWebSocket_NoAuthToken_Fails() {
        // Given
        APIClient.shared.setAuthToken("")

        // When
        chatService.connectWebSocket()

        // Then
        XCTAssertFalse(chatService.isConnected)
    }

    /// Test: Connect with valid token succeeds
    func testConnectWebSocket_WithAuthToken_Succeeds() {
        // Given
        APIClient.shared.setAuthToken("valid_token")

        // When
        chatService.connectWebSocket()

        // Then
        XCTAssertTrue(chatService.isConnected)
    }

    // MARK: - Message Reception

    /// Test: Receive message calls callback
    func testReceiveMessage_CallsOnMessageReceived() async {
        // Given
        chatService.connectWebSocket()
        var receivedMessage: Message?

        chatService.onMessageReceived = { message in
            receivedMessage = message
        }

        let testMessage = TestFixtures.makeMessage(content: "Hello")
        let jsonData = try! TestFixtures.makeJSONData(testMessage)
        mockWebSocket.messagesToReceive = [.data(jsonData)]

        // When
        await chatService.receiveMessage()

        // Give async callback time to execute
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertNotNil(receivedMessage)
        XCTAssertEqual(receivedMessage?.content, "Hello")
    }

    /// Test: Receive multiple messages
    func testReceiveMessage_MultipleMessages() async {
        // Given
        chatService.connectWebSocket()
        var receivedMessages: [Message] = []

        chatService.onMessageReceived = { message in
            receivedMessages.append(message)
        }

        let msg1 = TestFixtures.makeMessage(content: "First")
        let msg2 = TestFixtures.makeMessage(content: "Second")
        let msg3 = TestFixtures.makeMessage(content: "Third")

        let data1 = try! TestFixtures.makeJSONData(msg1)
        let data2 = try! TestFixtures.makeJSONData(msg2)
        let data3 = try! TestFixtures.makeJSONData(msg3)

        mockWebSocket.messagesToReceive = [
            .data(data1),
            .data(data2),
            .data(data3)
        ]

        // When
        for _ in 1...3 {
            await chatService.receiveMessage()
        }

        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertEqual(receivedMessages.count, 3)
    }

    /// Test: Disconnection
    func testDisconnectWebSocket_StopsConnection() {
        // Given
        chatService.connectWebSocket()
        XCTAssertTrue(chatService.isConnected)

        // When
        chatService.disconnectWebSocket()

        // Then
        XCTAssertFalse(chatService.isConnected)
    }

    // MARK: - Error Handling

    /// Test: Connection lost error handled
    func testReceiveMessage_ConnectionLost_Handles() async {
        // Given
        chatService.connectWebSocket()
        mockWebSocket.shouldFailReceive = true
        mockWebSocket.receiveError = URLError(.networkConnectionLost)

        // When
        await chatService.receiveMessage()

        // Then - connection marked as failed
        // (depends on implementation, may trigger reconnect)
    }

    /// Test: Invalid JSON in message handled gracefully
    func testReceiveMessage_InvalidJSON_Logs() async {
        // Given
        chatService.connectWebSocket()
        mockWebSocket.messagesToReceive = [.data("invalid json".data(using: .utf8)!)]

        // When/Then - should not crash
        await chatService.receiveMessage()
    }

    // MARK: - Concurrency Safety

    /// Test: Concurrent send and receive no data race
    func testConcurrentSendAndReceive_NoDataRace() async throws {
        // Given
        chatService.connectWebSocket()

        // When - concurrent operations
        async let send1 = chatService.sendMessage(
            conversationId: "conv1",
            content: "Message 1"
        )
        async let send2 = chatService.sendMessage(
            conversationId: "conv1",
            content: "Message 2"
        )

        _ = try? await [send1, send2]

        // Then - no crashes or data races
        XCTAssertTrue(chatService.isConnected)
    }
}
```

---

## Part 2: High Priority Tests (P1)

### 2.1 FeedViewModel State Machine Tests

**File**: `Tests/UnitTests/ViewModels/FeedViewModelTests.swift`
**Test Methods**: 15-20
**Effort**: Medium

#### Critical Test Scenarios

```swift
@MainActor
final class FeedViewModelTests: XCTestCase {

    var viewModel: FeedViewModel!
    var mockFeedService: MockFeedService!
    var mockAuthManager: MockAuthenticationManager!

    override func setUp() async throws {
        try await super.setUp()
        mockFeedService = MockFeedService()
        mockAuthManager = MockAuthenticationManager()
        viewModel = FeedViewModel(
            feedService: mockFeedService,
            contentService: MockContentService(),
            socialService: MockSocialService(),
            authManager: mockAuthManager
        )
    }

    // MARK: - Initial Load

    func testLoadFeed_Success_PopulatesPosts() async throws {
        // Given
        let expectedPosts = [
            TestFixtures.makeFeedPost(),
            TestFixtures.makeFeedPost()
        ]
        mockFeedService.feedToReturn = FeedResponse(
            posts: expectedPosts,
            postIds: expectedPosts.map { $0.id },
            cursor: nil,
            hasMore: false
        )

        // When
        await viewModel.loadFeed()

        // Then
        XCTAssertEqual(viewModel.posts.count, 2)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testLoadFeed_IsLoading_SetTrue() async {
        // Given
        var loadingStates: [Bool] = []

        let task = Task {
            while true {
                loadingStates.append(self.viewModel.isLoading)
                try? await Task.sleep(nanoseconds: 10_000_000)
                if !self.viewModel.isLoading && loadingStates.count > 1 {
                    break
                }
            }
        }

        // When
        await viewModel.loadFeed()

        // Then
        task.cancel()
        XCTAssertTrue(loadingStates.contains(true))
    }

    // MARK: - Auth Token Refresh Flow

    func testLoadFeed_401_AttemptsTokenRefresh() async throws {
        // Given
        mockFeedService.errorToThrow = APIError.unauthorized
        mockAuthManager.refreshTokenWillSucceed = true

        // When
        await viewModel.loadFeed()

        // Then
        XCTAssertTrue(mockAuthManager.refreshTokenWasCalled)
    }

    func testLoadFeed_401_RefreshSuccess_Retries() async throws {
        // Given - first call 401, then success
        var callCount = 0
        mockFeedService.requestHandler = {
            callCount += 1
            if callCount == 1 {
                throw APIError.unauthorized
            }
            return FeedResponse(
                posts: [TestFixtures.makeFeedPost()],
                postIds: ["post1"],
                cursor: nil,
                hasMore: false
            )
        }
        mockAuthManager.refreshTokenWillSucceed = true

        // When
        await viewModel.loadFeed()

        // Then
        XCTAssertEqual(viewModel.posts.count, 1) // Should have retried
        XCTAssertNil(viewModel.error)
    }

    func testLoadFeed_401_RefreshFails_FallsBackToGuest() async throws {
        // Given
        mockFeedService.errorToThrow = APIError.unauthorized
        mockAuthManager.refreshTokenWillSucceed = false

        // When
        await viewModel.loadFeed()

        // Then
        XCTAssertTrue(mockAuthManager.logoutWasCalled)
    }

    // MARK: - Guest Fallback Logic

    func testLoadFeed_401_GuestMode_ShowsError() async {
        // Given
        mockAuthManager.isGuestMode = true
        mockFeedService.errorToThrow = APIError.unauthorized

        // When
        await viewModel.loadFeed()

        // Then
        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.posts.isEmpty)
    }

    func testLoadFeed_InvalidGuestFallback_StopsRetrying() async {
        // Given
        let isGuestFallback = true
        mockFeedService.errorToThrow = APIError.unauthorized

        // When
        await viewModel.loadFeed(isGuestFallback: isGuestFallback)

        // Then
        // Should NOT retry or logout again
        XCTAssertNotNil(viewModel.error)
    }
}
```

---

### 2.2 Token Refresh Integration Tests

**File**: `Tests/IntegrationTests/Auth/TokenRefreshIntegrationTests.swift`
**Test Methods**: 12-15
**Effort**: Medium

```swift
/// Test end-to-end token refresh flow
final class TokenRefreshIntegrationTests: XCTestCase {

    var identityService: IdentityService!
    var authManager: AuthenticationManager!
    var apiClient: APIClient!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        identityService = IdentityService()
        authManager = AuthenticationManager.shared
        apiClient = APIClient.shared

        // Setup mock
        session = MockURLProtocol.createMockSession()
        MockURLProtocol.reset()

        await authManager.logout()
    }

    // MARK: - Full Flow Tests

    /// Test: API call with expired token triggers refresh
    func testExpiredToken_TriggersRefresh() async throws {
        // Given
        let oldToken = "old_expired_token"
        let newToken = "new_valid_token"
        let refreshToken = "refresh_token"

        apiClient.setAuthToken(oldToken)
        KeychainService.shared.save(refreshToken, for: .refreshToken)

        var refreshCalled = false
        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("refresh") == true {
                refreshCalled = true
                let response = TestFixtures.makeAuthResponse(token: newToken)
                let data = try TestFixtures.makeJSONData(response)
                return (TestFixtures.makeHTTPResponse(statusCode: 200), data)
            }

            if request.url?.path.contains("some_endpoint") == true {
                // First call returns 401, second returns 200
                if apiClient.getAuthToken() == oldToken {
                    return (TestFixtures.makeHTTPResponse(statusCode: 401), nil)
                } else if apiClient.getAuthToken() == newToken {
                    return (TestFixtures.makeHTTPResponse(statusCode: 200), Data())
                }
            }

            return (TestFixtures.makeHTTPResponse(statusCode: 404), nil)
        }

        // When
        let refreshed = await authManager.attemptTokenRefresh()

        // Then
        XCTAssertTrue(refreshed)
        XCTAssertTrue(refreshCalled)
        XCTAssertEqual(apiClient.getAuthToken(), newToken)
    }

    /// Test: Multiple concurrent 401s coalesce into one refresh
    func testConcurrent401s_Coalesce() async throws {
        // Given
        let refreshToken = "refresh_token"
        KeychainService.shared.save(refreshToken, for: .refreshToken)

        var refreshCallCount = 0
        let callLock = NSLock()

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("refresh") == true {
                callLock.lock()
                refreshCallCount += 1
                callLock.unlock()

                let response = TestFixtures.makeAuthResponse(token: "new_token")
                let data = try TestFixtures.makeJSONData(response)

                // Simulate network delay
                try? await Task.sleep(nanoseconds: 50_000_000)

                return (TestFixtures.makeHTTPResponse(statusCode: 200), data)
            }
            return (TestFixtures.makeHTTPResponse(statusCode: 200), nil)
        }

        // When - concurrent refresh attempts
        async let r1 = authManager.attemptTokenRefresh()
        async let r2 = authManager.attemptTokenRefresh()
        async let r3 = authManager.attemptTokenRefresh()

        let results = await [r1, r2, r3]

        // Then
        print("Refresh call count: \(refreshCallCount)")
        XCTAssertTrue(results.allSatisfy { $0 == results[0] })
        // Should have limited refresh calls due to coalescence
        XCTAssertLessThanOrEqual(refreshCallCount, 2)
    }

    /// Test: Failed refresh triggers logout
    func testRefreshFailure_TriggersLogout() async throws {
        // Given
        let refreshToken = "refresh_token"
        KeychainService.shared.save(refreshToken, for: .refreshToken)

        MockURLProtocol.requestHandler = { request in
            if request.url?.path.contains("refresh") == true {
                return (TestFixtures.makeHTTPResponse(statusCode: 401), nil)
            }
            return (TestFixtures.makeHTTPResponse(statusCode: 200), nil)
        }

        // When
        let refreshed = await authManager.attemptTokenRefresh()

        // Then
        XCTAssertFalse(refreshed)
        XCTAssertFalse(authManager.isAuthenticated)
    }
}
```

---

## Part 3: Mock Services Template

For testing ViewModels and complex features, create mock services:

```swift
// Tests/UnitTests/Mocks/MockServices.swift

final class MockFeedService: FeedService {
    var feedToReturn: FeedResponse?
    var errorToThrow: Error?
    var requestHandler: (() async throws -> FeedResponse)?

    override func getFeed(
        algo: FeedAlgorithm,
        limit: Int,
        cursor: String?
    ) async throws -> FeedResponse {
        if let error = errorToThrow { throw error }
        if let handler = requestHandler { return try await handler() }
        return feedToReturn ?? FeedResponse(posts: [], postIds: [], cursor: nil, hasMore: false)
    }
}

final class MockAuthenticationManager: AuthenticationManager {
    var refreshTokenWillSucceed = true
    var refreshTokenWasCalled = false
    var logoutWasCalled = false
    var isGuestMode = false

    override func attemptTokenRefresh() async -> Bool {
        refreshTokenWasCalled = true
        return refreshTokenWillSucceed
    }

    override func logout() async {
        logoutWasCalled = true
    }
}
```

---

## Part 4: Test Execution & CI Integration

### Running Tests Locally

```bash
# Run all tests
xcodebuild test \
  -project NovaSocial.xcodeproj \
  -scheme NovaSocial \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -enableCodeCoverage YES

# Run specific test class
xcodebuild test \
  -project NovaSocial.xcodeproj \
  -scheme NovaSocial \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:NovaSocialTests/E2EEServiceTests

# Generate coverage report
xcrun xccov view --report --json \
  /path/to/coverage.json
```

### GitHub Actions CI Setup

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run tests
        run: |
          xcodebuild test \
            -project NovaSocial.xcodeproj \
            -scheme NovaSocial \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -enableCodeCoverage YES
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

---

## Conclusion

Implementing these test recommendations will:

1. **Eliminate P0 risks** for E2EE and WebSocket
2. **Reach 75% code coverage** in 6-8 weeks
3. **Prevent regressions** with comprehensive integration tests
4. **Enable confident shipping** of chat features

**Next Steps**:
1. Assign E2EEService tests (Priority 1, Week 1)
2. Assign ChatService WebSocket tests (Priority 1, Week 1-2)
3. Set up CI/CD (Parallel, Week 1)
4. Complete FeedViewModel tests (Priority 2, Week 3)

---
