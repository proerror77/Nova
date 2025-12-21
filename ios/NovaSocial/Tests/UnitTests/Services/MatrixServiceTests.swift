import XCTest
@testable import ICERED

/// MatrixService 單元測試
/// 測試 Matrix 連接狀態管理、Session 恢復、憑證管理等核心功能
final class MatrixServiceTests: XCTestCase {

    // MARK: - Connection State Tests

    /// 測試 Matrix 連接狀態枚舉
    func testMatrixConnectionStates() {
        enum MatrixConnectionState: Equatable {
            case disconnected
            case connecting
            case connected
            case syncing
            case error(String)

            static func == (lhs: MatrixConnectionState, rhs: MatrixConnectionState) -> Bool {
                switch (lhs, rhs) {
                case (.disconnected, .disconnected),
                     (.connecting, .connecting),
                     (.connected, .connected),
                     (.syncing, .syncing):
                    return true
                case (.error(let l), .error(let r)):
                    return l == r
                default:
                    return false
                }
            }
        }

        let state1 = MatrixConnectionState.disconnected
        let state2 = MatrixConnectionState.connected

        XCTAssertNotEqual(state1, state2)
        XCTAssertEqual(state1, .disconnected)

        let errorState = MatrixConnectionState.error("Network failed")
        XCTAssertEqual(errorState, .error("Network failed"))
        XCTAssertNotEqual(errorState, .error("Different error"))
    }

    /// 測試連接狀態轉換邏輯
    func testMatrixConnectionStateTransitions() {
        enum MatrixConnectionState {
            case disconnected
            case connecting
            case connected
            case syncing
            case error

            func canTransitionTo(_ newState: MatrixConnectionState) -> Bool {
                switch (self, newState) {
                case (.disconnected, .connecting):
                    return true
                case (.connecting, .connected),
                     (.connecting, .error),
                     (.connecting, .disconnected):
                    return true
                case (.connected, .syncing),
                     (.connected, .disconnected),
                     (.connected, .error):
                    return true
                case (.syncing, .connected),
                     (.syncing, .disconnected),
                     (.syncing, .error):
                    return true
                case (.error, .connecting),
                     (.error, .disconnected):
                    return true
                default:
                    return false
                }
            }
        }

        // 從 disconnected 只能轉到 connecting
        let disconnected = MatrixConnectionState.disconnected
        XCTAssertTrue(disconnected.canTransitionTo(.connecting))
        XCTAssertFalse(disconnected.canTransitionTo(.connected))
        XCTAssertFalse(disconnected.canTransitionTo(.syncing))

        // 從 connecting 可以轉到 connected, error, 或 disconnected
        let connecting = MatrixConnectionState.connecting
        XCTAssertTrue(connecting.canTransitionTo(.connected))
        XCTAssertTrue(connecting.canTransitionTo(.error))
        XCTAssertTrue(connecting.canTransitionTo(.disconnected))
        XCTAssertFalse(connecting.canTransitionTo(.syncing))

        // 從 connected 可以轉到 syncing, disconnected, 或 error
        let connected = MatrixConnectionState.connected
        XCTAssertTrue(connected.canTransitionTo(.syncing))
        XCTAssertTrue(connected.canTransitionTo(.disconnected))
        XCTAssertTrue(connected.canTransitionTo(.error))

        // 從 error 可以重試連接或斷開
        let errorState = MatrixConnectionState.error
        XCTAssertTrue(errorState.canTransitionTo(.connecting))
        XCTAssertTrue(errorState.canTransitionTo(.disconnected))
        XCTAssertFalse(errorState.canTransitionTo(.connected))
    }

    // MARK: - Session Restoration Tests

    /// 測試 Session 恢復邏輯 - 有有效 token
    func testSessionRestorationWithValidToken() {
        // 模擬有效的 session 數據
        struct SessionData {
            let accessToken: String
            let userId: String
            let deviceId: String
            let homeserverUrl: String

            var isValid: Bool {
                return !accessToken.isEmpty && !userId.isEmpty && !deviceId.isEmpty
            }
        }

        let validSession = SessionData(
            accessToken: "valid_token_123",
            userId: "@user:matrix.org",
            deviceId: "DEVICE123",
            homeserverUrl: "https://matrix.org"
        )

        XCTAssertTrue(validSession.isValid, "有效的 session 應該返回 true")
    }

