import Testing
import Foundation

@Suite("WS decode envelope")
struct WebSocketDecodeTests {
    struct MessageDtoTest: Decodable, Equatable {
        let id: UUID
        let senderId: UUID
        let sequenceNumber: Int64
        let createdAt: String?
        enum CodingKeys: String, CodingKey { case id; case senderId = "sender_id"; case sequenceNumber = "sequence_number"; case createdAt = "created_at" }
    }
    struct Envelope: Decodable { let type: String; let message: MessageDtoTest }

    @Test("decodes server message envelope")
    func testDecode() throws {
        let json = """
        {"type":"message","message":{"id":"00000000-0000-0000-0000-000000000001","sender_id":"00000000-0000-0000-0000-0000000000AA","sequence_number":42}}
        """.data(using: .utf8)!
        let env = try JSONDecoder().decode(Envelope.self, from: json)
        #expect(env.type == "message")
        #expect(env.message.sequenceNumber == 42)
    }
}

