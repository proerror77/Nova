import Foundation

/// C FFI Function Declarations for Crypto Core
@_silgen_name("cryptocore_encrypt")
func cryptocore_encrypt(
    plaintext: UnsafeRawPointer?,
    plaintext_len: UInt,
    recipient_pk: UnsafeRawPointer?,
    recipient_pk_len: UInt,
    sender_sk: UnsafeRawPointer?,
    sender_sk_len: UInt,
    nonce: UnsafeRawPointer?,
    nonce_len: UInt,
    out_len: UnsafeMutablePointer<UInt>?
) -> UnsafeMutableRawPointer?

@_silgen_name("cryptocore_decrypt")
func cryptocore_decrypt(
    ciphertext: UnsafeRawPointer?,
    ciphertext_len: UInt,
    sender_pk: UnsafeRawPointer?,
    sender_pk_len: UInt,
    recipient_sk: UnsafeRawPointer?,
    recipient_sk_len: UInt,
    nonce: UnsafeRawPointer?,
    nonce_len: UInt,
    out_len: UnsafeMutablePointer<UInt>?
) -> UnsafeMutableRawPointer?

@_silgen_name("cryptocore_generate_nonce")
func cryptocore_generate_nonce(
    out_buf: UnsafeMutableRawPointer?,
    out_len: UInt
) -> UInt

/// Crypto Core FFI Wrapper with Input Validation
class CryptoCoreFFI {
    enum CryptoError: Error {
        case nullPointer(String)
        case invalidKeyLength(String)
        case invalidNonceLength(String)
        case invalidPlaintextLength(String)
        case encryptionFailed(String)
        case decryptionFailed(String)
    }

    // Constants
    static let KEY_LENGTH = 32        // 32 bytes = 256 bits
    static let NONCE_LENGTH = 24      // 24 bytes for XSalsa20-Poly1305
    static let MAX_PLAINTEXT_LENGTH = 1_000_000  // 1 MB safety limit

    /// Securely encrypt data
    /// - Parameters:
    ///   - plaintext: Data to encrypt
    ///   - recipientPublicKey: Recipient's public key (32 bytes)
    ///   - senderSecretKey: Sender's secret key (32 bytes)
    ///   - nonce: Nonce for encryption (24 bytes)
    /// - Returns: Encrypted data
    static func encrypt(
        plaintext: Data,
        recipientPublicKey: Data,
        senderSecretKey: Data,
        nonce: Data
    ) throws -> Data {
        // ✅ INPUT VALIDATION

        // 1. Null pointer checks
        if plaintext.isEmpty {
            throw CryptoError.invalidPlaintextLength("Plaintext cannot be empty")
        }

        if recipientPublicKey.isEmpty {
            throw CryptoError.nullPointer("recipientPublicKey")
        }

        if senderSecretKey.isEmpty {
            throw CryptoError.nullPointer("senderSecretKey")
        }

        if nonce.isEmpty {
            throw CryptoError.nullPointer("nonce")
        }

        // 2. Length validation
        if plaintext.count > Self.MAX_PLAINTEXT_LENGTH {
            throw CryptoError.invalidPlaintextLength(
                "Plaintext too large: \(plaintext.count) (max: \(Self.MAX_PLAINTEXT_LENGTH))"
            )
        }

        if recipientPublicKey.count != Self.KEY_LENGTH {
            throw CryptoError.invalidKeyLength(
                "Recipient public key must be \(Self.KEY_LENGTH) bytes, got \(recipientPublicKey.count)"
            )
        }

        if senderSecretKey.count != Self.KEY_LENGTH {
            throw CryptoError.invalidKeyLength(
                "Sender secret key must be \(Self.KEY_LENGTH) bytes, got \(senderSecretKey.count)"
            )
        }

        if nonce.count != Self.NONCE_LENGTH {
            throw CryptoError.invalidNonceLength(
                "Nonce must be \(Self.NONCE_LENGTH) bytes, got \(nonce.count)"
            )
        }

        // 3. Call FFI function with validated inputs
        var outLen: UInt = 0

        let result = plaintext.withUnsafeBytes { plainPtr in
            recipientPublicKey.withUnsafeBytes { rpkPtr in
                senderSecretKey.withUnsafeBytes { sskPtr in
                    nonce.withUnsafeBytes { noncePtr in
                        cryptocore_encrypt(
                            plainPtr.baseAddress,
                            UInt(plaintext.count),
                            rpkPtr.baseAddress,
                            UInt(recipientPublicKey.count),
                            sskPtr.baseAddress,
                            UInt(senderSecretKey.count),
                            noncePtr.baseAddress,
                            UInt(nonce.count),
                            &outLen
                        )
                    }
                }
            }
        }

        guard let result = result else {
            throw CryptoError.encryptionFailed("FFI returned null pointer")
        }

        // 4. Convert result to Data
        let encryptedData = Data(
            bytes: result,
            count: Int(outLen)
        )

        // Free FFI-allocated memory
        free(result)

        return encryptedData
    }

