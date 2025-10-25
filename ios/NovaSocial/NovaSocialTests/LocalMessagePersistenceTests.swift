import XCTest
@testable import NovaSocial

final class LocalMessagePersistenceTests: XCTestCase {
    func testSaveFetchDeleteLocalMessage() async throws {
        let storage = LocalStorageManager.shared
        let cid = UUID().uuidString
        let uid = UUID().uuidString
        let tempId = UUID().uuidString
        let msg = LocalMessage(id: tempId, conversationId: cid, senderId: uid, plaintext: "hello")
        try await storage.save(msg)

        let fetched = try await storage.fetch(LocalMessage.self, predicate: #Predicate { $0.conversationId == cid })
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, tempId)

        try await storage.delete(msg)
        let after = try await storage.fetch(LocalMessage.self, predicate: #Predicate { $0.conversationId == cid })
        XCTAssertEqual(after.count, 0)
    }
}

