import Foundation

/// Represents a notification for user engagement
struct Notification: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let userId: String
    let actionType: String
    let targetId: String
    let timestamp: String
    let actor: User

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case actionType = "action_type"
        case targetId = "target_id"
        case timestamp
        case actor
    }

    init(
        id: String,
        userId: String,
        actionType: String,
        targetId: String,
        timestamp: String,
        actor: User
    ) {
        self.id = id
        self.userId = userId
        self.actionType = actionType
        self.targetId = targetId
        self.timestamp = timestamp
        self.actor = actor
    }
}
