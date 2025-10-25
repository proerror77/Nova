import XCTest
@testable import NovaSocial

final class E2EEncodingFormatTests: XCTestCase {
    final class CaptureRepo: MessagingRepository {
        var captured: String?
        override func sendMessage(conversationId: UUID, senderId: UUID, plaintext: String, idempotencyKey: UUID = UUID()) async throws -> MessageDto {
            captured = plaintext
            return MessageDto(id: UUID(), senderId: senderId, sequenceNumber: 1, createdAt: nil, contentEncrypted: nil, contentNonce: nil)
        }
        override func fetchMessages(conversationId: UUID, limit: Int? = nil, before: UUID? = nil) async throws -> [MessageDto] { [] }
    }

    @MainActor
    func testENCV1Format() async throws {
        let repo = CaptureRepo()
        let vm = MessagingViewModel(repo: repo)
        let cid = UUID(), uid = UUID()
        await vm.load(conversationId: cid)
        vm.connect(conversationId: cid, userId: uid)
        await vm.sendMessage("hello-e2e")
        guard let payload = repo.captured else { return XCTFail("no payload") }
        // Format: ENC:v1:<nonce_b64>:<cipher_b64>
        XCTAssertTrue(payload.hasPrefix("ENC:v1:"))
        let parts = payload.split(separator: ":")
        XCTAssertEqual(parts.count, 4)
        // decode cipher (Base64 fallback in tests) => plaintext
        if let ct = Data(base64Encoded: String(parts[3])) {
            XCTAssertEqual(String(data: ct, encoding: .utf8), "hello-e2e")
        }
    }
}

