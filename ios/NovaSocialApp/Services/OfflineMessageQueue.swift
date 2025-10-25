import Foundation

/// 离线消息队列
/// 当网络不可用时，保存待发送的消息
/// 网络恢复时，自动重新发送
final class OfflineMessageQueue: ObservableObject {
    static let shared = OfflineMessageQueue()

    @Published var pendingCount: Int = 0

    private let queue = DispatchQueue(label: "com.nova.offline-queue")
    private let defaults = UserDefaults.standard
    private let key = "offlineMessages"
    private var messages: [OfflineMessage] = []
    private var isSyncing = false

    init() {
        queue.async {
            self.loadMessages()
        }
    }

    // MARK: - Models

    struct OfflineMessage: Codable {
        let id: UUID
        let conversationId: UUID
        let peerUserId: UUID
        let text: String
        let createdAt: Date
        var retryCount: Int = 0
        let maxRetries: Int = 3

        var canRetry: Bool {
            retryCount < maxRetries
        }
    }

    // MARK: - Public API

    /// 添加消息到离线队列
    func enqueue(conversationId: UUID, peerUserId: UUID, text: String) {
        let message = OfflineMessage(
            id: UUID(),
            conversationId: conversationId,
            peerUserId: peerUserId,
            text: text,
            createdAt: Date()
        )

        queue.async {
            self.messages.append(message)
            self.saveMessages()
            DispatchQueue.main.async {
                self.pendingCount = self.messages.count
            }
        }
    }

    /// 当网络恢复时调用
    func syncPendingMessages(repository: MessagingRepository) async {
        guard !isSyncing else { return }
        isSyncing = true

        let messagesToSync = queue.sync { self.messages }

        for var message in messagesToSync {
            do {
                try await repository.sendText(
                    conversationId: message.conversationId,
                    to: message.peerUserId,
                    text: message.text
                )
                // 成功发送，从队列移除
                await remove(messageId: message.id)
            } catch {
                message.retryCount += 1
                if message.canRetry {
                    // 更新重试次数
                    queue.async {
                        if let index = self.messages.firstIndex(where: { $0.id == message.id }) {
                            self.messages[index].retryCount = message.retryCount
                            self.saveMessages()
                        }
                    }
                } else {
                    // 超过最大重试次数，移除
                    await remove(messageId: message.id)
                }
            }
        }

        isSyncing = false
    }

    /// 清空所有待发送消息
    func clear() {
        queue.async {
            self.messages.removeAll()
            self.saveMessages()
            DispatchQueue.main.async {
                self.pendingCount = 0
            }
        }
    }

    /// 获取待发送消息数量
    func getCount() -> Int {
        queue.sync { self.messages.count }
    }

    // MARK: - Private

    private func remove(messageId: UUID) async {
        queue.async {
            self.messages.removeAll { $0.id == messageId }
            self.saveMessages()
            DispatchQueue.main.async {
                self.pendingCount = self.messages.count
            }
        }
    }

    private func saveMessages() {
        do {
            let data = try JSONEncoder().encode(messages)
            defaults.set(data, forKey: key)
        } catch {
            print("Failed to save offline messages: \(error)")
        }
    }

    private func loadMessages() {
        guard let data = defaults.data(forKey: key) else { return }
        do {
            messages = try JSONDecoder().decode([OfflineMessage].self, from: data)
            DispatchQueue.main.async {
                self.pendingCount = self.messages.count
            }
        } catch {
            print("Failed to load offline messages: \(error)")
        }
    }
}