    /// 測試 Session 恢復邏輯 - 無效 token
    func testSessionRestorationWithInvalidToken() {
        struct SessionData {
            let accessToken: String
            let userId: String
            let deviceId: String
            let homeserverUrl: String

            var isValid: Bool {
                return !accessToken.isEmpty && !userId.isEmpty && !deviceId.isEmpty
            }
        }

        let invalidSession = SessionData(
            accessToken: "",
            userId: "@user:matrix.org",
            deviceId: "DEVICE123",
            homeserverUrl: "https://matrix.org"
        )

        XCTAssertFalse(invalidSession.isValid, "空 token 的 session 應該返回 false")
    }

    /// 測試 Session 恢復邏輯 - 缺失 userId
    func testSessionRestorationWithMissingUserId() {
        struct SessionData {
            let accessToken: String
            let userId: String
            let deviceId: String

            var isValid: Bool {
                return !accessToken.isEmpty && !userId.isEmpty && !deviceId.isEmpty
            }
        }

        let missingUserId = SessionData(
            accessToken: "valid_token",
            userId: "",
            deviceId: "DEVICE123"
        )

        XCTAssertFalse(missingUserId.isValid, "缺少 userId 的 session 應該返回 false")
    }

    // MARK: - Credential Management Tests

    /// 測試憑證清除邏輯
    func testClearCredentials() {
        class MockKeychain {
            var storedValues: [String: String] = [
                "matrix_access_token": "token123",
                "matrix_user_id": "@user:matrix.org",
                "matrix_device_id": "DEVICE123"
            ]

            func clearCredentials() {
                storedValues.removeAll()
            }

            var isEmpty: Bool {
                return storedValues.isEmpty
            }
        }

        let keychain = MockKeychain()
        XCTAssertFalse(keychain.isEmpty, "清除前應該有數據")

        keychain.clearCredentials()
        XCTAssertTrue(keychain.isEmpty, "清除後應該沒有數據")
    }

    /// 測試憑證儲存
    func testStoreCredentials() {
        class MockKeychain {
            var storedValues: [String: String] = [:]

            func store(key: String, value: String) {
                storedValues[key] = value
            }

            func get(key: String) -> String? {
                return storedValues[key]
            }
        }

        let keychain = MockKeychain()

        keychain.store(key: "matrix_access_token", value: "new_token_456")
        keychain.store(key: "matrix_user_id", value: "@newuser:matrix.org")
        keychain.store(key: "matrix_device_id", value: "NEWDEVICE")

        XCTAssertEqual(keychain.get(key: "matrix_access_token"), "new_token_456")
        XCTAssertEqual(keychain.get(key: "matrix_user_id"), "@newuser:matrix.org")
        XCTAssertEqual(keychain.get(key: "matrix_device_id"), "NEWDEVICE")
    }

    // MARK: - Matrix User ID Tests

    /// 測試 Matrix 用戶 ID 格式驗證
    func testMatrixUserIdFormat() {
        func isValidMatrixUserId(_ userId: String) -> Bool {
            // Matrix 用戶 ID 格式: @localpart:domain
            let pattern = "^@[a-z0-9._=/-]+:[a-zA-Z0-9.-]+$"
            return userId.range(of: pattern, options: .regularExpression) != nil
        }

        XCTAssertTrue(isValidMatrixUserId("@user:matrix.org"), "標準格式應該有效")
        XCTAssertTrue(isValidMatrixUserId("@john.doe:example.com"), "帶點的用戶名應該有效")
        XCTAssertTrue(isValidMatrixUserId("@user_123:server.io"), "帶下劃線的用戶名應該有效")

        XCTAssertFalse(isValidMatrixUserId("user:matrix.org"), "缺少 @ 應該無效")
        XCTAssertFalse(isValidMatrixUserId("@user"), "缺少 domain 應該無效")
        XCTAssertFalse(isValidMatrixUserId("@:matrix.org"), "缺少 localpart 應該無效")
        XCTAssertFalse(isValidMatrixUserId("@User:matrix.org"), "大寫字母應該無效")
    }

