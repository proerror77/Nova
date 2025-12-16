import Foundation

// MARK: - Matrix Service Stubs
// Temporary stubs while MatrixRustSDK compatibility is being resolved

/// Stub for MatrixBridgeService
@MainActor
class MatrixBridgeService {
    static let shared = MatrixBridgeService()

    var isInitialized: Bool = false
    var isE2EEAvailable: Bool = false
    var onMatrixMessage: ((String, MatrixMessage) -> Void)?
    var onTypingIndicator: ((String, [String]) -> Void)?

    private init() {}

    func initialize() async throws {
        // Stub - Matrix integration disabled
        print("[MatrixBridgeService] Stub: Matrix integration temporarily disabled")
    }

    func shutdown() async {
        // Stub
    }

    func sendMessage(to roomId: String, content: String) async throws -> String {
        // Stub - return empty event ID
        return ""
    }

    func sendMessage(conversationId: String, content: String) async throws -> String {
        // Stub - return empty event ID
        return ""
    }

    func convertToNovaMessage(_ matrixMessage: MatrixMessage, conversationId: String) -> Message? {
        // Stub
        return nil
    }

    func getOrCreateRoom(for conversationId: String, participants: [String]) async throws -> String {
        // Stub
        return ""
    }

    func startConversationWithFriend(userId: String, username: String) async throws -> String {
        // Stub - return empty conversation ID
        return ""
    }

    /// Start E2EE conversation with a friend - returns Conversation
    /// This method won't be called when isE2EEAvailable is false
    func startConversationWithFriend(friendUserId: String) async throws -> Conversation {
        // Stub - Matrix integration disabled, this shouldn't be called
        throw MatrixStubError.matrixDisabled
    }

    /// Create Matrix room for an existing conversation
    /// This method won't be called when isE2EEAvailable is false
    func createRoomForConversation(_ conversation: Conversation) async throws -> String {
        // Stub - Matrix integration disabled, this shouldn't be called
        throw MatrixStubError.matrixDisabled
    }
}

/// Error type for Matrix stubs
enum MatrixStubError: LocalizedError {
    case matrixDisabled

    var errorDescription: String? {
        switch self {
        case .matrixDisabled:
            return "Matrix integration is temporarily disabled"
        }
    }
}

/// Stub Matrix message type
struct MatrixMessage {
    let eventId: String
    let senderId: String
    let content: String
    let timestamp: Date

    /// Alias for eventId to match expected interface
    var id: String { eventId }
}

/// Stub for MatrixService
@MainActor
class MatrixService {
    static let shared = MatrixService()

    private init() {}

    func startSync() async throws {
        // Stub
    }

    func stopSync() {
        // Stub
    }
}
