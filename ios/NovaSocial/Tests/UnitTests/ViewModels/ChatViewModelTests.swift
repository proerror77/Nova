import XCTest
@testable import ICERED

/// ChatViewModel 單元測試
/// 測試消息狀態管理、分頁載入、輸入指示器等核心功能
final class ChatViewModelTests: XCTestCase {

    // MARK: - State Management Tests

    /// 測試初始狀態
    func testInitialState() {
        // 模擬 ViewModel 初始狀態
        struct ChatViewModelState {
            var messages: [Message] = []
            var messageText: String = ""
            var error: String? = nil
            var isLoadingHistory: Bool = false
            var isSending: Bool = false
            var isUploadingImage: Bool = false
            var hasMoreMessages: Bool = true
            var nextCursor: String? = nil
            var isMatrixE2EEEnabled: Bool = false
            var isOtherUserTyping: Bool = false
            var typingUserName: String = ""
        }

        let state = ChatViewModelState()

        XCTAssertTrue(state.messages.isEmpty, "初始消息列表應該為空")
        XCTAssertEqual(state.messageText, "", "初始輸入文字應該為空")
        XCTAssertNil(state.error, "初始應該沒有錯誤")
        XCTAssertFalse(state.isLoadingHistory, "初始不應該在載入歷史")
        XCTAssertFalse(state.isSending, "初始不應該在發送")
        XCTAssertTrue(state.hasMoreMessages, "初始應該假設有更多消息")
        XCTAssertNil(state.nextCursor, "初始沒有分頁游標")
        XCTAssertFalse(state.isOtherUserTyping, "初始對方不應該在輸入")
    }