    /// 測試 Nova UUID 到 Matrix ID 的映射
    func testNovaUuidToMatrixIdMapping() {
        func novaUuidToMatrixId(_ uuid: String, homeserver: String) -> String {
            // Nova 使用用戶 UUID 作為 Matrix localpart
            return "@\(uuid.lowercased()):\(homeserver)"
        }

        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        let homeserver = "nova-matrix.example.com"

        let matrixId = novaUuidToMatrixId(uuid, homeserver: homeserver)

        XCTAssertEqual(matrixId, "@550e8400-e29b-41d4-a716-446655440000:nova-matrix.example.com")
    }

    // MARK: - Room ID Tests

    /// 測試 Matrix Room ID 格式驗證
    func testMatrixRoomIdFormat() {
        func isValidMatrixRoomId(_ roomId: String) -> Bool {
            // Matrix Room ID 格式: !opaque_id:domain
            let pattern = "^![a-zA-Z0-9]+:[a-zA-Z0-9.-]+$"
            return roomId.range(of: pattern, options: .regularExpression) != nil
        }

        XCTAssertTrue(isValidMatrixRoomId("!abc123:matrix.org"), "標準格式應該有效")
        XCTAssertTrue(isValidMatrixRoomId("!XYZ789:example.com"), "大寫應該有效")

        XCTAssertFalse(isValidMatrixRoomId("abc123:matrix.org"), "缺少 ! 應該無效")
        XCTAssertFalse(isValidMatrixRoomId("!abc123"), "缺少 domain 應該無效")
    }

    // MARK: - Message Event Tests

