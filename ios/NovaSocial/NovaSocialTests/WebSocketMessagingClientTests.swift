import XCTest
@testable import NovaSocial

final class WebSocketMessagingClientTests: XCTestCase {
    func testDecodeServerMessageEnvelope() throws {
        let json = """
        {"type":"message","message":{"id":"00000000-0000-0000-0000-000000000001","sender_id":"00000000-0000-0000-0000-0000000000AA","sequence_number":5}}
        """.data(using: .utf8)!
        struct Envelope: Decodable { let type: String; let message: MessageDto }
        let env = try JSONDecoder().decode(Envelope.self, from: json)
        XCTAssertEqual(env.type, "message")
        XCTAssertEqual(env.message.sequenceNumber, 5)
    }
}

