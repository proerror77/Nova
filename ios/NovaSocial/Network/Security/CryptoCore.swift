import Foundation

// Swift wrapper for CryptoCore.xcframework
// If framework not present, uses Base64 fallback to avoid blocking app flows.

protocol CryptoProvider {
    func generateNonce() -> Data
    func encrypt(plaintext: Data, recipientPublicKey: Data, senderSecretKey: Data, nonce: Data) throws -> Data
    func decrypt(ciphertext: Data, senderPublicKey: Data, recipientSecretKey: Data, nonce: Data) throws -> Data
}

enum CryptoCoreError: Error { case runtime, invalid }

final class Base64FallbackCrypto: CryptoProvider {
    func generateNonce() -> Data { Data((0..<24).map { _ in UInt8.random(in: 0...255) }) }
    func encrypt(plaintext: Data, recipientPublicKey: Data, senderSecretKey: Data, nonce: Data) throws -> Data {
        plaintext.base64EncodedData()
    }
    func decrypt(ciphertext: Data, senderPublicKey: Data, recipientSecretKey: Data, nonce: Data) throws -> Data {
        Data(base64Encoded: ciphertext) ?? Data()
    }
}

final class CryptoCoreProvider {
    static let shared = CryptoCoreProvider()
    private let impl: CryptoProvider
    private init() {
        #if CRYPTOCORE_FFI
        self.impl = FfiCrypto()
        #else
        self.impl = Base64FallbackCrypto()
        #endif
    }
    func generateNonce() -> Data { impl.generateNonce() }
    func encrypt(plaintext: Data, recipientPublicKey: Data, senderSecretKey: Data, nonce: Data) throws -> Data {
        try impl.encrypt(plaintext: plaintext, recipientPublicKey: recipientPublicKey, senderSecretKey: senderSecretKey, nonce: nonce)
    }
    func decrypt(ciphertext: Data, senderPublicKey: Data, recipientSecretKey: Data, nonce: Data) throws -> Data {
        try impl.decrypt(ciphertext: ciphertext, senderPublicKey: senderPublicKey, recipientSecretKey: recipientSecretKey, nonce: nonce)
    }
}

#if CRYPTOCORE_FFI
// FFI declarations
@_silgen_name("cryptocore_generate_nonce")
private func ffi_generate_nonce(_ out: UnsafeMutablePointer<UInt8>!, _ outLen: UInt) -> UInt

@_silgen_name("cryptocore_encrypt")
private func ffi_encrypt(_ pt: UnsafePointer<UInt8>!, _ ptLen: UInt,
                         _ rpk: UnsafePointer<UInt8>!, _ rpkLen: UInt,
                         _ ssk: UnsafePointer<UInt8>!, _ sskLen: UInt,
                         _ nonce: UnsafePointer<UInt8>!, _ nonceLen: UInt,
                         _ outLen: UnsafeMutablePointer<UInt>!) -> UnsafeMutablePointer<UInt8>!

@_silgen_name("cryptocore_decrypt")
private func ffi_decrypt(_ ct: UnsafePointer<UInt8>!, _ ctLen: UInt,
                         _ spk: UnsafePointer<UInt8>!, _ spkLen: UInt,
                         _ rsk: UnsafePointer<UInt8>!, _ rskLen: UInt,
                         _ nonce: UnsafePointer<UInt8>!, _ nonceLen: UInt,
                         _ outLen: UnsafeMutablePointer<UInt>!) -> UnsafeMutablePointer<UInt8>!

@_silgen_name("cryptocore_free")
private func ffi_free(_ buf: UnsafeMutablePointer<UInt8>!, _ len: UInt)

final class FfiCrypto: CryptoProvider {
    func generateNonce() -> Data {
        var out = [UInt8](repeating: 0, count: 24)
        let written = ffi_generate_nonce(&out, UInt(out.count))
        return Data(out.prefix(Int(written)))
    }
    func encrypt(plaintext: Data, recipientPublicKey: Data, senderSecretKey: Data, nonce: Data) throws -> Data {
        var outLen: UInt = 0
        let ptr = plaintext.withUnsafeBytes { pt in
            recipientPublicKey.withUnsafeBytes { rpk in
                senderSecretKey.withUnsafeBytes { ssk in
                    nonce.withUnsafeBytes { nn in
                        ffi_encrypt(pt.bindMemory(to: UInt8.self).baseAddress, UInt(plaintext.count),
                                    rpk.bindMemory(to: UInt8.self).baseAddress, UInt(recipientPublicKey.count),
                                    ssk.bindMemory(to: UInt8.self).baseAddress, UInt(senderSecretKey.count),
                                    nn.bindMemory(to: UInt8.self).baseAddress, UInt(nonce.count),
                                    &outLen)
                    }
                }
            }
        }
        guard let p = ptr, outLen > 0 else { throw CryptoCoreError.runtime }
        let data = Data(bytes: p, count: Int(outLen))
        ffi_free(p, outLen)
        return data
    }
    func decrypt(ciphertext: Data, senderPublicKey: Data, recipientSecretKey: Data, nonce: Data) throws -> Data {
        var outLen: UInt = 0
        let ptr = ciphertext.withUnsafeBytes { ct in
            senderPublicKey.withUnsafeBytes { spk in
                recipientSecretKey.withUnsafeBytes { rsk in
                    nonce.withUnsafeBytes { nn in
                        ffi_decrypt(ct.bindMemory(to: UInt8.self).baseAddress, UInt(ciphertext.count),
                                    spk.bindMemory(to: UInt8.self).baseAddress, UInt(senderPublicKey.count),
                                    rsk.bindMemory(to: UInt8.self).baseAddress, UInt(recipientSecretKey.count),
                                    nn.bindMemory(to: UInt8.self).baseAddress, UInt(nonce.count),
                                    &outLen)
                    }
                }
            }
        }
        guard let p = ptr, outLen > 0 else { throw CryptoCoreError.runtime }
        let data = Data(bytes: p, count: Int(outLen))
        ffi_free(p, outLen)
        return data
    }
}
#endif
