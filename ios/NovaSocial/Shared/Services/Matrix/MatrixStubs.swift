import Foundation

// MARK: - Matrix Stubs
// Placeholder implementations for Matrix services that are not yet fully implemented

enum VerificationState {
    case unknown
    case verified
    case unverified
}

struct DirectRoom {
    let id: String
}

final class MatrixBridgeService {
    static let shared = MatrixBridgeService()

    private init() {}

    var isEnabled: Bool { false }
    var isConnected: Bool { false }
    var isInitialized: Bool { false }

    func initialize(requireLogin: Bool = false) async throws {}
    func connect() async throws {}
    func disconnect() async throws {}

    func createDirectConversation(withUserId userId: String, displayName: String) async throws -> DirectRoom {
        return DirectRoom(id: "")
    }

    func shutdown(clearCredentials: Bool = false) async {}
}

final class MatrixService {
    static let shared = MatrixService()

    private init() {}

    var isLoggedIn: Bool { false }

    func getVerificationState() -> VerificationState {
        return .unknown
    }
}