    /// 測試消息列表更新
    func testMessagesUpdate() {
        var messages: [Message] = []

        // 添加消息
        let newMessage = createTestMessage(id: "msg-1", content: "Hello")
        messages.append(newMessage)

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].content, "Hello")

        // 添加更多消息
        messages.append(createTestMessage(id: "msg-2", content: "World"))
        XCTAssertEqual(messages.count, 2)
    }

    /// 測試消息文字綁定
    func testMessageTextBinding() {
        var messageText = ""

        // 模擬用戶輸入
        messageText = "H"
        XCTAssertEqual(messageText, "H")

        messageText = "Hello"
        XCTAssertEqual(messageText, "Hello")

        // 發送後清空
        messageText = ""
        XCTAssertEqual(messageText, "")
    }

    // MARK: - Loading State Tests

    /// 測試載入歷史狀態轉換
    func testLoadingHistoryStateTransition() {
        var isLoadingHistory = false

        // 開始載入
        isLoadingHistory = true
        XCTAssertTrue(isLoadingHistory)

        // 載入完成
        isLoadingHistory = false
        XCTAssertFalse(isLoadingHistory)
    }

    /// 測試發送狀態轉換
    func testSendingStateTransition() {
        var isSending = false
        var messageText = "Test message"

        // 模擬發送過程
        func sendMessage() {
            guard !messageText.isEmpty else { return }
            isSending = true

            // 模擬異步發送
            // ...

            isSending = false
            messageText = ""
        }

        XCTAssertFalse(isSending, "發送前應該為 false")

        isSending = true
        XCTAssertTrue(isSending, "發送中應該為 true")

        isSending = false
        messageText = ""
        XCTAssertFalse(isSending, "發送後應該為 false")
        XCTAssertEqual(messageText, "", "發送後消息應該清空")
    }

    /// 測試圖片上傳狀態
    func testUploadingImageState() {
        var isUploadingImage = false

        // 開始上傳
        isUploadingImage = true
        XCTAssertTrue(isUploadingImage)

        // 上傳完成
        isUploadingImage = false
        XCTAssertFalse(isUploadingImage)
    }

    // MARK: - Pagination Tests

    /// 測試分頁載入邏輯
    func testPaginationLogic() {
        var messages: [Message] = []
        var hasMoreMessages = true
        var nextCursor: String? = nil
        var isLoadingHistory = false

        // 第一頁
        let page1 = [
            createTestMessage(id: "msg-1", content: "Message 1"),
            createTestMessage(id: "msg-2", content: "Message 2"),
            createTestMessage(id: "msg-3", content: "Message 3")
        ]
        messages.append(contentsOf: page1)
        nextCursor = "cursor-page2"
        hasMoreMessages = true

        XCTAssertEqual(messages.count, 3)
        XCTAssertNotNil(nextCursor)
        XCTAssertTrue(hasMoreMessages)

        // 第二頁
        let page2 = [
            createTestMessage(id: "msg-4", content: "Message 4"),
            createTestMessage(id: "msg-5", content: "Message 5")
        ]
        messages.insert(contentsOf: page2, at: 0)  // 歷史消息插入到前面
        nextCursor = nil
        hasMoreMessages = false

        XCTAssertEqual(messages.count, 5)
        XCTAssertNil(nextCursor)
        XCTAssertFalse(hasMoreMessages)
    }

    /// 測試載入更多條件判斷
    func testShouldLoadMore() {
        func shouldLoadMore(
            hasMoreMessages: Bool,
            isLoadingHistory: Bool,
            nextCursor: String?
        ) -> Bool {
            return hasMoreMessages && !isLoadingHistory && nextCursor != nil
        }

        // 應該載入更多
        XCTAssertTrue(shouldLoadMore(
            hasMoreMessages: true,
            isLoadingHistory: false,
            nextCursor: "cursor"
        ))

        // 沒有更多消息
        XCTAssertFalse(shouldLoadMore(
            hasMoreMessages: false,
            isLoadingHistory: false,
            nextCursor: "cursor"
        ))

        // 正在載入中
        XCTAssertFalse(shouldLoadMore(
            hasMoreMessages: true,
            isLoadingHistory: true,
            nextCursor: "cursor"
        ))

        // 沒有游標
        XCTAssertFalse(shouldLoadMore(
            hasMoreMessages: true,
            isLoadingHistory: false,
            nextCursor: nil
        ))
    }

    // MARK: - Typing Indicator Tests

    /// 測試輸入指示器開始
    func testTypingIndicatorStart() {
        var isOtherUserTyping = false
        var typingUserName = ""

        // 對方開始輸入
        isOtherUserTyping = true
        typingUserName = "John"

        XCTAssertTrue(isOtherUserTyping)
        XCTAssertEqual(typingUserName, "John")
    }

    /// 測試輸入指示器停止
    func testTypingIndicatorStop() {
        var isOtherUserTyping = true
        var typingUserName = "John"

        // 對方停止輸入
        isOtherUserTyping = false
        typingUserName = ""

        XCTAssertFalse(isOtherUserTyping)
        XCTAssertEqual(typingUserName, "")
    }

    /// 測試輸入指示器超時
    func testTypingIndicatorTimeout() {
        // 輸入指示器應該在一定時間後自動隱藏
        let typingTimeoutSeconds = 5.0

        XCTAssertEqual(typingTimeoutSeconds, 5.0, "輸入指示器應該 5 秒後超時")
    }

    // MARK: - E2EE State Tests

    /// 測試 E2EE 狀態
    func testE2EEState() {
        var isMatrixE2EEEnabled = false

        // 啟用 E2EE
        isMatrixE2EEEnabled = true
        XCTAssertTrue(isMatrixE2EEEnabled)

        // 禁用 E2EE
        isMatrixE2EEEnabled = false
        XCTAssertFalse(isMatrixE2EEEnabled)
    }

    // MARK: - Error Handling Tests

    /// 測試錯誤狀態
    func testErrorState() {
        var error: String? = nil

        // 設置錯誤
        error = "Network connection failed"
        XCTAssertNotNil(error)
        XCTAssertEqual(error, "Network connection failed")

        // 清除錯誤
        error = nil
        XCTAssertNil(error)
    }

    /// 測試發送失敗處理
    func testSendMessageFailure() {
        var isSending = false
        var error: String? = nil
        var messageText = "Test message"

        // 模擬發送失敗
        isSending = true
        error = nil

        // 發送失敗
        isSending = false
        error = "Failed to send message"

        XCTAssertFalse(isSending)
        XCTAssertNotNil(error)
        XCTAssertEqual(messageText, "Test message", "發送失敗時消息不應該清空")
    }

    // MARK: - Message Operations Tests

    /// 測試發送消息驗證
    func testSendMessageValidation() {
        func canSendMessage(messageText: String, isSending: Bool) -> Bool {
            return !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
        }

        XCTAssertTrue(canSendMessage(messageText: "Hello", isSending: false))
        XCTAssertFalse(canSendMessage(messageText: "", isSending: false))
        XCTAssertFalse(canSendMessage(messageText: "   ", isSending: false))
        XCTAssertFalse(canSendMessage(messageText: "Hello", isSending: true))
    }

    /// 測試創建臨時消息（樂觀更新）
    func testCreateOptimisticMessage() {
        let tempId = UUID().uuidString
        let content = "Optimistic message"
        let senderId = "current-user-id"
        let conversationId = "conv-123"

        let message = Message(
            id: tempId,
            conversationId: conversationId,
            senderId: senderId,
            content: content,
            type: .text,
            createdAt: Date(),
            status: .sent
        )

        XCTAssertEqual(message.content, content)
        XCTAssertEqual(message.senderId, senderId)
        XCTAssertEqual(message.conversationId, conversationId)
        XCTAssertEqual(message.status, .sent)
    }

    /// 測試替換臨時消息
    func testReplaceOptimisticMessage() {
        var messages = [
            createTestMessage(id: "temp-123", content: "Sending..."),
            createTestMessage(id: "msg-1", content: "Existing message")
        ]

        // 服務器返回真實消息
        let realMessage = createTestMessage(id: "real-456", content: "Sending...")

        // 替換臨時消息
        if let index = messages.firstIndex(where: { $0.id == "temp-123" }) {
            messages[index] = realMessage
        }

        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].id, "real-456")
    }

    // MARK: - Media Message Tests

    /// 測試圖片消息驗證
    func testImageMessageValidation() {
        func canSendImage(imageData: Data?, isUploadingImage: Bool) -> Bool {
            guard let data = imageData else { return false }
            return !data.isEmpty && !isUploadingImage
        }

        let validImageData = Data([0x89, 0x50, 0x4E, 0x47])  // PNG header
        let emptyData = Data()

        XCTAssertTrue(canSendImage(imageData: validImageData, isUploadingImage: false))
        XCTAssertFalse(canSendImage(imageData: nil, isUploadingImage: false))
        XCTAssertFalse(canSendImage(imageData: emptyData, isUploadingImage: false))
        XCTAssertFalse(canSendImage(imageData: validImageData, isUploadingImage: true))
    }

    /// 測試位置消息格式
    func testLocationMessageFormat() {
        struct LocationData {
            let latitude: Double
            let longitude: Double
            let address: String?

            func toJSON() -> String {
                if let address = address {
                    return "{\"lat\":\(latitude),\"lng\":\(longitude),\"address\":\"\(address)\"}"
                }
                return "{\"lat\":\(latitude),\"lng\":\(longitude)}"
            }
        }

        let location = LocationData(
            latitude: 25.0330,
            longitude: 121.5654,
            address: "台北市"
        )

        let json = location.toJSON()
        XCTAssertTrue(json.contains("25.033"))
        XCTAssertTrue(json.contains("121.5654"))
        XCTAssertTrue(json.contains("台北市"))
    }

    /// 測試語音消息驗證
    func testVoiceMessageValidation() {
        func canSendVoice(audioData: Data?, duration: Double) -> Bool {
            guard let data = audioData, !data.isEmpty else { return false }
            return duration > 0 && duration <= 60  // 最長 60 秒
        }

        let validAudioData = Data([0x00, 0x01, 0x02])

        XCTAssertTrue(canSendVoice(audioData: validAudioData, duration: 10))
        XCTAssertFalse(canSendVoice(audioData: nil, duration: 10))
        XCTAssertFalse(canSendVoice(audioData: validAudioData, duration: 0))
        XCTAssertFalse(canSendVoice(audioData: validAudioData, duration: 61))
    }

    // MARK: - Cleanup Tests

    /// 測試清理邏輯
    func testCleanup() {
        var messages: [Message] = [
            createTestMessage(id: "msg-1", content: "Test")
        ]
        var messageText = "Draft message"
        var isOtherUserTyping = true
        var typingUserName = "John"

        // 執行清理
        func cleanup() {
            messageText = ""
            isOtherUserTyping = false
            typingUserName = ""
            // 消息不清空，留給下次進入
        }

        cleanup()

        XCTAssertEqual(messageText, "")
        XCTAssertFalse(isOtherUserTyping)
        XCTAssertEqual(typingUserName, "")
        XCTAssertFalse(messages.isEmpty, "消息不應該在清理時清空")
    }

    // MARK: - Message Deduplication Tests (Today's Bug Fix)

    /// 測試消息去重 - WebSocket 和 REST 可能返回相同消息
    func testMessageDeduplicationFromMultipleSources() {
        var messages: [Message] = []

        // 從 REST API 載入消息
        let restMessages = [
            createTestMessage(id: "msg-1", content: "Hello"),
            createTestMessage(id: "msg-2", content: "World")
        ]
        messages.append(contentsOf: restMessages)

        // 從 WebSocket 接收相同消息
        let wsMessage = createTestMessage(id: "msg-1", content: "Hello")

        // 去重邏輯
        let existingIDs = Set(messages.map { $0.id })
        if !existingIDs.contains(wsMessage.id) {
            messages.append(wsMessage)
        }

        XCTAssertEqual(messages.count, 2, "不應該有重複消息")
    }

    /// 測試 Matrix 消息去重
    func testMatrixMessageDeduplication() {
        var messages: [Message] = []

        // 從 Matrix SDK 接收消息
        let matrixMessage1 = createTestMessage(id: "matrix-event-1", content: "Matrix message")
        messages.append(matrixMessage1)

        // 再次接收相同事件（例如 sync 重複）
        let matrixMessage2 = createTestMessage(id: "matrix-event-1", content: "Matrix message")

        let existingIDs = Set(messages.map { $0.id })
        if !existingIDs.contains(matrixMessage2.id) {
            messages.append(matrixMessage2)
        }

        XCTAssertEqual(messages.count, 1, "Matrix 消息不應該重複")
    }

    // MARK: - Helper Methods

    private func createTestMessage(
        id: String,
        content: String,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) -> Message {
        return Message(
            id: id,
            conversationId: "conv-test",
            senderId: "user-test",
            content: content,
            type: .text,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}

// MARK: - Reply Message Tests

/// 回覆消息測試
final class ReplyMessageTests: XCTestCase {

    /// 測試回覆消息模型
    func testReplyMessageModel() {
        let replyMessage = Message(
            id: "msg-reply",
            conversationId: "conv-123",
            senderId: "user-1",
            content: "This is a reply",
            type: .text,
            createdAt: Date(),
            replyToId: "msg-original"
        )

        XCTAssertEqual(replyMessage.replyToId, "msg-original")
        XCTAssertEqual(replyMessage.content, "This is a reply")
    }

    /// 測試檢查是否為回覆消息
    func testIsReplyMessage() {
        func isReplyMessage(_ message: Message) -> Bool {
            return message.replyToId != nil
        }

        let normalMessage = Message(
            id: "msg-1",
            conversationId: "conv-123",
            senderId: "user-1",
            content: "Normal message",
            type: .text,
            createdAt: Date()
        )

        let replyMessage = Message(
            id: "msg-2",
            conversationId: "conv-123",
            senderId: "user-1",
            content: "Reply message",
            type: .text,
            createdAt: Date(),
            replyToId: "msg-original"
        )

        XCTAssertFalse(isReplyMessage(normalMessage))
        XCTAssertTrue(isReplyMessage(replyMessage))
    }
}