    /// Securely decrypt data
    /// - Parameters:
    ///   - ciphertext: Data to decrypt
    ///   - senderPublicKey: Sender's public key (32 bytes)
    ///   - recipientSecretKey: Recipient's secret key (32 bytes)
    ///   - nonce: Nonce used for encryption (24 bytes)
    /// - Returns: Decrypted plaintext
    static func decrypt(
        ciphertext: Data,
        senderPublicKey: Data,
        recipientSecretKey: Data,
        nonce: Data
    ) throws -> Data {
        // ✅ INPUT VALIDATION

        // 1. Null pointer checks
        if ciphertext.isEmpty {
            throw CryptoError.invalidPlaintextLength("Ciphertext cannot be empty")
        }

        if senderPublicKey.isEmpty {
            throw CryptoError.nullPointer("senderPublicKey")
        }

        if recipientSecretKey.isEmpty {
            throw CryptoError.nullPointer("recipientSecretKey")
        }

        if nonce.isEmpty {
            throw CryptoError.nullPointer("nonce")
        }

        // 2. Length validation
        if senderPublicKey.count != Self.KEY_LENGTH {
            throw CryptoError.invalidKeyLength(
                "Sender public key must be \(Self.KEY_LENGTH) bytes, got \(senderPublicKey.count)"
            )
        }

        if recipientSecretKey.count != Self.KEY_LENGTH {
            throw CryptoError.invalidKeyLength(
                "Recipient secret key must be \(Self.KEY_LENGTH) bytes, got \(recipientSecretKey.count)"
            )
        }

        if nonce.count != Self.NONCE_LENGTH {
            throw CryptoError.invalidNonceLength(
                "Nonce must be \(Self.NONCE_LENGTH) bytes, got \(nonce.count)"
            )
        }

        // 3. Call FFI function with validated inputs
        var outLen: UInt = 0

        let result = ciphertext.withUnsafeBytes { ctPtr in
            senderPublicKey.withUnsafeBytes { spkPtr in
                recipientSecretKey.withUnsafeBytes { rskPtr in
                    nonce.withUnsafeBytes { noncePtr in
                        cryptocore_decrypt(
                            ctPtr.baseAddress,
                            UInt(ciphertext.count),
                            spkPtr.baseAddress,
                            UInt(senderPublicKey.count),
                            rskPtr.baseAddress,
                            UInt(recipientSecretKey.count),
                            noncePtr.baseAddress,
                            UInt(nonce.count),
                            &outLen
                        )
                    }
                }
            }
        }

        guard let result = result else {
            throw CryptoError.decryptionFailed("FFI returned null pointer or invalid authentication tag")
        }

        // 4. Convert result to Data
        let decryptedData = Data(
            bytes: result,
            count: Int(outLen)
        )

        // Free FFI-allocated memory
        free(result)

        return decryptedData
    }

