import Foundation

#if canImport(TweetNacl)
import TweetNacl

enum NaClCryptoError: Error {
    case invalidKey
    case invalidCiphertext
}

struct NaClCrypto {
    static func generateKeyPair() throws -> (publicKeyB64: String, secretKeyB64: String) {
        let kp = try NaclBox.keyPair()
        let pk = kp.publicKey
        let sk = kp.secretKey
        return (pk.base64EncodedString(), sk.base64EncodedString())
    }

    static func encrypt(plaintext: Data, mySecretKeyB64: String, recipientPublicKeyB64: String) throws -> (ciphertextB64: String, nonceB64: String) {
        guard let sk = Data(base64Encoded: mySecretKeyB64), sk.count == 32,
              let pk = Data(base64Encoded: recipientPublicKeyB64), pk.count == 32 else {
            throw NaClCryptoError.invalidKey
        }
        let nonce = NaclBox.nonce()
        let box = try NaclBox.box(message: plaintext, nonce: nonce, publicKey: pk, secretKey: sk)
        return (box.base64EncodedString(), nonce.base64EncodedString())
    }

    static func decrypt(ciphertextB64: String, nonceB64: String, senderPublicKeyB64: String, mySecretKeyB64: String) throws -> Data {
        guard let sk = Data(base64Encoded: mySecretKeyB64), sk.count == 32,
              let pk = Data(base64Encoded: senderPublicKeyB64), pk.count == 32,
              let nonce = Data(base64Encoded: nonceB64), nonce.count == 24,
              let ciphertext = Data(base64Encoded: ciphertextB64) else {
            throw NaClCryptoError.invalidKey
        }
        let opened = try NaclBox.open(ciphertext: ciphertext, nonce: nonce, publicKey: pk, secretKey: sk)
        return opened
    }
}
#else
enum NaClCryptoError: Error { case unavailable(String) }

struct NaClCrypto {
    static func generateKeyPair() throws -> (publicKeyB64: String, secretKeyB64: String) {
        throw NaClCryptoError.unavailable("TweetNacl not installed. Add https://github.com/bitmark-inc/tweetnacl-swiftwrap via SPM.")
    }
    static func encrypt(plaintext: Data, mySecretKeyB64: String, recipientPublicKeyB64: String) throws -> (ciphertextB64: String, nonceB64: String) {
        throw NaClCryptoError.unavailable("TweetNacl not installed. Add https://github.com/bitmark-inc/tweetnacl-swiftwrap via SPM.")
    }
    static func decrypt(ciphertextB64: String, nonceB64: String, senderPublicKeyB64: String, mySecretKeyB64: String) throws -> Data {
        throw NaClCryptoError.unavailable("TweetNacl not installed. Add https://github.com/bitmark-inc/tweetnacl-swiftwrap via SPM.")
    }
}
#endif

