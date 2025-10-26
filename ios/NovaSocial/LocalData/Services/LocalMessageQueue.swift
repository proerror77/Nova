import Foundation
import SwiftData

// MARK: - LocalMessageQueue

/// iOS 离线消息队列 - 与前端 OfflineQueue 和后端 offline_queue 对应
/// 用于：
/// 1. 缓存离线期间尝试发送但失败的消息
/// 2. 网络恢复时自动重新发送这些消息
/// 3. 支持幂等重发，防止消息重复
@MainActor
final class LocalMessageQueue {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Queue Operations

    /// 将消息加入离线队列
    /// 在消息发送失败但可重试时调用
    func enqueue(_ message: LocalMessage) async throws {
        // 确保消息状态为 localOnly (未同步)
        var mutableMessage = message
        mutableMessage.syncState = .localOnly
        mutableMessage.localModifiedAt = Date()
        mutableMessage.retryCount = 0
        mutableMessage.nextRetryAt = nil

        modelContext.insert(mutableMessage)
        try modelContext.save()

        logQueue("✅ Enqueued message: \(message.id) for conversation: \(message.conversationId)")
    }

    /// 获取并清空所有离线队列中的消息
    /// 在 WebSocket 连接成功时调用（onOpen 回调）
    func drain(for conversationId: String? = nil) async throws -> [LocalMessage] {
        // 构建谓词：获取所有 syncState == .localOnly 的消息
        var predicate: Predicate<LocalMessage>

        if let conversationId {
            // 如果指定了 conversationId，只获取该对话的消息
            predicate = #Predicate<LocalMessage> { msg in
                msg.syncState == .localOnly && msg.conversationId == conversationId
            }
        } else {
            // 获取所有离线消息
            predicate = #Predicate<LocalMessage> { msg in
                msg.syncState == .localOnly
            }
        }

        let descriptor = FetchDescriptor(predicate: predicate)
        let allMessages = try modelContext.fetch(descriptor)
        let now = Date()
        let messages = allMessages.filter { message in
            guard let nextRetryAt = message.nextRetryAt else { return true }
            return nextRetryAt <= now
        }

        logQueue("🚰 Draining \(messages.count) offline messages for conversation: \(conversationId ?? "all")")

        return messages
    }

    /// 标记消息为已同步
    /// 在消息成功发送到服务器后调用
    func markSynced(_ messageId: String) async throws {
        var descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate<LocalMessage> { $0.id == messageId }
        )
        descriptor.fetchLimit = 1

        guard let message = try modelContext.fetch(descriptor).first else {
            logQueue("⚠️  Message not found for marking synced: \(messageId)")
            return
        }

        message.syncState = .synced
        message.updatedAt = Date()
        message.retryCount = 0
        message.nextRetryAt = nil

        try modelContext.save()

        logQueue("✅ Marked synced: \(messageId)")
    }

    /// 从队列中删除消息
    /// 在消息不可恢复的错误时调用
    func remove(_ messageId: String) async throws {
        var descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate<LocalMessage> { $0.id == messageId }
        )
        descriptor.fetchLimit = 1

        guard let message = try modelContext.fetch(descriptor).first else {
            logQueue("⚠️  Message not found for removal: \(messageId)")
            return
        }

        modelContext.delete(message)
        try modelContext.save()

        logQueue("🗑️  Removed message: \(messageId)")
    }

    /// 更新消息的重试信息
    func updateRetryState(messageId: String, retryCount: Int, nextRetryAt: Date?) async throws {
        var descriptor = FetchDescriptor<LocalMessage>(
            predicate: #Predicate<LocalMessage> { $0.id == messageId }
        )
        descriptor.fetchLimit = 1

        guard let message = try modelContext.fetch(descriptor).first else {
            logQueue("⚠️  Message not found for retry update: \(messageId)")
            return
        }

        message.retryCount = retryCount
        message.nextRetryAt = nextRetryAt
        message.localModifiedAt = Date()

        try modelContext.save()

        logQueue("🔁 Updated retry state for \(messageId) (retryCount=\(retryCount), nextRetryAt=\(String(describing: nextRetryAt)))")
    }

    // MARK: - Queue Status

    /// 获取队列中的消息数量
    func size(for conversationId: String? = nil) async throws -> Int {
        let predicate: Predicate<LocalMessage>

        if let conversationId {
            predicate = #Predicate<LocalMessage> { msg in
                msg.syncState == .localOnly && msg.conversationId == conversationId
            }
        } else {
            predicate = #Predicate<LocalMessage> { msg in
                msg.syncState == .localOnly
            }
        }

        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = Int.max

        return try modelContext.fetch(descriptor).count
    }

    /// 检查队列是否为空
    func isEmpty() async throws -> Bool {
        let predicate = #Predicate<LocalMessage> { msg in
            msg.syncState == .localOnly
        }

        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = 1

        return try modelContext.fetch(descriptor).isEmpty
    }

    // MARK: - Clear Queue

    /// 清空队列（用于调试或用户操作）
    func clear() async throws {
        let predicate = #Predicate<LocalMessage> { msg in
            msg.syncState == .localOnly
        }

        var descriptor = FetchDescriptor(predicate: predicate)
        descriptor.fetchLimit = Int.max

        let messages = try modelContext.fetch(descriptor)
        for message in messages {
            modelContext.delete(message)
        }

        try modelContext.save()

        logQueue("🧹 Cleared all offline messages (count: \(messages.count))")
    }

    // MARK: - Logging

    private func logQueue(_ message: String) {
        print("[LocalMessageQueue] \(message)")
    }
}

// MARK: - LocalMessageQueue Extension: Environment Key

/// SwiftUI Environment key for LocalMessageQueue
struct LocalMessageQueueKey: EnvironmentKey {
    static let defaultValue: LocalMessageQueue? = nil
}

extension EnvironmentValues {
    var localMessageQueue: LocalMessageQueue? {
        get { self[LocalMessageQueueKey.self] }
        set { self[LocalMessageQueueKey.self] = newValue }
    }
}

// MARK: - Usage Example

/*

 // 在 ChatViewModel 中使用
 @MainActor
 final class ChatViewModel: ObservableObject {
     private let queue: LocalMessageQueue

     func connectWebSocket() {
         socket.onOpen = { [weak self] in
             Task {
                 await self?.drainOfflineQueue()
             }
         }
     }

     private func drainOfflineQueue() async {
         do {
             let queuedMessages = try await queue.drain(for: conversationId)
             print("Draining \(queuedMessages.count) offline messages")

             for msg in queuedMessages {
                 await resendMessage(msg)
             }
         } catch {
             print("Error draining offline queue: \(error)")
         }
     }

     private func resendMessage(_ message: LocalMessage) async {
         do {
             let response = try await repository.sendMessage(
                 conversationId: message.conversationId,
                 senderId: message.senderId,
                 plaintext: message.plaintext,
                 idempotencyKey: message.id
             )

             // 标记为已同步
             try await queue.markSynced(message.id)
             print("Message resent successfully: \(message.id)")

         } catch {
             print("Failed to resend message: \(error)")
             // 重新入队以便下次重试
             try? await queue.enqueue(message)
         }
     }
 }

 */
