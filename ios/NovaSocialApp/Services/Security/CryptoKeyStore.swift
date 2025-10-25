import Foundation
import Security

/// Stores NaCl keypair in Keychain and uploads public key when needed
final class CryptoKeyStore {
    static let shared = CryptoKeyStore()

    private let service = "com.nova.social"
    private let pkKey = "nacl_public_key"
    private let skKey = "nacl_secret_key"

    private init() {}

    func ensureKeyPair() throws -> (publicKeyB64: String, secretKeyB64: String) {
        if let pk = load(pkKey), let sk = load(skKey) {
            return (pk, sk)
        }
        let (pk, sk) = try NaClCrypto.generateKeyPair()
        save(pk, key: pkKey)
        save(sk, key: skKey)
        return (pk, sk)
    }

    func getPublicKey() -> String? { load(pkKey) }
    func getSecretKey() -> String? { load(skKey) }

    // MARK: - Keychain
    private func save(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var newQuery = query
        newQuery[kSecValueData as String] = data
        newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(newQuery as CFDictionary, nil)
    }

    private func load(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

