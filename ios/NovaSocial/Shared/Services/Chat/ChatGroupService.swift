import Foundation

// MARK: - Chat Group Service

/// Chat Group Service - 群组管理服务
/// 职责：
/// - 添加/移除群组成员
/// - 更新群组成员角色
/// - Matrix SDK 与 REST API 双协议支持
@MainActor
final class ChatGroupService {
    // MARK: - Properties

    private let client = APIClient.shared
    private let matrixBridge = MatrixBridgeService.shared

    // MARK: - Group Management

    /// 添加成员到群组会话 - 優先使用 Matrix SDK
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - userIds: 要添加的用户ID列表
    @MainActor
    func addGroupMembers(conversationId: String, userIds: [String]) async throws {
        // 優先使用 Matrix SDK
        if matrixBridge.isInitialized {
            var successCount = 0
            var errors: [Error] = []

            for userId in userIds {
                do {
                    try await matrixBridge.inviteUser(
                        conversationId: conversationId,
                        userId: userId
                    )
                    successCount += 1
                } catch {
                    errors.append(error)
                    #if DEBUG
                    print("[ChatGroupService] Matrix invite failed for user \(userId): \(error)")
                    #endif
                }
            }

            if successCount == userIds.count {
                #if DEBUG
                print("[ChatGroupService] ✅ Added \(successCount) members via Matrix SDK to conversation \(conversationId)")
                #endif
                return
            } else if successCount > 0 {
                // 部分成功，不 fallback
                #if DEBUG
                print("[ChatGroupService] ⚠️ Partially added \(successCount)/\(userIds.count) members via Matrix SDK")
                #endif
                return
            }
            // 全部失敗，fallback 到 REST API
            #if DEBUG
            print("[ChatGroupService] Matrix addGroupMembers failed, falling back to REST API")
            #endif
        }

        // Fallback: REST API
        struct Response: Codable {
            let success: Bool
        }

        let request = AddGroupMembersRequest(userIds: userIds)

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.addGroupMembers(conversationId),
            method: "POST",
            body: request
        )

        #if DEBUG
        print("[ChatGroupService] Added \(userIds.count) members via REST API to conversation \(conversationId)")
        #endif
    }

    /// 从群组会话中移除成员 - 優先使用 Matrix SDK
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - userId: 要移除的用户ID
    ///   - reason: 移除原因（可選）
    @MainActor
    func removeGroupMember(conversationId: String, userId: String, reason: String? = nil) async throws {
        // 優先使用 Matrix SDK
        if matrixBridge.isInitialized {
            do {
                try await matrixBridge.removeUser(
                    conversationId: conversationId,
                    userId: userId,
                    reason: reason
                )
                #if DEBUG
                print("[ChatGroupService] ✅ Removed member \(userId) via Matrix SDK from conversation \(conversationId)")
                #endif
                return
            } catch {
                #if DEBUG
                print("[ChatGroupService] Matrix removeUser failed, falling back to REST API: \(error)")
                #endif
            }
        }

        // Fallback: REST API
        struct EmptyResponse: Codable {}

        let _: EmptyResponse = try await client.request(
            endpoint: APIConfig.Chat.removeGroupMember(conversationId: conversationId, userId: userId),
            method: "DELETE"
        )

        #if DEBUG
        print("[ChatGroupService] Removed member \(userId) via REST API from conversation \(conversationId)")
        #endif
    }

    /// 更新群组成员角色
    /// - Parameters:
    ///   - conversationId: 会话ID
    ///   - userId: 用户ID
    ///   - role: 新角色（owner/admin/member）
    /// - Note: 優先使用 Matrix power levels，失敗時 fallback 到 REST API
    @MainActor
    func updateMemberRole(conversationId: String, userId: String, role: GroupMemberRole) async throws {
        // Convert role to Matrix power level
        let powerLevel: Int
        switch role {
        case .owner:
            powerLevel = 100  // Full admin rights
        case .admin:
            powerLevel = 50   // Moderator rights
        case .member:
            powerLevel = 0    // Regular member
        }

        // 優先使用 Matrix SDK power levels
        if matrixBridge.isInitialized {
            do {
                try await matrixBridge.updateMemberPowerLevel(
                    conversationId: conversationId,
                    userId: userId,
                    powerLevel: powerLevel
                )
                #if DEBUG
                print("[ChatGroupService] ✅ Updated role via Matrix power levels: \(role.rawValue) (PL:\(powerLevel))")
                #endif
                return
            } catch {
                #if DEBUG
                print("[ChatGroupService] Matrix power level update failed, falling back to REST API: \(error)")
                #endif
            }
        }

        // Fallback: REST API
        struct Response: Codable {
            let success: Bool
        }

        let request = UpdateMemberRoleRequest(role: role)

        let _: Response = try await client.request(
            endpoint: APIConfig.Chat.updateMemberRole(conversationId: conversationId, userId: userId),
            method: "PUT",
            body: request
        )

        #if DEBUG
        print("[ChatGroupService] Updated role for user \(userId) to \(role.rawValue) via REST API")
        #endif
    }
}
