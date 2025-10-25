import XCTest
@testable import NovaSocial

final class MessagingViewModelTypingAndReplayTests: XCTestCase {
    final class FlipRepo: MessagingRepository {
        var fail = true
        override func sendMessage(conversationId: UUID, senderId: UUID, plaintext: String, idempotencyKey: UUID = UUID()) async throws -> MessageDto {
            if fail { throw NSError(domain: "offline", code: -1009) }
            return MessageDto(id: UUID(), senderId: senderId, sequenceNumber: 1, createdAt: nil)
        }
        override func fetchMessages(conversationId: UUID, limit: Int? = nil, before: UUID? = nil) async throws -> [MessageDto] { [] }
    }

    @MainActor
    func testTypingAutoClear() async throws {
        let vm = MessagingViewModel()
        let cid = UUID(), uid = UUID()
        await vm.load(conversationId: cid)
        vm.connect(conversationId: cid, userId: uid)
        let other = UUID()
        vm._receiveTyping(other)
        XCTAssertTrue(vm.typingUsers.contains(other))
        try await Task.sleep(for: .seconds(3) + .milliseconds(200))
        XCTAssertFalse(vm.typingUsers.contains(other))
    }

    @MainActor
    func testOfflineReplayDeletesLocalMessage() async throws {
        let repo = FlipRepo()
        let vm = MessagingViewModel(repo: repo)
        let cid = UUID(), uid = UUID()
        await vm.load(conversationId: cid)
        vm.connect(conversationId: cid, userId: uid)
        // First send fails -> should persist locally
        await vm.sendMessage("hello")
        let storage = LocalStorageManager.shared
        let pending1 = try await storage.fetch(LocalMessage.self, predicate: #Predicate { $0.conversationId == cid.uuidString })
        XCTAssertEqual(pending1.count, 1)
        // Flip to success and reconnect to trigger replay
        repo.fail = false
        vm.connect(conversationId: cid, userId: uid)
        try await Task.sleep(for: .milliseconds(300))
        let pending2 = try await storage.fetch(LocalMessage.self, predicate: #Predicate { $0.conversationId == cid.uuidString })
        XCTAssertEqual(pending2.count, 0)
    }
}

