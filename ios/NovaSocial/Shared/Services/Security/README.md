# E2EE Implementation for iOS

End-to-end encryption implementation for Nova Social iOS app using X25519 key agreement and ChaCha20-Poly1305 AEAD.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      E2EEService                            │
│  (High-level API for app integration)                      │
│  - Device initialization                                    │
│  - Session management                                       │
│  - Message encryption/decryption                            │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│                    CryptoCore                               │
│  (Low-level cryptographic primitives)                      │
│  - X25519 ECDH key agreement                               │
│  - ChaCha20-Poly1305 AEAD encryption                       │
│  - Random number generation                                 │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│                   CryptoKit                                 │
│  (Apple's native crypto framework)                         │
│  - Curve25519.KeyAgreement                                 │
│  - ChaChaPoly (ChaCha20-Poly1305)                          │
│  - SecRandomCopyBytes                                      │
└─────────────────────────────────────────────────────────────┘
```

## Files

### Data Models
- **E2EEModels.swift** - Data structures for E2EE
  - `DeviceKeys` - Device identity keys
  - `DeviceKeyInfo` - Other users' device keys
  - `ClaimedKey` - One-time prekeys
  - `EncryptedMessage` - Encrypted message format
  - `SessionInfo` - Session state
  - API request/response models

### Services
- **CryptoCore.swift** - Low-level crypto operations
  - `generateKeypair()` - X25519 keypair generation
  - `deriveSharedSecret()` - ECDH key agreement
  - `encrypt()` - ChaCha20-Poly1305 encryption
  - `decrypt()` - ChaCha20-Poly1305 decryption

- **E2EEService.swift** - High-level E2EE service
  - `initializeDevice()` - Setup E2EE for device
  - `encryptMessage()` - Encrypt outgoing messages
  - `decryptMessage()` - Decrypt incoming messages
  - `establishSession()` - Create session with peer
  - `queryDeviceKeys()` - Discover peer devices

- **KeychainService.swift** - Secure key storage
  - Stores device identity (private keys)
  - Uses iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`

## Usage

### 1. Initialize E2EE

```swift
let e2eeService = E2EEService()

// Initialize device (first time setup)
try await e2eeService.initializeDevice()
```

This will:
- Generate X25519 keypair
- Register device with backend
- Upload initial batch of one-time keys (50 keys)
- Store private key securely in Keychain

### 2. Encrypt a Message

```swift
let conversationId = UUID()
let plaintext = "Hello, world!"

let encryptedMessage = try await e2eeService.encryptMessage(
    for: conversationId,
    plaintext: plaintext
)

// encryptedMessage contains:
// - ciphertext: String (base64)
// - nonce: String (base64)
// - deviceId: String
```

### 3. Decrypt a Message

```swift
let decrypted = try await e2eeService.decryptMessage(
    encryptedMessage,
    conversationId: conversationId
)

print(decrypted)  // "Hello, world!"
```

### 4. Establish Session with Peer

```swift
// Query peer's device keys
let userId = UUID(uuidString: "...")!
let deviceKeys = try await e2eeService.queryDeviceKeys(for: [userId])

// Establish session with specific device
let deviceId = deviceKeys[userId.uuidString]?.first?.deviceId
try await e2eeService.establishSession(with: userId, deviceId: deviceId!)
```

## Cryptographic Details

### Key Agreement: X25519 ECDH

```
Alice                                  Bob
─────                                  ───
Generate keypair:                      Generate keypair:
  secretKey_A (32 bytes)                secretKey_B (32 bytes)
  publicKey_A (32 bytes)                publicKey_B (32 bytes)

Share publicKey_A ────────────────────>
                  <──────────────────── Share publicKey_B

Compute:                               Compute:
  sharedSecret = ECDH(secretKey_A,      sharedSecret = ECDH(secretKey_B,
                      publicKey_B)                          publicKey_A)

Both derive same 32-byte shared secret
```

### Encryption: ChaCha20-Poly1305 AEAD

```
Input:
  key (32 bytes from ECDH)
  plaintext (variable length)
  nonce (12 bytes random)

Output:
  ciphertext (same length as plaintext)
  tag (16 bytes authentication tag)

Final message:
  Base64(ciphertext || tag) + Base64(nonce)
```

### Message Format

Encrypted messages are sent as JSON:

```json
{
  "ciphertext": "base64_encoded_ciphertext_with_tag",
  "nonce": "base64_encoded_12_byte_nonce",
  "device_id": "iPhone-ABC123-iOS17"
}
```

## Backend API Integration

### Device Registration

```
POST /api/v1/e2ee/devices
Headers:
  Authorization: Bearer {JWT}
  X-Device-ID: {device_id}
Body:
  {
    "device_id": "iPhone-ABC123-iOS17",
    "device_name": "Alice's iPhone"
  }
Response:
  {
    "device_id": "...",
    "identity_key": "base64_x25519_public_key",
    "signing_key": "base64_ed25519_signing_key"
  }
```

### Upload One-Time Keys

```
POST /api/v1/e2ee/keys/upload
Headers:
  Authorization: Bearer {JWT}
  X-Device-ID: {device_id}
Body:
  {
    "count": 50
  }
Response:
  {
    "uploaded_count": 50,
    "total_count": 50
  }
```

### Claim One-Time Keys

```
POST /api/v1/e2ee/keys/claim
Headers:
  Authorization: Bearer {JWT}
  X-Device-ID: {device_id}
Body:
  {
    "one_time_keys": {
      "user_id_1": ["device_id_1", "device_id_2"],
      "user_id_2": ["device_id_3"]
    }
  }
Response:
  {
    "one_time_keys": {
      "user_id_1": {
        "device_id_1": {
          "device_id": "...",
          "key_id": "...",
          "key": "base64_one_time_key",
          "identity_key": "base64_x25519_public_key",
          "signing_key": "..."
        }
      }
    },
    "failures": []
  }
```

### Query Device Keys

```
POST /api/v1/e2ee/keys/query
Headers: Authorization: Bearer {JWT}
Body:
  {
    "user_ids": ["user_id_1", "user_id_2"]
  }
Response:
  {
    "device_keys": {
      "user_id_1": [
        {
          "device_id": "...",
          "device_name": "Alice's iPhone",
          "identity_key": "base64_x25519_public_key",
          "signing_key": "...",
          "verified": false
        }
      ]
    }
  }
```

## Security Considerations

### ✅ Implemented

1. **X25519 ECDH** - Modern elliptic curve Diffie-Hellman
2. **ChaCha20-Poly1305** - Fast authenticated encryption
3. **Random Nonces** - SecRandomCopyBytes for cryptographically secure randomness
4. **Keychain Storage** - Private keys stored with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
5. **Forward Secrecy** - One-time prekeys enable forward secrecy

### ⚠️ TODO

1. **Per-Device Sessions** - Currently using simplified conversation-based keys
2. **Double Ratchet** - Should implement full Signal Protocol
3. **Cross-Signing** - Device verification and trust chains
4. **Key Rotation** - Periodic key refresh
5. **Backup Keys** - Secure key backup for device recovery
6. **Group Encryption** - Megolm-style group encryption (Sender Keys)

### 🔴 Known Limitations

1. **Temporary Key Derivation** - Using SHA256(secret_key || conversation_id) instead of proper session keys
2. **No Device Verification** - Users can't verify device fingerprints yet
3. **No Key Refresh** - Keys never expire or rotate
4. **Single Device** - Multi-device sync not implemented
5. **No Group E2EE** - Only 1:1 encryption supported

## Migration Path

### Phase 1: Basic E2EE (Current)
- ✅ X25519 + ChaCha20-Poly1305
- ✅ Device registration
- ✅ One-time key management
- ⚠️ Simplified key derivation

### Phase 2: Proper Sessions
- [ ] Implement Double Ratchet (Signal Protocol)
- [ ] Per-device session state
- [ ] Message ordering and gap detection

### Phase 3: Device Trust
- [ ] Cross-signing
- [ ] Device fingerprint verification
- [ ] Trust on first use (TOFU)

### Phase 4: Multi-Device
- [ ] Device-to-device sync
- [ ] Shared message history
- [ ] Cross-device session management

### Phase 5: Group E2EE
- [ ] Sender Keys (Megolm)
- [ ] Group session rotation
- [ ] Member add/remove handling

## Testing

### Unit Tests (TODO)

```swift
func testKeypairGeneration() {
    let (publicKey, secretKey) = try crypto.generateKeypair()
    XCTAssertEqual(publicKey.count, 32)
    XCTAssertEqual(secretKey.count, 32)
}

func testEncryptDecrypt() {
    let key = try crypto.randomBytes(count: 32)
    let plaintext = "Hello, world!".data(using: .utf8)!

    let (ciphertext, nonce) = try crypto.encrypt(key: key, plaintext: plaintext)
    let decrypted = try crypto.decrypt(key: key, ciphertext: ciphertext, nonce: nonce)

    XCTAssertEqual(decrypted, plaintext)
}

func testECDH() {
    let (publicKeyA, secretKeyA) = try crypto.generateKeypair()
    let (publicKeyB, secretKeyB) = try crypto.generateKeypair()

    let sharedSecretA = try crypto.deriveSharedSecret(secretKey: secretKeyA, peerPublicKey: publicKeyB)
    let sharedSecretB = try crypto.deriveSharedSecret(secretKey: secretKeyB, peerPublicKey: publicKeyA)

    XCTAssertEqual(sharedSecretA, sharedSecretB)
}
```

### Integration Tests (TODO)

```swift
func testDeviceInitialization() async throws {
    let service = E2EEService()
    try await service.initializeDevice()

    // Verify device registered with backend
    // Verify keys uploaded
    // Verify identity stored in keychain
}

func testMessageEncryptionDecryption() async throws {
    let service = E2EEService()
    let conversationId = UUID()
    let message = "Test message"

    let encrypted = try await service.encryptMessage(for: conversationId, plaintext: message)
    let decrypted = try await service.decryptMessage(encrypted, conversationId: conversationId)

    XCTAssertEqual(decrypted, message)
}
```

## References

- **Signal Protocol**: https://signal.org/docs/
- **Matrix E2EE**: https://spec.matrix.org/latest/client-server-api/#end-to-end-encryption
- **X25519**: https://cr.yp.to/ecdh.html
- **ChaCha20-Poly1305**: RFC 8439
- **Apple CryptoKit**: https://developer.apple.com/documentation/cryptokit

## License

Copyright (c) 2025 Nova Social. All rights reserved.
