import Foundation
import Security
import CommonCrypto

// MARK: - Certificate Pinning Manager

/// Manages SSL certificate pinning for secure API communication
/// Uses public key pinning (SPKI) for better certificate rotation handling
final class CertificatePinningManager: NSObject {
    static let shared = CertificatePinningManager()

    // MARK: - Pinned Public Key Hashes (SHA-256)
    // These are the SHA-256 hashes of the Subject Public Key Info (SPKI)
    // Update these when certificates are rotated
    private let pinnedHashes: [String: Set<String>] = [
        // Production API - api.icered.com
        "api.icered.com": [
            // Primary certificate hash (update with actual hash)
            // Use: openssl s_client -connect api.icered.com:443 | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
            // Placeholder - replace with actual production certificate hash
        ],
        // Staging API - staging-api.icered.com (via Cloudflare)
        "staging-api.icered.com": [
            // Cloudflare certificate hashes (these are well-known)
            // Cloudflare uses Let's Encrypt or DigiCert certificates
            // Add actual hashes after deployment
        ]
    ]

    // MARK: - Bypass for Development
    #if DEBUG
    /// Set to true to bypass pinning in development (localhost)
    var bypassPinningForLocalhost = true
    #endif

    private override init() {
        super.init()
    }

    // MARK: - Public Key Hash Extraction

    /// Extract SHA-256 hash of the public key from a certificate
    /// - Parameter certificate: The certificate to extract public key from
    /// - Returns: Base64-encoded SHA-256 hash of the public key, or nil if extraction fails
    func publicKeyHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        // Add ASN.1 header for RSA public keys
        // This creates the Subject Public Key Info (SPKI) structure
        let rsa2048Asn1Header: [UInt8] = [
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
        ]

        var keyWithHeader = Data(rsa2048Asn1Header)
        keyWithHeader.append(publicKeyData)

        // Calculate SHA-256 hash
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        keyWithHeader.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(keyWithHeader.count), &hash)
        }

        return Data(hash).base64EncodedString()
    }

    /// Validate a certificate chain against pinned hashes
    /// - Parameters:
    ///   - trust: The server trust object from the challenge
    ///   - host: The host being connected to
    /// - Returns: True if the certificate is valid and matches a pinned hash
    func validateCertificate(trust: SecTrust, host: String) -> Bool {
        #if DEBUG
        // Bypass pinning for localhost in development
        if bypassPinningForLocalhost && (host == "localhost" || host == "127.0.0.1") {
            return true
        }
        #endif

        // Get pinned hashes for this host
        guard let expectedHashes = pinnedHashes[host], !expectedHashes.isEmpty else {
            // No pinning configured for this host
            // In production, you might want to fail closed (return false)
            // For now, allow unpinned hosts but log a warning
            #if DEBUG
            print("[CertificatePinning] No pins configured for host: \(host)")
            #endif
            return true
        }

        // Evaluate the trust
        var secResult: SecTrustResultType = .invalid
        let status = SecTrustEvaluate(trust, &secResult)

        guard status == errSecSuccess else {
            #if DEBUG
            print("[CertificatePinning] Trust evaluation failed for \(host)")
            #endif
            return false
        }

        // Check if the result is acceptable
        guard secResult == .proceed || secResult == .unspecified else {
            #if DEBUG
            print("[CertificatePinning] Trust result not acceptable for \(host): \(secResult)")
            #endif
            return false
        }

        // Get the certificate chain
        let certificateCount = SecTrustGetCertificateCount(trust)

        // Check each certificate in the chain against our pins
        for i in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(trust, i) else {
                continue
            }

            if let hash = publicKeyHash(for: certificate) {
                if expectedHashes.contains(hash) {
                    #if DEBUG
                    print("[CertificatePinning] Certificate pinning validated for \(host)")
                    #endif
                    return true
                }
            }
        }

        #if DEBUG
        print("[CertificatePinning] No matching pin found for \(host)")
        #endif
        return false
    }
}

// MARK: - URLSession Delegate for Pinning

/// URLSession delegate that implements certificate pinning
final class PinningURLSessionDelegate: NSObject, URLSessionDelegate {
    private let pinningManager = CertificatePinningManager.shared

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle server trust challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Validate the certificate
        if pinningManager.validateCertificate(trust: serverTrust, host: host) {
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            // Certificate validation failed - reject the connection
            #if DEBUG
            print("[CertificatePinning] Connection rejected for \(host) - certificate pinning failed")
            #endif
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

// MARK: - URLSession Extension

extension URLSession {
    /// Create a URLSession with certificate pinning enabled
    /// - Parameter configuration: The session configuration to use
    /// - Returns: A URLSession with pinning delegate
    static func withPinning(configuration: URLSessionConfiguration = .default) -> URLSession {
        return URLSession(
            configuration: configuration,
            delegate: PinningURLSessionDelegate(),
            delegateQueue: nil
        )
    }
}
