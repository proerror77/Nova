import XCTest
@testable import NovaSocial

final class MessagingViewModelTests: XCTestCase {
    final class MockRepo: MessagingRepository {
        var sent: [(UUID, UUID, String)] = []
        override func sendMessage(conversationId: UUID, senderId: UUID, plaintext: String, idempotencyKey: UUID = UUID()) async throws -> MessageDto {
            sent.append((conversationId, senderId, plaintext))
            return MessageDto(id: UUID(), senderId: senderId, sequenceNumber: Int64(sent.count), createdAt: nil)
        }
        override func fetchMessages(conversationId: UUID, limit: Int? = nil, before: UUID? = nil) async throws -> [MessageDto] {
            return []
        }
    }

    @MainActor
    func testReceiveMessageOrdersAndDedups() async {
        let repo = MockRepo()
        let vm = MessagingViewModel(repo: repo)
        let cid = UUID(), uid = UUID()
        await vm.load(conversationId: cid)
        vm.connect(conversationId: cid, userId: uid)

        let m2 = MessageDto(id: UUID(), senderId: uid, sequenceNumber: 2, createdAt: nil)
        let m1 = MessageDto(id: UUID(), senderId: uid, sequenceNumber: 1, createdAt: nil)
        vm._receiveMessage(m2)
        vm._receiveMessage(m1)
        XCTAssertEqual(vm.messages.map{ $0.sequenceNumber }, [1,2])
        vm._receiveMessage(MessageDto(id: UUID(), senderId: uid, sequenceNumber: 1, createdAt: nil))
        XCTAssertEqual(vm.messages.count, 2)
    }
}