    /// Generate a secure random nonce
    /// - Returns: 24-byte nonce suitable for XSalsa20-Poly1305
    static func generateNonce() throws -> Data {
        var nonceBuffer = [UInt8](repeating: 0, count: Self.NONCE_LENGTH)

        let length = nonceBuffer.withUnsafeMutableBytes { ptr in
            cryptocore_generate_nonce(
                ptr.baseAddress,
                UInt(Self.NONCE_LENGTH)
            )
        }

        guard length == UInt(Self.NONCE_LENGTH) else {
            throw CryptoError.encryptionFailed("Failed to generate nonce")
        }

        return Data(nonceBuffer)
    }
}

// MARK: - Tests

#if DEBUG
import XCTest

class CryptoCoreFFITests: XCTestCase {
    let testMessage = "Hello, World!"
    var recipientPK: Data!
    var senderSK: Data!
    var nonce: Data!

    override func setUp() {
        super.setUp()
        // Generate test keys and nonce
        recipientPK = Data(repeating: 0x01, count: CryptoCoreFFI.KEY_LENGTH)
        senderSK = Data(repeating: 0x02, count: CryptoCoreFFI.KEY_LENGTH)
        nonce = Data(repeating: 0x03, count: CryptoCoreFFI.NONCE_LENGTH)
    }

    func testEncryptWithInvalidNonceLength() {
        let plaintext = testMessage.data(using: .utf8)!
        let invalidNonce = Data(repeating: 0, count: 10) // Wrong size

        XCTAssertThrowsError(
            try CryptoCoreFFI.encrypt(
                plaintext: plaintext,
                recipientPublicKey: recipientPK,
                senderSecretKey: senderSK,
                nonce: invalidNonce
            )
        ) { error in
            guard case .invalidNonceLength = error as? CryptoCoreFFI.CryptoError else {
                XCTFail("Expected invalidNonceLength error")
                return
            }
        }
    }

    func testEncryptWithInvalidKeyLength() {
        let plaintext = testMessage.data(using: .utf8)!
        let invalidKey = Data(repeating: 0, count: 16) // Wrong size

        XCTAssertThrowsError(
            try CryptoCoreFFI.encrypt(
                plaintext: plaintext,
                recipientPublicKey: invalidKey,
                senderSecretKey: senderSK,
                nonce: nonce
            )
        ) { error in
            guard case .invalidKeyLength = error as? CryptoCoreFFI.CryptoError else {
                XCTFail("Expected invalidKeyLength error")
                return
            }
        }
    }

    func testEncryptWithNullData() {
        let emptyData = Data()

        XCTAssertThrowsError(
            try CryptoCoreFFI.encrypt(
                plaintext: emptyData,
                recipientPublicKey: recipientPK,
                senderSecretKey: senderSK,
                nonce: nonce
            )
        ) { error in
            guard case .invalidPlaintextLength = error as? CryptoCoreFFI.CryptoError else {
                XCTFail("Expected invalidPlaintextLength error")
                return
            }
        }
    }

    func testDecryptWithInvalidNonceLength() {
        let ciphertext = Data(repeating: 0, count: 100)
        let invalidNonce = Data(repeating: 0, count: 12) // Wrong size

        XCTAssertThrowsError(
            try CryptoCoreFFI.decrypt(
                ciphertext: ciphertext,
                senderPublicKey: recipientPK,
                recipientSecretKey: senderSK,
                nonce: invalidNonce
            )
        ) { error in
            guard case .invalidNonceLength = error as? CryptoCoreFFI.CryptoError else {
                XCTFail("Expected invalidNonceLength error")
                return
            }
        }
    }

    func testGenerateNonce() throws {
        let nonce = try CryptoCoreFFI.generateNonce()
        XCTAssertEqual(nonce.count, CryptoCoreFFI.NONCE_LENGTH)
        // Ensure nonce is not all zeros
        XCTAssertNotEqual(nonce, Data(repeating: 0, count: CryptoCoreFFI.NONCE_LENGTH))
    }
}
#endif
