import Foundation
import Security

/// KeyManager - manages user keypairs and peer public keys
final class KeyManager {
    static let shared = KeyManager()
    private init() {}

    // NOTE: Demo only. Replace with secure keychain/KeyStore in production.
    private let myPubKeyKey = "e2e.my_public_key"
    private let mySecKeyKey = "e2e.my_secret_key"

    func getOrCreateMyKeypair() -> (publicKey: Data, secretKey: Data) {
        if let pub = UserDefaults.standard.data(forKey: myPubKeyKey),
           let sec = UserDefaults.standard.data(forKey: mySecKeyKey) {
            return (pub, sec)
        }
        // For demo, generate random 32-byte keys; replace with real Curve25519 keys if using libsodium FFI
        let pub = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let sec = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        UserDefaults.standard.set(pub, forKey: myPubKeyKey)
        UserDefaults.standard.set(sec, forKey: mySecKeyKey)
        return (pub, sec)
    }

    func getPeerPublicKey(for userId: UUID) -> Data? {
        // TODO: fetch from server profile or conversation member info. For demo, reuse my own key.
        return getOrCreateMyKeypair().publicKey
    }
}

