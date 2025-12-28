import Foundation

// MARK: - Room Operations Extension

extension MatrixBridgeService {

    // MARK: - Room Creation

    /// Create Matrix room for a new Nova conversation
    @discardableResult
    func createRoomForConversation(_ conversation: Conversation) async throws -> String {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let isDirect = conversation.type == .direct
        let participantIds = conversation.participants

        let roomId = try await matrixService.createRoom(
            name: isDirect ? nil : conversation.name,
            isDirect: isDirect,
            inviteUserIds: participantIds,
            isEncrypted: conversation.isEncrypted  // Use E2EE only for private chats
        )

        #if DEBUG
        print("[MatrixBridge] Created room \(roomId) for conversation \(conversation.id)")
        #endif

        // Cache and save the mapping
        cacheMapping(conversationId: conversation.id, roomId: roomId)
        try await saveRoomMapping(conversationId: conversation.id, roomId: roomId)

        return roomId
    }

    /// Create a new conversation with a friend and setup Matrix room
    /// This is the main entry point for starting a chat with a friend
    /// - Parameters:
    ///   - friendUserId: The user ID of the friend to chat with
    ///   - isPrivate: Whether this is a private (E2EE encrypted) chat. Default is false (plain text)
    func startConversationWithFriend(friendUserId: String, isPrivate: Bool = false) async throws -> Conversation {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        guard let currentUserId = AuthenticationManager.shared.currentUser?.id else {
            throw MatrixBridgeError.notAuthenticated
        }

        #if DEBUG
        print("[MatrixBridge] Starting \(isPrivate ? "private" : "regular") conversation with friend: \(friendUserId)")
        #endif

        // Create Nova conversation first
        let conversation = try await chatService.createConversation(
            type: .direct,
            participantIds: [currentUserId, friendUserId],
            name: nil,
            isEncrypted: isPrivate
        )

        // Create Matrix room - only use E2EE for private chats
        let roomId = try await matrixService.createRoom(
            name: nil,
            isDirect: true,
            inviteUserIds: [friendUserId],
            isEncrypted: isPrivate
        )

        // Save mapping
        cacheMapping(conversationId: conversation.id, roomId: roomId)
        try await saveRoomMapping(conversationId: conversation.id, roomId: roomId)

        #if DEBUG
        print("[MatrixBridge] Created \(isPrivate ? "private" : "regular") conversation \(conversation.id) with Matrix room \(roomId)")
        #endif

        return conversation
    }

    // MARK: - Room Membership

    /// Invite user to conversation's Matrix room
    func inviteUser(conversationId: String, userId: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.inviteUser(roomId: roomId, userId: userId)
    }

    /// Remove user from conversation's Matrix room
    func removeUser(conversationId: String, userId: String, reason: String? = nil) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.kickUser(roomId: roomId, userId: userId, reason: reason)
    }

    /// Update user power level in conversation's Matrix room
    /// - Parameters:
    ///   - conversationId: Conversation ID
    ///   - userId: User ID to update
    ///   - powerLevel: New power level (0=member, 50=moderator/admin, 100=owner)
    func updateMemberPowerLevel(conversationId: String, userId: String, powerLevel: Int) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        let roomId = try await resolveRoomId(for: conversationId)
        try await matrixService.updatePowerLevel(roomId: roomId, userId: userId, powerLevel: powerLevel)

        #if DEBUG
        print("[MatrixBridge] ✅ Updated power level for user \(userId) to \(powerLevel)")
        #endif
    }

    // MARK: - Room Queries

    /// Get all Matrix rooms as conversations
    func getMatrixRooms() async throws -> [MatrixRoom] {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        return try await matrixService.getJoinedRooms()
    }

    // MARK: - Leave Room

    /// Leave/delete a conversation (leave the Matrix room)
    func leaveConversation(conversationId: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        // Get the Matrix room ID for this conversation
        let roomId = try await getRoomId(for: conversationId)

        #if DEBUG
        print("[MatrixBridgeService] Leaving conversation: \(conversationId), roomId: \(roomId)")
        #endif

        // Leave the Matrix room
        try await matrixService.leaveRoom(roomId: roomId)

        // Clear the mapping cache
        clearMapping(conversationId: conversationId, roomId: roomId)

        #if DEBUG
        print("[MatrixBridgeService] Successfully left conversation: \(conversationId)")
        #endif
    }

    /// Leave a room by room ID directly
    func leaveRoom(roomId: String) async throws {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        #if DEBUG
        print("[MatrixBridgeService] Leaving room: \(roomId)")
        #endif

        try await matrixService.leaveRoom(roomId: roomId)
    }

    // MARK: - Room Members

    /// Room member information
    struct RoomMember {
        let userId: String
        let displayName: String?
        let avatarUrl: String?
        let powerLevel: Int
        let isAdmin: Bool

        init(userId: String, displayName: String?, avatarUrl: String?, powerLevel: Int, isAdmin: Bool = false) {
            self.userId = userId
            self.displayName = displayName
            self.avatarUrl = avatarUrl
            self.powerLevel = powerLevel
            self.isAdmin = isAdmin
        }
    }

    /// Get members of a room using Matrix SDK
    func getRoomMembers(roomId: String) async throws -> [RoomMember] {
        guard isInitialized else {
            throw MatrixBridgeError.notInitialized
        }

        // Resolve room ID if needed
        let resolvedRoomId = try await resolveRoomId(for: roomId)

        #if DEBUG
        print("[MatrixBridgeService] Getting members for room: \(resolvedRoomId)")
        #endif

        // Use Matrix SDK to get real members
        do {
            let matrixMembers = try await matrixService.getRoomMembers(roomId: resolvedRoomId)

            let members = matrixMembers.map { member in
                RoomMember(
                    userId: member.userId,
                    displayName: member.displayName,
                    avatarUrl: member.avatarUrl,
                    powerLevel: member.powerLevel,
                    isAdmin: member.isAdmin
                )
            }

            #if DEBUG
            print("[MatrixBridgeService] Found \(members.count) real members in room")
            #endif

            return members
        } catch {
            #if DEBUG
            print("[MatrixBridgeService] Failed to get members from Matrix SDK: \(error), using fallback")
            #endif

            // Fallback: try to get room info
            let rooms = try await matrixService.getJoinedRooms()
            guard let room = rooms.first(where: { $0.id == resolvedRoomId }) else {
                throw MatrixBridgeError.roomNotFound
            }

            var members: [RoomMember] = []

            // Add current user
            if let userId = matrixService.userId {
                members.append(RoomMember(
                    userId: userId,
                    displayName: nil,
                    avatarUrl: nil,
                    powerLevel: 100,
                    isAdmin: true
                ))
            }

            // Add placeholder for other members
            for i in 1..<room.memberCount {
                members.append(RoomMember(
                    userId: "member_\(i)",
                    displayName: "Member \(i)",
                    avatarUrl: nil,
                    powerLevel: 0,
                    isAdmin: false
                ))
            }

            return members
        }
    }

    /// Get members of a conversation by conversation ID
    func getConversationMembers(conversationId: String) async throws -> [RoomMember] {
        let roomId = try await resolveRoomId(for: conversationId)
        return try await getRoomMembers(roomId: roomId)
    }
}
