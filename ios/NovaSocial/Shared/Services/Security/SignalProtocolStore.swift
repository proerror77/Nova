import Foundation
import Security
import LibSignalClient

// MARK: - Signal Protocol Store
// Implements all 6 store protocols required by libsignal-client:
// - IdentityKeyStore
// - PreKeyStore
// - SignedPreKeyStore
// - KyberPreKeyStore
// - SessionStore
// - SenderKeyStore

/// Empty context for store operations
struct NullContext: StoreContext {}

/// Keychain-backed implementation of Signal Protocol stores
/// Provides secure, persistent storage for all cryptographic material
final class SignalProtocolStore {

    // MARK: - Constants

    private enum KeychainKey {
        static let service = "com.nova.signal"
        static let identityKeyPair = "identity_key_pair"
        static let registrationId = "registration_id"
        static let preKeyPrefix = "prekey_"
        static let signedPreKeyPrefix = "signed_prekey_"
        static let kyberPreKeyPrefix = "kyber_prekey_"
        static let sessionPrefix = "session_"
        static let senderKeyPrefix = "sender_key_"
        static let identityPrefix = "identity_"
    }

    // MARK: - Cached Identity

    private var _identityKeyPair: IdentityKeyPair?
    private var _registrationId: UInt32?

    // MARK: - Singleton

    static let shared = SignalProtocolStore()

    private init() {
        // Load or generate registration ID
        if let existingRegId = loadRegistrationId() {
            _registrationId = existingRegId
        } else {
            let regId = UInt32.random(in: 1...0x3FFF)
            saveRegistrationId(regId)
            _registrationId = regId
        }

        // Load or generate identity key pair
        if let data = loadFromKeychain(key: KeychainKey.identityKeyPair),
           let keyPair = try? IdentityKeyPair(bytes: data) {
            _identityKeyPair = keyPair
        } else {
            let keyPair = IdentityKeyPair.generate()
            saveToKeychain(data: Data(keyPair.serialize()), key: KeychainKey.identityKeyPair)
            _identityKeyPair = keyPair
        }
    }

    // MARK: - Public Accessors

    func getIdentityKeyPair() throws -> IdentityKeyPair {
        guard let keyPair = _identityKeyPair else {
            throw SignalProtocolError.invalidState("Identity key pair not initialized")
        }
        return keyPair
    }

    func getLocalRegistrationId() -> UInt32 {
        return _registrationId ?? 0
    }

    // MARK: - Key Generation

    /// Generate batch of prekeys
    func generatePreKeys(start: UInt32, count: UInt32) throws -> [PreKeyRecord] {
        var preKeys: [PreKeyRecord] = []

        for i in 0..<count {
            let id = start + i
            let record = try PreKeyRecord(id: id, privateKey: PrivateKey.generate())
            try storePreKey(record, id: id, context: NullContext())
            preKeys.append(record)
        }

        return preKeys
    }

    /// Generate a signed prekey
    func generateSignedPreKey(id: UInt32) throws -> SignedPreKeyRecord {
        let identityKeyPair = try getIdentityKeyPair()
        let privateKey = PrivateKey.generate()
        let signature = identityKeyPair.privateKey.generateSignature(
            message: privateKey.publicKey.serialize()
        )

        let record = try SignedPreKeyRecord(
            id: id,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            privateKey: privateKey,
            signature: signature
        )

        try storeSignedPreKey(record, id: id, context: NullContext())
        return record
    }

