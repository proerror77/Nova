#if CRYPTOCORE_FFI
import XCTest
@testable import NovaSocial

final class CryptoCoreFFITests: XCTestCase {
    func testFFINonceAndEncrypt() throws {
        let nonce = CryptoCoreProvider.shared.generateNonce()
        XCTAssertEqual(nonce.count, 24)
        let msg = Data("ffi-hello".utf8)
        let km = KeyManager.shared.getOrCreateMyKeypair()
        let ct = try CryptoCoreProvider.shared.encrypt(plaintext: msg, recipientPublicKey: km.publicKey, senderSecretKey: km.secretKey, nonce: nonce)
        XCTAssertFalse(ct.isEmpty)
    }
}
#endif

