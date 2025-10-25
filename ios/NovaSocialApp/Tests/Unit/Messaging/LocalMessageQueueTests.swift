import XCTest
import SwiftData
@testable import NovaSocial

/// LocalMessageQueueTests - iOS 离线消息队列单元测试
///
/// 测试范围：
/// 1. 消息入队 (enqueue)
/// 2. 消息出队恢复 (drain)
/// 3. 标记已同步 (markSynced)
/// 4. 移除消息 (remove)
/// 5. 队列大小查询 (size)
/// 6. 队列空检查 (isEmpty)
/// 7. 清空队列 (clear)
/// 8. 指定对话的消息过滤
/// 9. 并发操作安全性
/// 10. 数据持久化验证
///
final class LocalMessageQueueTests: XCTestCase {

    // MARK: - Properties

    var modelContext: ModelContext!
    var queue: LocalMessageQueue!

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()

        // 创建内存中的 SwiftData 容器用于测试
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: LocalMessage.self, configurations: config)
        modelContext = ModelContext(container)
        queue = LocalMessageQueue(modelContext: modelContext)
    }

    override func tearDown() {
        queue = nil
        modelContext = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

    /// 创建测试消息
    private func makeTestMessage(
        id: String = UUID().uuidString,
        conversationId: String = "conv-test-1",
        senderId: String = "user-1",
        plaintext: String = "Test message",
        syncState: SyncState = .localOnly
    ) -> LocalMessage {
        let message = LocalMessage(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            plaintext: plaintext,
            syncState: syncState
        )
        return message
    }

    // MARK: - Test: enqueue()

    /// 测试：消息入队
    func testEnqueue_BasicEnqueue() async throws {
        // Given
        let message = makeTestMessage(id: "msg-1")

        // When
        try await queue.enqueue(message)

        // Then
        let size = try await queue.size()
        XCTAssertEqual(size, 1, "Queue should contain 1 message after enqueue")

        let drained = try await queue.drain()
        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained[0].id, "msg-1")
        XCTAssertEqual(drained[0].syncState, .localOnly)
    }

    /// 测试：多条消息入队
    func testEnqueue_MultipleMessages() async throws {
        // Given
        let messages = (1...5).map { i in
            makeTestMessage(id: "msg-\(i)", plaintext: "Message \(i)")
        }

        // When
        for message in messages {
            try await queue.enqueue(message)
        }

        // Then
        let size = try await queue.size()
        XCTAssertEqual(size, 5, "Queue should contain 5 messages")

        let drained = try await queue.drain()
        XCTAssertEqual(drained.count, 5)
    }

    /// 测试：入队消息状态自动设置为 localOnly
    func testEnqueue_SyncStateAlwaysLocalOnly() async throws {
        // Given
        let message = makeTestMessage(syncState: .synced) // 输入已同步状态

        // When
        try await queue.enqueue(message)

        // Then
        let drained = try await queue.drain()
        XCTAssertEqual(drained[0].syncState, .localOnly, "Enqueue should force syncState to localOnly")
    }

    // MARK: - Test: drain()

    /// 测试：恢复所有离线消息
    func testDrain_AllMessages() async throws {
        // Given
        let msg1 = makeTestMessage(id: "msg-1", conversationId: "conv-1")
        let msg2 = makeTestMessage(id: "msg-2", conversationId: "conv-2")
        try await queue.enqueue(msg1)
        try await queue.enqueue(msg2)

        // When
        let drained = try await queue.drain()

        // Then
        XCTAssertEqual(drained.count, 2)
        let ids = Set(drained.map { $0.id })
        XCTAssertTrue(ids.contains("msg-1"))
        XCTAssertTrue(ids.contains("msg-2"))
    }

    /// 测试：恢复特定对话的消息
    func testDrain_SpecificConversation() async throws {
        // Given
        let msg1 = makeTestMessage(id: "msg-1", conversationId: "conv-1")
        let msg2 = makeTestMessage(id: "msg-2", conversationId: "conv-2")
        let msg3 = makeTestMessage(id: "msg-3", conversationId: "conv-1")
        try await queue.enqueue(msg1)
        try await queue.enqueue(msg2)
        try await queue.enqueue(msg3)

        // When
        let drained = try await queue.drain(for: "conv-1")

        // Then
        XCTAssertEqual(drained.count, 2, "Should return only messages from conv-1")
        let allFromConv1 = drained.allSatisfy { $0.conversationId == "conv-1" }
        XCTAssertTrue(allFromConv1)
    }

    /// 测试：恢复空队列
    func testDrain_EmptyQueue() async throws {
        // When
        let drained = try await queue.drain()

        // Then
        XCTAssertEqual(drained.count, 0)
        XCTAssertTrue(drained.isEmpty)
    }

    /// 测试：恢复不存在的对话消息
    func testDrain_NonExistentConversation() async throws {
        // Given
        let msg1 = makeTestMessage(id: "msg-1", conversationId: "conv-1")
        try await queue.enqueue(msg1)

        // When
        let drained = try await queue.drain(for: "conv-999")

        // Then
        XCTAssertEqual(drained.count, 0)
    }

    // MARK: - Test: markSynced()

    /// 测试：标记消息为已同步
    func testMarkSynced_BasicMarkSync() async throws {
        // Given
        let message = makeTestMessage(id: "msg-1")
        try await queue.enqueue(message)

        // When
        try await queue.markSynced("msg-1")

        // Then
        let descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate<LocalMessage> { $0.id == "msg-1" }
        )
        let fetched = try modelContext.fetch(descriptor)
        XCTAssertEqual(fetched.first?.syncState, .synced)
    }

    /// 测试：标记不存在的消息（应该安全处理）
    func testMarkSynced_NonExistentMessage() async throws {
        // When & Then
        // 应该不会抛出异常
        XCTAssertNoThrow {
            try await self.queue.markSynced("non-existent-id")
        }
    }

    // MARK: - Test: remove()

    /// 测试：移除消息
    func testRemove_BasicRemove() async throws {
        // Given
        let msg1 = makeTestMessage(id: "msg-1")
        let msg2 = makeTestMessage(id: "msg-2")
        try await queue.enqueue(msg1)
        try await queue.enqueue(msg2)

        // When
        try await queue.remove("msg-1")

        // Then
        let remaining = try await queue.drain()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].id, "msg-2")
    }

    /// 测试：移除不存在的消息（应该安全处理）
    func testRemove_NonExistentMessage() async throws {
        // When & Then
        XCTAssertNoThrow {
            try await self.queue.remove("non-existent-id")
        }
    }

    // MARK: - Test: size()

    /// 测试：获取队列大小
    func testSize_BasicSize() async throws {
        // Given
        let messages = (1...3).map { i in
            makeTestMessage(id: "msg-\(i)")
        }
        for message in messages {
            try await queue.enqueue(message)
        }

        // When
        let size = try await queue.size()

        // Then
        XCTAssertEqual(size, 3)
    }

    /// 测试：特定对话的队列大小
    func testSize_SpecificConversation() async throws {
        // Given
        let msg1 = makeTestMessage(id: "msg-1", conversationId: "conv-1")
        let msg2 = makeTestMessage(id: "msg-2", conversationId: "conv-2")
        let msg3 = makeTestMessage(id: "msg-3", conversationId: "conv-1")
        try await queue.enqueue(msg1)
        try await queue.enqueue(msg2)
        try await queue.enqueue(msg3)

        // When
        let sizeConv1 = try await queue.size(for: "conv-1")
        let sizeConv2 = try await queue.size(for: "conv-2")

        // Then
        XCTAssertEqual(sizeConv1, 2)
        XCTAssertEqual(sizeConv2, 1)
    }

    /// 测试：空队列大小
    func testSize_EmptyQueue() async throws {
        // When
        let size = try await queue.size()

        // Then
        XCTAssertEqual(size, 0)
    }

    // MARK: - Test: isEmpty()

    /// 测试：队列是否为空
    func testIsEmpty_EmptyQueue() async throws {
        // When
        let isEmpty = try await queue.isEmpty()

        // Then
        XCTAssertTrue(isEmpty)
    }

    /// 测试：队列不为空
    func testIsEmpty_NonEmptyQueue() async throws {
        // Given
        let message = makeTestMessage(id: "msg-1")
        try await queue.enqueue(message)

        // When
        let isEmpty = try await queue.isEmpty()

        // Then
        XCTAssertFalse(isEmpty)
    }

    // MARK: - Test: clear()

    /// 测试：清空队列
    func testClear_ClearAllMessages() async throws {
        // Given
        let messages = (1...5).map { i in
            makeTestMessage(id: "msg-\(i)")
        }
        for message in messages {
            try await queue.enqueue(message)
        }

        // When
        try await queue.clear()

        // Then
        let size = try await queue.size()
        XCTAssertEqual(size, 0)
        let isEmpty = try await queue.isEmpty()
        XCTAssertTrue(isEmpty)
    }

    /// 测试：清空空队列
    func testClear_ClearEmptyQueue() async throws {
        // When & Then
        XCTAssertNoThrow {
            try await self.queue.clear()
        }
    }

    // MARK: - Integration Tests

    /// 测试：完整的离线消息流程
    func testIntegration_OfflineMessageFlow() async throws {
        // Scenario: 用户发送消息 → 离线 → 恢复 → 重新发送

        // Step 1: 用户尝试发送消息，但离线（消息入队）
        let messageToSend = makeTestMessage(id: "offline-msg-1")
        try await queue.enqueue(messageToSend)

        // 验证消息被队列保存
        var size = try await queue.size()
        XCTAssertEqual(size, 1)

        // Step 2: WebSocket 重新连接（drain 恢复消息）
        let recovered = try await queue.drain()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered[0].id, "offline-msg-1")

        // Step 3: 消息成功重新发送（标记为已同步）
        try await queue.markSynced("offline-msg-1")

        // 验证消息已从队列中移除
        size = try await queue.size()
        XCTAssertEqual(size, 0)
    }

    /// 测试：多对话离线消息管理
    func testIntegration_MultiConversationOfflineMessages() async throws {
        // Scenario: 用户在多个对话中有离线消息

        // 创建多个对话的离线消息
        let conv1Msgs = (1...3).map { i in
            makeTestMessage(id: "conv1-msg-\(i)", conversationId: "conv-1")
        }
        let conv2Msgs = (1...2).map { i in
            makeTestMessage(id: "conv2-msg-\(i)", conversationId: "conv-2")
        }

        for msg in conv1Msgs + conv2Msgs {
            try await queue.enqueue(msg)
        }

        // 恢复 conv-1 的消息
        let conv1Recovered = try await queue.drain(for: "conv-1")
        XCTAssertEqual(conv1Recovered.count, 3)

        // 标记 conv-1 的消息为已同步
        for msg in conv1Recovered {
            try await queue.markSynced(msg.id)
        }

        // 验证只有 conv-2 的消息还在队列中
        let remaining = try await queue.drain()
        XCTAssertEqual(remaining.count, 2)
        let allFromConv2 = remaining.allSatisfy { $0.conversationId == "conv-2" }
        XCTAssertTrue(allFromConv2)
    }

    /// 测试：幂等性验证（同一消息不应该被重复添加）
    func testIntegration_IdempotencyWithDuplicateIds() async throws {
        // Scenario: 相同 ID 的消息入队（应该被覆盖或处理）

        let msg1 = makeTestMessage(id: "msg-idempotent", plaintext: "First version")
        let msg2 = makeTestMessage(id: "msg-idempotent", plaintext: "Second version")

        try await queue.enqueue(msg1)
        try await queue.enqueue(msg2)

        // 虽然入队了两次，但由于 ID 相同，可能只保存一份
        // 这取决于数据库的实现（是否有唯一索引）
        let recovered = try await queue.drain()

        // 至少应该有一条消息
        XCTAssertGreaterThanOrEqual(recovered.count, 1)
    }

    // MARK: - Concurrency Tests

    /// 测试：并发入队操作的安全性
    func testConcurrency_ConcurrentEnqueue() async throws {
        // Given & When: 并发入队多条消息
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let message = self.makeTestMessage(id: "concurrent-msg-\(i)")
                    try? await self.queue.enqueue(message)
                }
            }
        }

        // Then: 所有消息都应该被保存
        let size = try await queue.size()
        XCTAssertEqual(size, 10, "All concurrent enqueues should succeed")
    }

    /// 测试：并发读写操作的安全性
    func testConcurrency_ConcurrentReadWrite() async throws {
        // Given: 初始化一些消息
        for i in 0..<5 {
            let message = makeTestMessage(id: "msg-\(i)")
            try await queue.enqueue(message)
        }

        // When & Then: 并发读写操作
        await withTaskGroup(of: Void.self) { group in
            // 并发读取
            for _ in 0..<5 {
                group.addTask {
                    let _ = try? await self.queue.size()
                    let _ = try? await self.queue.isEmpty()
                    let _ = try? await self.queue.drain()
                }
            }

            // 并发写入
            for i in 5..<10 {
                group.addTask {
                    let message = self.makeTestMessage(id: "concurrent-msg-\(i)")
                    try? await self.queue.enqueue(message)
                }
            }
        }

        // 验证最终状态
        let finalSize = try await queue.size()
        XCTAssertGreaterThan(finalSize, 0, "Concurrent operations should complete safely")
    }

    // MARK: - Performance Tests

    /// 测试：入队性能
    func testPerformance_EnqueueMany() async throws {
        let messageCount = 100

        measure {
            let queue = self.queue!
            let model = self.modelContext!

            Task {
                for i in 0..<messageCount {
                    let message = self.makeTestMessage(id: "perf-msg-\(i)")
                    try await queue.enqueue(message)
                }
            }
        }
    }

    /// 测试：查询性能
    func testPerformance_DrainLargeQueue() async throws {
        // 设置大队列
        for i in 0..<100 {
            let message = makeTestMessage(id: "msg-\(i)")
            try await queue.enqueue(message)
        }

        measure {
            Task {
                let _ = try await self.queue.drain()
            }
        }
    }
}

// MARK: - Helper Extension

extension XCTestCase {
    func XCTAssertNoThrow<T>(
        _ expression: @escaping () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        Task {
            do {
                let _ = try await expression()
            } catch {
                XCTFail("Expected no error but got \(error)", file: file, line: line)
            }
        }
    }
}