    /// Generate a Kyber prekey (post-quantum)
    func generateKyberPreKey(id: UInt32) throws -> KyberPreKeyRecord {
        let identityKeyPair = try getIdentityKeyPair()
        let keyPair = KEMKeyPair.generate()
        let signature = identityKeyPair.privateKey.generateSignature(
            message: keyPair.publicKey.serialize()
        )

        let record = try KyberPreKeyRecord(
            id: id,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
            keyPair: keyPair,
            signature: signature
        )

        try storeKyberPreKey(record, id: id, context: NullContext())
        return record
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(data: Data, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKey.service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    private func saveRegistrationId(_ id: UInt32) {
        var value = id
        let data = Data(bytes: &value, count: MemoryLayout<UInt32>.size)
        saveToKeychain(data: data, key: KeychainKey.registrationId)
    }

    private func loadRegistrationId() -> UInt32? {
        guard let data = loadFromKeychain(key: KeychainKey.registrationId),
              data.count == MemoryLayout<UInt32>.size else {
            return nil
        }
        return data.withUnsafeBytes { $0.load(as: UInt32.self) }
    }
}

// MARK: - IdentityKeyStore

extension SignalProtocolStore: IdentityKeyStore {
    func identityKeyPair(context: StoreContext) throws -> IdentityKeyPair {
        return try getIdentityKeyPair()
    }

    func localRegistrationId(context: StoreContext) throws -> UInt32 {
        return getLocalRegistrationId()
    }

    func saveIdentity(_ identity: IdentityKey, for address: ProtocolAddress, context: StoreContext) throws -> IdentityChange {
        let key = KeychainKey.identityPrefix + address.name + "." + String(address.deviceId)

        // Check if identity changed (TOFU - Trust On First Use)
        if let existingData = loadFromKeychain(key: key) {
            let existingKey = try IdentityKey(bytes: existingData)
            let changed = existingKey != identity
            if changed {
                #if DEBUG
                print("[SignalStore] Identity key changed for \(address)")
                #endif
            }
            saveToKeychain(data: Data(identity.serialize()), key: key)
            return changed ? .replacedExisting : .newOrUnchanged
        }

        // First time seeing this identity
        saveToKeychain(data: Data(identity.serialize()), key: key)
        return .newOrUnchanged
    }

    func isTrustedIdentity(_ identity: IdentityKey, for address: ProtocolAddress, direction: Direction, context: StoreContext) throws -> Bool {
        let key = KeychainKey.identityPrefix + address.name + "." + String(address.deviceId)

        guard let storedData = loadFromKeychain(key: key) else {
            // No stored identity - trust on first use
            return true
        }

        let storedKey = try IdentityKey(bytes: storedData)
        return storedKey == identity
    }

    func identity(for address: ProtocolAddress, context: StoreContext) throws -> IdentityKey? {
        let key = KeychainKey.identityPrefix + address.name + "." + String(address.deviceId)
        guard let data = loadFromKeychain(key: key) else { return nil }
        return try IdentityKey(bytes: data)
    }
}

// MARK: - PreKeyStore

extension SignalProtocolStore: PreKeyStore {
    func loadPreKey(id: UInt32, context: StoreContext) throws -> PreKeyRecord {
        let key = KeychainKey.preKeyPrefix + String(id)
        guard let data = loadFromKeychain(key: key) else {
            throw SignalProtocolError.invalidKeyIdentifier("PreKey \(id) not found")
        }
        return try PreKeyRecord(bytes: data)
    }

    func storePreKey(_ record: PreKeyRecord, id: UInt32, context: StoreContext) throws {
        let key = KeychainKey.preKeyPrefix + String(id)
        saveToKeychain(data: Data(record.serialize()), key: key)
    }

    func removePreKey(id: UInt32, context: StoreContext) throws {
        let key = KeychainKey.preKeyPrefix + String(id)
        deleteFromKeychain(key: key)
    }
}

// MARK: - SignedPreKeyStore

extension SignalProtocolStore: SignedPreKeyStore {
    func loadSignedPreKey(id: UInt32, context: StoreContext) throws -> SignedPreKeyRecord {
        let key = KeychainKey.signedPreKeyPrefix + String(id)
        guard let data = loadFromKeychain(key: key) else {
            throw SignalProtocolError.invalidKeyIdentifier("SignedPreKey \(id) not found")
        }
        return try SignedPreKeyRecord(bytes: data)
    }

    func storeSignedPreKey(_ record: SignedPreKeyRecord, id: UInt32, context: StoreContext) throws {
        let key = KeychainKey.signedPreKeyPrefix + String(id)
        saveToKeychain(data: Data(record.serialize()), key: key)
    }
}

// MARK: - KyberPreKeyStore

extension SignalProtocolStore: KyberPreKeyStore {
    func loadKyberPreKey(id: UInt32, context: StoreContext) throws -> KyberPreKeyRecord {
        let key = KeychainKey.kyberPreKeyPrefix + String(id)
        guard let data = loadFromKeychain(key: key) else {
            throw SignalProtocolError.invalidKeyIdentifier("KyberPreKey \(id) not found")
        }
        return try KyberPreKeyRecord(bytes: data)
    }

    func storeKyberPreKey(_ record: KyberPreKeyRecord, id: UInt32, context: StoreContext) throws {
        let key = KeychainKey.kyberPreKeyPrefix + String(id)
        saveToKeychain(data: Data(record.serialize()), key: key)
    }

    func markKyberPreKeyUsed(id: UInt32, signedPreKeyId: UInt32, baseKey: PublicKey, context: StoreContext) throws {
        // Mark as used by updating timestamp in a separate key
        let usageKey = KeychainKey.kyberPreKeyPrefix + "used_" + String(id)
        let timestamp = Date().timeIntervalSince1970
        saveToKeychain(data: withUnsafeBytes(of: timestamp) { Data($0) }, key: usageKey)
    }
}

// MARK: - SessionStore

extension SignalProtocolStore: SessionStore {
    func loadSession(for address: ProtocolAddress, context: StoreContext) throws -> SessionRecord? {
        let key = KeychainKey.sessionPrefix + address.name + "." + String(address.deviceId)
        guard let data = loadFromKeychain(key: key) else { return nil }
        return try SessionRecord(bytes: data)
    }

    func loadExistingSessions(for addresses: [ProtocolAddress], context: StoreContext) throws -> [SessionRecord] {
        var sessions: [SessionRecord] = []
        for address in addresses {
            if let session = try loadSession(for: address, context: context) {
                sessions.append(session)
            }
        }
        return sessions
    }

    func storeSession(_ record: SessionRecord, for address: ProtocolAddress, context: StoreContext) throws {
        let key = KeychainKey.sessionPrefix + address.name + "." + String(address.deviceId)
        saveToKeychain(data: Data(record.serialize()), key: key)
    }

    func hasSession(for address: ProtocolAddress) -> Bool {
        let key = KeychainKey.sessionPrefix + address.name + "." + String(address.deviceId)
        return loadFromKeychain(key: key) != nil
    }

    func deleteSession(for address: ProtocolAddress) {
        let key = KeychainKey.sessionPrefix + address.name + "." + String(address.deviceId)
        deleteFromKeychain(key: key)
    }
}

// MARK: - SenderKeyStore

extension SignalProtocolStore: SenderKeyStore {
    func storeSenderKey(from sender: ProtocolAddress, distributionId: UUID, record: SenderKeyRecord, context: StoreContext) throws {
        let key = KeychainKey.senderKeyPrefix + distributionId.uuidString + "_" + sender.name + "." + String(sender.deviceId)
        saveToKeychain(data: Data(record.serialize()), key: key)
    }

    func loadSenderKey(from sender: ProtocolAddress, distributionId: UUID, context: StoreContext) throws -> SenderKeyRecord? {
        let key = KeychainKey.senderKeyPrefix + distributionId.uuidString + "_" + sender.name + "." + String(sender.deviceId)
        guard let data = loadFromKeychain(key: key) else { return nil }
        return try SenderKeyRecord(bytes: data)
    }
}

// MARK: - Supporting Types

enum SignalProtocolError: LocalizedError {
    case invalidState(String)
    case invalidKeyIdentifier(String)

    var errorDescription: String? {
        switch self {
        case .invalidState(let msg):
            return "Invalid state: \(msg)"
        case .invalidKeyIdentifier(let msg):
            return "Invalid key identifier: \(msg)"
        }
    }
}
