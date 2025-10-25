# LocalStorage Encryption

Secure client-side encryption for sensitive data stored in localStorage using Web Crypto API.

## Overview

This module provides AES-GCM encryption for localStorage, protecting sensitive data from:
- XSS attacks accessing localStorage
- Browser extensions reading plaintext data
- Forensic analysis of browser storage
- Tampering detection via authenticated encryption

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│  (OfflineQueue, other services using encrypted storage)     │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│               StorageEncryption (singleton)                  │
│  - AES-GCM encryption/decryption                            │
│  - Key management in memory                                 │
│  - Base64 encoding for storage                              │
└───────────────────────────┬─────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                   Web Crypto API                             │
│  - crypto.subtle.encrypt()                                   │
│  - crypto.subtle.decrypt()                                   │
│  - crypto.subtle.importKey()                                 │
└─────────────────────────────────────────────────────────────┘
```

## Usage

### 1. Initialize encryption on login

```typescript
import { storageEncryption } from './services/encryption/localStorage';

// After successful login
async function onLoginSuccess(userId: string, sessionToken: string) {
  // Derive encryption key from session token or user credentials
  const keyMaterial = await deriveKeyFromSession(sessionToken, userId);

  await storageEncryption.initialize(keyMaterial);

  // Or generate random key for this session
  // await storageEncryption.generateKey();
}
```

### 2. Destroy encryption on logout

```typescript
async function onLogout() {
  // Clear encryption key from memory
  storageEncryption.destroy();

  // Clear localStorage
  localStorage.clear();
}
```

### 3. Use encrypted storage

```typescript
import { OfflineQueue } from './services/offlineQueue/Queue';

const queue = new OfflineQueue();

// Enqueue message (automatically encrypted)
await queue.enqueue({
  conversationId: 'conv-123',
  userId: 'user-456',
  plaintext: 'Secret message',
  idempotencyKey: 'unique-key'
});

// Drain messages (automatically decrypted)
const messages = await queue.drain();
```

## Security Properties

### AES-GCM Encryption

- **Algorithm**: AES-256-GCM (Galois/Counter Mode)
- **Key size**: 256 bits (32 bytes)
- **IV size**: 96 bits (12 bytes, randomly generated per encryption)
- **Authentication**: Built-in AEAD (Authenticated Encryption with Associated Data)

### Benefits

1. **Confidentiality**: Ciphertext is indistinguishable from random data
2. **Integrity**: Tampering detected automatically (decryption fails)
3. **Authenticity**: Ensures data was encrypted with the correct key
4. **Random IV**: Same plaintext produces different ciphertext each time

### Key Management

- **Storage**: Key lives in JavaScript memory only (never persisted)
- **Lifecycle**: Generated/imported on login, destroyed on logout
- **Scope**: Per-session key (doesn't survive browser restart)
- **Derivation**: Can be derived from user credentials or session token

## Implementation Details

### Encrypted Data Format

```typescript
interface EncryptedData {
  ciphertext: string; // Base64-encoded encrypted data
  iv: string;         // Base64-encoded initialization vector (12 bytes)
}
```

Stored in localStorage as JSON:
```json
{
  "ciphertext": "R3J5cHRvZ3JhcGh5IGlzIGhhcmQh...",
  "iv": "cmFuZG9tMTJieXRlcw=="
}
```

### Encryption Process

1. Serialize data to JSON
2. Encode JSON string to UTF-8 bytes
3. Generate random 12-byte IV
4. Encrypt with AES-GCM using key and IV
5. Encode ciphertext and IV to base64
6. Store as JSON in localStorage

### Decryption Process

1. Load JSON from localStorage
2. Decode base64 ciphertext and IV
3. Decrypt with AES-GCM using key and IV
4. Decode UTF-8 bytes to JSON string
5. Parse JSON to JavaScript object
6. **If any step fails**: Discard data (don't return corrupted/tampered data)

## Failure Modes

### Graceful Degradation

```typescript
// If encryption not initialized
await queue.enqueue(msg); // ⚠️ Memory-only mode (not persisted)

// If localStorage corrupted
await queue.initialize(); // ✅ Discards corrupted data, starts fresh

// If decryption fails (wrong key or tampering)
await queue.drain(); // ✅ Returns empty array, removes corrupted data
```

### Error Handling Philosophy

**"Fail hard on security, fail soft on availability"**

- **Encryption/decryption failures**: Throw errors (detect tampering)
- **Corrupted storage**: Discard and continue (don't crash app)
- **Missing key**: Memory-only mode (degrade gracefully)

## Testing

```bash
# Run encryption tests
npm test src/services/encryption

# Run offline queue tests
npm test src/services/offlineQueue
```

### Test Coverage

- ✅ Encryption/decryption round-trip
- ✅ Tamper detection (modified ciphertext)
- ✅ Wrong key detection
- ✅ Corrupted data handling
- ✅ Unicode support
- ✅ Large data (1MB+)
- ✅ Persistence across sessions
- ✅ Memory-only fallback mode

## Performance

### Benchmarks (approximate)

- **Encrypt 1KB**: ~1ms
- **Decrypt 1KB**: ~1ms
- **Encrypt 1MB**: ~10ms
- **Decrypt 1MB**: ~10ms

### Optimization Tips

1. **Batch operations**: Encrypt entire queue, not individual messages
2. **Lazy initialization**: Don't decrypt until needed
3. **Memory cache**: Keep decrypted data in memory during session

## Browser Compatibility

Web Crypto API is supported in all modern browsers:

- ✅ Chrome 37+
- ✅ Firefox 34+
- ✅ Safari 11+
- ✅ Edge 79+

**Not supported**: Internet Explorer (EOL)

## Best Practices

### DO

✅ Initialize encryption immediately after login
✅ Destroy key on logout
✅ Use random IV for each encryption
✅ Validate decryption success before using data
✅ Clear localStorage on logout

### DON'T

❌ Store encryption key in localStorage
❌ Reuse IV across encryptions
❌ Use encryption as authentication mechanism
❌ Trust decrypted data without validation
❌ Log plaintext in production

## Future Enhancements

1. **Key derivation**: PBKDF2 from user password
2. **Key rotation**: Periodic re-encryption with new keys
3. **Metadata protection**: Encrypt message counts, timestamps
4. **Subresource Integrity**: Verify encryption module hasn't been tampered
5. **Web Worker**: Offload encryption to background thread

## Related Modules

- `services/offlineQueue/Queue.ts` - Encrypted message queue
- `services/encryption/client.ts` - E2E encryption (separate concern)

## References

- [Web Crypto API Spec](https://www.w3.org/TR/WebCryptoAPI/)
- [AES-GCM NIST SP 800-38D](https://csrc.nist.gov/publications/detail/sp/800-38d/final)
- [OWASP: Cryptographic Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html)
