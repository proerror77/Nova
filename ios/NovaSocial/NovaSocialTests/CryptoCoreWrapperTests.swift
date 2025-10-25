import XCTest
@testable import NovaSocial

final class CryptoCoreWrapperTests: XCTestCase {
    func testBase64FallbackRoundtrip() throws {
        let msg = "hello, crypto"
        let nonce = CryptoCoreProvider.shared.generateNonce()
        let keys = KeyManager.shared.getOrCreateMyKeypair()
        let ct = try CryptoCoreProvider.shared.encrypt(plaintext: Data(msg.utf8), recipientPublicKey: keys.publicKey, senderSecretKey: keys.secretKey, nonce: nonce)
        let pt = try CryptoCoreProvider.shared.decrypt(ciphertext: ct, senderPublicKey: keys.publicKey, recipientSecretKey: keys.secretKey, nonce: nonce)
        XCTAssertEqual(String(data: pt, encoding: .utf8), msg)
    }
}