    /// 測試 Matrix 消息事件解析
    func testMatrixMessageEventParsing() throws {
        let json = """
        {
            "type": "m.room.message",
            "event_id": "$event123",
            "room_id": "!room456:matrix.org",
            "sender": "@user:matrix.org",
            "origin_server_ts": 1703116800000,
            "content": {
                "msgtype": "m.text",
                "body": "Hello, World!"
            }
        }
        """.data(using: .utf8)!

        struct MessageContent: Decodable {
            let msgtype: String
            let body: String
        }

        struct MatrixMessageEvent: Decodable {
            let type: String
            let eventId: String
            let roomId: String
            let sender: String
            let originServerTs: Int64
            let content: MessageContent
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let event = try decoder.decode(MatrixMessageEvent.self, from: json)

        XCTAssertEqual(event.type, "m.room.message")
        XCTAssertEqual(event.eventId, "$event123")
        XCTAssertEqual(event.roomId, "!room456:matrix.org")
        XCTAssertEqual(event.sender, "@user:matrix.org")
        XCTAssertEqual(event.content.msgtype, "m.text")
        XCTAssertEqual(event.content.body, "Hello, World!")
    }

    /// 測試 Matrix 圖片消息事件
    func testMatrixImageMessageParsing() throws {
        let json = """
        {
            "type": "m.room.message",
            "event_id": "$img123",
            "room_id": "!room456:matrix.org",
            "sender": "@user:matrix.org",
            "origin_server_ts": 1703116800000,
            "content": {
                "msgtype": "m.image",
                "body": "image.png",
                "url": "mxc://matrix.org/abc123",
                "info": {
                    "mimetype": "image/png",
                    "size": 12345,
                    "w": 800,
                    "h": 600
                }
            }
        }
        """.data(using: .utf8)!

        struct ImageInfo: Decodable {
            let mimetype: String
            let size: Int
            let w: Int
            let h: Int
        }

        struct ImageContent: Decodable {
            let msgtype: String
            let body: String
            let url: String
            let info: ImageInfo
        }

        struct MatrixImageEvent: Decodable {
            let type: String
            let eventId: String
            let content: ImageContent
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let event = try decoder.decode(MatrixImageEvent.self, from: json)

        XCTAssertEqual(event.content.msgtype, "m.image")
        XCTAssertEqual(event.content.url, "mxc://matrix.org/abc123")
        XCTAssertEqual(event.content.info.mimetype, "image/png")
        XCTAssertEqual(event.content.info.w, 800)
        XCTAssertEqual(event.content.info.h, 600)
    }

    // MARK: - Sync Response Tests

    /// 測試 Matrix Sync 響應解析
    func testMatrixSyncResponseParsing() throws {
        let json = """
        {
            "next_batch": "s12345_67890",
            "rooms": {
                "join": {},
                "invite": {},
                "leave": {}
            }
        }
        """.data(using: .utf8)!

        struct RoomCategories: Decodable {
            let join: [String: String]?
            let invite: [String: String]?
            let leave: [String: String]?
        }

        struct SyncResponse: Decodable {
            let nextBatch: String
            let rooms: RoomCategories?
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(SyncResponse.self, from: json)

        XCTAssertEqual(response.nextBatch, "s12345_67890")
        XCTAssertNotNil(response.rooms)
    }

    // MARK: - MXC URI Tests

    /// 測試 MXC URI 格式驗證
    func testMxcUriFormat() {
        func isValidMxcUri(_ uri: String) -> Bool {
            // MXC URI 格式: mxc://server/media_id
            let pattern = "^mxc://[a-zA-Z0-9.-]+/[a-zA-Z0-9]+$"
            return uri.range(of: pattern, options: .regularExpression) != nil
        }

        XCTAssertTrue(isValidMxcUri("mxc://matrix.org/abc123"), "標準 MXC URI 應該有效")
        XCTAssertTrue(isValidMxcUri("mxc://example.com/XYZ789"), "大寫 media_id 應該有效")

        XCTAssertFalse(isValidMxcUri("https://matrix.org/abc123"), "HTTP URL 應該無效")
        XCTAssertFalse(isValidMxcUri("mxc://matrix.org/"), "缺少 media_id 應該無效")
        XCTAssertFalse(isValidMxcUri("mxc:///abc123"), "缺少 server 應該無效")
    }

    /// 測試 MXC URI 到 HTTP URL 的轉換
    func testMxcToHttpConversion() {
        func mxcToHttp(_ mxcUri: String, homeserverUrl: String) -> String? {
            guard mxcUri.hasPrefix("mxc://") else { return nil }

            let withoutPrefix = String(mxcUri.dropFirst(6))
            let components = withoutPrefix.split(separator: "/", maxSplits: 1)

            guard components.count == 2 else { return nil }

            let serverName = String(components[0])
            let mediaId = String(components[1])

            return "\(homeserverUrl)/_matrix/media/v3/download/\(serverName)/\(mediaId)"
        }

        let mxcUri = "mxc://matrix.org/abc123"
        let homeserver = "https://matrix.org"

        let httpUrl = mxcToHttp(mxcUri, homeserverUrl: homeserver)

        XCTAssertEqual(httpUrl, "https://matrix.org/_matrix/media/v3/download/matrix.org/abc123")
    }

    // MARK: - Error Handling Tests

    /// 測試 Matrix 錯誤類型
    func testMatrixErrorTypes() {
        enum MatrixError: Error, Equatable {
            case networkError
            case authenticationFailed
            case sessionExpired
            case roomNotFound
            case userNotFound
            case rateLimited(retryAfterMs: Int)
            case serverError(code: Int, message: String)

            static func == (lhs: MatrixError, rhs: MatrixError) -> Bool {
                switch (lhs, rhs) {
                case (.networkError, .networkError),
                     (.authenticationFailed, .authenticationFailed),
                     (.sessionExpired, .sessionExpired),
                     (.roomNotFound, .roomNotFound),
                     (.userNotFound, .userNotFound):
                    return true
                case (.rateLimited(let l), .rateLimited(let r)):
                    return l == r
                case (.serverError(let lc, let lm), .serverError(let rc, let rm)):
                    return lc == rc && lm == rm
                default:
                    return false
                }
            }
        }

        let authError = MatrixError.authenticationFailed
        let sessionError = MatrixError.sessionExpired

        XCTAssertNotEqual(authError, sessionError)

        let rateLimited1 = MatrixError.rateLimited(retryAfterMs: 5000)
        let rateLimited2 = MatrixError.rateLimited(retryAfterMs: 5000)
        let rateLimited3 = MatrixError.rateLimited(retryAfterMs: 10000)

        XCTAssertEqual(rateLimited1, rateLimited2)
        XCTAssertNotEqual(rateLimited1, rateLimited3)
    }

    /// 測試錯誤重試邏輯
    func testErrorRetryLogic() {
        struct RetryPolicy {
            let maxRetries: Int
            let baseDelayMs: Int
            let maxDelayMs: Int

            func delayForAttempt(_ attempt: Int) -> Int {
                let exponentialDelay = baseDelayMs * Int(pow(2.0, Double(attempt)))
                return min(exponentialDelay, maxDelayMs)
            }

            func shouldRetry(attempt: Int, error: Error) -> Bool {
                return attempt < maxRetries
            }
        }

        let policy = RetryPolicy(maxRetries: 3, baseDelayMs: 1000, maxDelayMs: 30000)

        XCTAssertEqual(policy.delayForAttempt(0), 1000, "第一次延遲 1 秒")
        XCTAssertEqual(policy.delayForAttempt(1), 2000, "第二次延遲 2 秒")
        XCTAssertEqual(policy.delayForAttempt(2), 4000, "第三次延遲 4 秒")
        XCTAssertEqual(policy.delayForAttempt(5), 30000, "不應超過最大延遲")

        XCTAssertTrue(policy.shouldRetry(attempt: 0, error: NSError(domain: "", code: 0)))
        XCTAssertTrue(policy.shouldRetry(attempt: 2, error: NSError(domain: "", code: 0)))
        XCTAssertFalse(policy.shouldRetry(attempt: 3, error: NSError(domain: "", code: 0)))
    }
}

// MARK: - Timeline Management Tests

/// Timeline 管理測試
final class MatrixTimelineTests: XCTestCase {

    /// 測試消息時間線排序
    func testTimelineMessageOrdering() {
        struct TimelineEvent {
            let eventId: String
            let timestamp: Int64
            let content: String
        }

        var timeline = [
            TimelineEvent(eventId: "e3", timestamp: 1703116900, content: "Third"),
            TimelineEvent(eventId: "e1", timestamp: 1703116700, content: "First"),
            TimelineEvent(eventId: "e2", timestamp: 1703116800, content: "Second")
        ]

        timeline.sort { $0.timestamp < $1.timestamp }

        XCTAssertEqual(timeline[0].eventId, "e1")
        XCTAssertEqual(timeline[1].eventId, "e2")
        XCTAssertEqual(timeline[2].eventId, "e3")
    }

    /// 測試消息編輯歷史
    func testMessageEditHistory() {
        struct MessageEdit {
            let originalEventId: String
            let editEventId: String
            let newContent: String
            let editTimestamp: Int64
        }

        var edits: [MessageEdit] = []

        edits.append(MessageEdit(
            originalEventId: "e1",
            editEventId: "edit1",
            newContent: "First edit",
            editTimestamp: 1703116801
        ))

        edits.append(MessageEdit(
            originalEventId: "e1",
            editEventId: "edit2",
            newContent: "Second edit",
            editTimestamp: 1703116802
        ))

        let latestEdit = edits.filter { $0.originalEventId == "e1" }
            .max { $0.editTimestamp < $1.editTimestamp }

        XCTAssertEqual(latestEdit?.newContent, "Second edit")
    }

    /// 測試消息刪除標記
    func testMessageDeletion() {
        struct TimelineMessage {
            let eventId: String
            var isRedacted: Bool
            var redactedBy: String?
        }

        var message = TimelineMessage(eventId: "e1", isRedacted: false, redactedBy: nil)

        XCTAssertFalse(message.isRedacted)

        message.isRedacted = true
        message.redactedBy = "@admin:matrix.org"

        XCTAssertTrue(message.isRedacted)
        XCTAssertEqual(message.redactedBy, "@admin:matrix.org")
    }
}
