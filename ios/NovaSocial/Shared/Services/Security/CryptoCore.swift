import Foundation
import CryptoKit

// MARK: - CryptoCore
//
// Low-level cryptographic operations for E2EE
// Uses Apple's CryptoKit (ChaCha20-Poly1305 + X25519) as fallback
// TODO: Replace with C FFI to backend/libs/crypto-core when xcframework is available

final class CryptoCore {
    static let shared = CryptoCore()

    private init() {
        #if DEBUG
        print("[CryptoCore] Initialized with CryptoKit fallback")
        #endif
    }

    // MARK: - Key Generation

    /// Generate X25519 keypair for device identity
    /// Returns (publicKey: 32 bytes, secretKey: 32 bytes)
    func generateKeypair() throws -> (publicKey: Data, secretKey: Data) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey

        // Extract raw key bytes
        let secretKeyData = privateKey.rawRepresentation
        let publicKeyData = publicKey.rawRepresentation

        #if DEBUG
        print("[CryptoCore] Generated X25519 keypair (public: \(publicKeyData.count) bytes, secret: \(secretKeyData.count) bytes)")
        #endif

        return (publicKey: publicKeyData, secretKey: secretKeyData)
    }

    // MARK: - Key Agreement

    /// Derive shared secret using X25519 ECDH
    /// - Parameters:
    ///   - secretKey: Our X25519 secret key (32 bytes)
    ///   - peerPublicKey: Peer's X25519 public key (32 bytes)
    /// - Returns: Shared secret (32 bytes)
    func deriveSharedSecret(secretKey: Data, peerPublicKey: Data) throws -> Data {
        guard secretKey.count == 32 else {
            throw E2EEError.invalidKey("Secret key must be 32 bytes, got \(secretKey.count)")
        }
        guard peerPublicKey.count == 32 else {
            throw E2EEError.invalidKey("Peer public key must be 32 bytes, got \(peerPublicKey.count)")
        }

        do {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secretKey)
            let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)

            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)

            // Extract raw bytes (32 bytes)
            let sharedSecretData = sharedSecret.withUnsafeBytes { Data($0) }

            #if DEBUG
            print("[CryptoCore] Derived shared secret (\(sharedSecretData.count) bytes)")
            #endif

            return sharedSecretData
        } catch {
            throw E2EEError.invalidKey("Key agreement failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Symmetric Encryption

    /// Encrypt plaintext using ChaCha20-Poly1305
    /// - Parameters:
    ///   - key: Symmetric key (32 bytes from ECDH)
    ///   - plaintext: Data to encrypt
    /// - Returns: (ciphertext, nonce) where nonce is 12 bytes
    func encrypt(key: Data, plaintext: Data) throws -> (ciphertext: Data, nonce: Data) {
        guard key.count == 32 else {
            throw E2EEError.invalidKey("Encryption key must be 32 bytes, got \(key.count)")
        }

        do {
            // Generate random 12-byte nonce
            var nonceBytes = [UInt8](repeating: 0, count: 12)
            let status = SecRandomCopyBytes(kSecRandomDefault, nonceBytes.count, &nonceBytes)
            guard status == errSecSuccess else {
                throw E2EEError.encryptionFailed("Failed to generate nonce")
            }
            let nonce = try ChaChaPoly.Nonce(data: Data(nonceBytes))

            // Create symmetric key
            let symmetricKey = SymmetricKey(data: key)

            // Encrypt
            let sealedBox = try ChaChaPoly.seal(plaintext, using: symmetricKey, nonce: nonce)

            #if DEBUG
            print("[CryptoCore] Encrypted \(plaintext.count) bytes -> \(sealedBox.ciphertext.count) bytes (nonce: 12 bytes)")
            #endif

            return (ciphertext: sealedBox.ciphertext + sealedBox.tag, nonce: Data(nonceBytes))
        } catch {
            throw E2EEError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Decrypt ciphertext using ChaCha20-Poly1305
    /// - Parameters:
    ///   - key: Symmetric key (32 bytes from ECDH)
    ///   - ciphertext: Encrypted data (includes 16-byte tag at end)
    ///   - nonce: 12-byte nonce used for encryption
    /// - Returns: Decrypted plaintext
    func decrypt(key: Data, ciphertext: Data, nonce: Data) throws -> Data {
        guard key.count == 32 else {
            throw E2EEError.invalidKey("Decryption key must be 32 bytes, got \(key.count)")
        }
        guard nonce.count == 12 else {
            throw E2EEError.invalidKey("Nonce must be 12 bytes, got \(nonce.count)")
        }
        guard ciphertext.count >= 16 else {
            throw E2EEError.decryptionFailed("Ciphertext too short (must include 16-byte tag)")
        }

        do {
            // Create symmetric key
            let symmetricKey = SymmetricKey(data: key)

            // Split ciphertext and tag (tag is last 16 bytes)
            let tagStart = ciphertext.count - 16
            let actualCiphertext = ciphertext[..<tagStart]
            let tag = ciphertext[tagStart...]

            // Create nonce
            let chaChaNonce = try ChaChaPoly.Nonce(data: nonce)

            // Create sealed box
            let sealedBox = try ChaChaPoly.SealedBox(nonce: chaChaNonce, ciphertext: actualCiphertext, tag: tag)

            // Decrypt
            let plaintext = try ChaChaPoly.open(sealedBox, using: symmetricKey)

            #if DEBUG
            print("[CryptoCore] Decrypted \(ciphertext.count) bytes -> \(plaintext.count) bytes")
            #endif

            return plaintext
        } catch {
            throw E2EEError.decryptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Helper Functions

    /// Generate random bytes (for one-time prekeys, etc.)
    func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw E2EEError.encryptionFailed("Failed to generate random bytes")
        }
        return Data(bytes)
    }
}

// MARK: - Base64 Helpers

extension Data {
    /// Convert to base64 string (URL-safe encoding)
    func toBase64() -> String {
        return self.base64EncodedString()
    }

    /// Create from base64 string
    init?(base64: String) {
        guard let data = Data(base64Encoded: base64) else {
            return nil
        }
        self = data
    }
}
