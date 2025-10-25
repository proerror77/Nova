import Foundation
import SwiftData

// MARK: - LocalMessage (本地離線消息)

@Model
final class LocalMessage {
    @Attribute(.unique) var id: String               // 使用 idempotency_key 作為臨時 ID（UUID 字串）
    var conversationId: String
    var senderId: String
    var plaintext: String
    var sequenceNumber: Int64?
    var createdAt: Date
    var updatedAt: Date

    // 同步相關
    var syncState: SyncState
    var localModifiedAt: Date?

    init(
        id: String,
        conversationId: String,
        senderId: String,
        plaintext: String,
        sequenceNumber: Int64? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        syncState: SyncState = .localOnly,
        localModifiedAt: Date? = Date()
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.plaintext = plaintext
        self.sequenceNumber = sequenceNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncState = syncState
        self.localModifiedAt = localModifiedAt
    }
}

// MARK: - Syncable Conformance

extension LocalMessage: Syncable {}

