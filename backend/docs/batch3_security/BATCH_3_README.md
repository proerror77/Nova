# Batch 3: Security Enhancement Migrations

**Status**: ✅ Ready for Review
**Created**: 2025-11-12
**Migrations**: 118, 119, 122

---

## Quick Summary

This batch adds **OAuth token encryption** and **end-to-end encryption (E2EE)** infrastructure to the Nova platform. The migrations enable:

1. **OAuth token refresh** by switching from hashed to encrypted token storage
2. **Message encryption versioning** to support both plaintext and E2EE messages
3. **Device key management** for ECDH key exchange and E2EE audit trails

**CRITICAL**: These migrations require **AWS KMS integration** and **cryptography libraries** to be implemented in application code **BEFORE** deployment. The migrations only create the database schema - they don't handle encryption/decryption.

---

## Files in This Batch

| File | Purpose | Size |
|------|---------|------|
| `118_oauth_encrypted_tokens.sql` | OAuth token encryption schema | 5.4 KB |
| `119_add_message_encryption.sql` | Message encryption validation | 3.7 KB |
| `122_create_device_keys_and_key_exchanges.sql` | E2EE device key tables | 5.5 KB |
| `BATCH_3_MIGRATION_REPORT.md` | Detailed technical analysis | 27 KB |
| `BATCH_3_EXECUTION_CHECKLIST.md` | Step-by-step deployment guide | 20 KB |
| `BATCH_3_VERIFICATION.sql` | Post-deployment verification script | 5 KB |
| `BATCH_3_README.md` | This file | 3 KB |

---

## Migration Details

### 118: OAuth Encrypted Tokens

**Creates**: `oauth_connections` table
**Adds**: Encrypted token storage columns

**Key Features**:
- AES-256-GCM encryption for OAuth access/refresh tokens
- Backward compatibility with hashed tokens (gradual migration)
- Token refresh monitoring (attempt tracking, error logging)
- Automatic token expiry detection

**Dependencies**:
- `users` table (created in migration 001)

**Application Changes Required**:
- AWS KMS integration for master key
- AES-256-GCM encryption/decryption implementation
- OAuth token refresh background job

---

### 119: Message Encryption Validation

**Modifies**: `messages` table (validation only, no schema changes)
**Adds**: Constraints, indexes, helper functions

**Key Features**:
- Validates encryption columns already exist (from migrations 104, 113)
- Adds CHECK constraint: `encryption_version IN (1, 2)`
- Adds index on `encryption_version` for efficient filtering
- Helper function for encryption statistics

**Dependencies**:
- `messages` table with `encryption_version`, `content_encrypted`, `content_nonce` columns

**Application Changes Required**:
- E2EE message encryption/decryption (ChaCha20-Poly1305)
- HKDF-SHA256 for key derivation from shared secret

---

### 122: Device Keys and Key Exchanges

**Creates**: `device_keys` and `key_exchanges` tables

**Key Features**:
- X25519 public/private key pair storage per device
- Private keys encrypted at rest with master key
- ECDH key exchange audit trail (shared secret hash only)
- Supports multi-device E2EE

**Dependencies**:
- `users` table (created in migration 001)
- `conversations` table (created in migration 018)

**Application Changes Required**:
- X25519 key pair generation on client devices
- ECDH shared secret computation
- ChaCha20-Poly1305 message encryption with derived keys

---

## Deployment Workflow

### Pre-Deployment (BLOCKERS)

**MUST IMPLEMENT BEFORE DEPLOYMENT**:

1. **AWS KMS Integration**
   - Create master encryption key in AWS KMS
   - Configure IAM roles for app servers
   - Implement encrypt/decrypt functions using KMS key

2. **Cryptography Libraries**
   - Add `aes-gcm` crate (AES-256-GCM for OAuth tokens)
   - Add `x25519-dalek` crate (ECDH for device keys)
   - Add `chacha20poly1305` crate (E2EE for messages)
   - Add `hkdf` crate (key derivation)

3. **Background Jobs**
   - OAuth token refresh job (checks expiring tokens, refreshes using encrypted refresh_token)

4. **API Endpoints**
   - Device key registration (POST /api/v1/devices/keys)
   - Device key lookup (GET /api/v1/users/:user_id/devices/:device_id/keys)
   - Key exchange initiation (POST /api/v1/conversations/:id/key-exchange)

### Deployment Steps

1. **Read the execution checklist**: `BATCH_3_EXECUTION_CHECKLIST.md`
2. **Test on staging**: Apply migrations to staging environment
3. **Run verification**: Execute `BATCH_3_VERIFICATION.sql` on staging
4. **Backup production**: Full database backup before applying
5. **Apply migrations**: Run 118 → 119 → 122 in order
6. **Verify**: Run `BATCH_3_VERIFICATION.sql` on production
7. **Smoke test**: Test OAuth login, device registration, E2EE messaging

**Estimated Time**: 60 minutes (including backup and verification)

### Rollback

If issues occur, rollback in reverse order: **122 → 119 → 118**

```sql
-- Rollback 122
DROP TABLE IF EXISTS key_exchanges CASCADE;
DROP TABLE IF EXISTS device_keys CASCADE;
DROP FUNCTION IF EXISTS get_device_key_stats();
DROP FUNCTION IF EXISTS update_device_keys_updated_at();

-- Rollback 119
DROP INDEX IF EXISTS idx_messages_encryption_version;
DROP FUNCTION IF EXISTS get_message_encryption_stats();
ALTER TABLE messages DROP CONSTRAINT IF EXISTS chk_messages_encryption_version_valid;

-- Rollback 118
DROP TABLE IF EXISTS oauth_connections CASCADE;
DROP FUNCTION IF EXISTS count_old_oauth_tokens();
DROP FUNCTION IF EXISTS update_oauth_connections_updated_at();
```

**OR** restore from backup:
```bash
pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME -c backup_pre_batch3_*.dump
```

---

## Security Considerations

### Cryptography Algorithms Used

| Purpose | Algorithm | Key Size | Notes |
|---------|-----------|----------|-------|
| OAuth token encryption | AES-256-GCM | 256-bit | Authenticated encryption, prevents tampering |
| ECDH key exchange | X25519 | 256-bit | Modern elliptic curve, fast, secure |
| Message encryption | ChaCha20-Poly1305 | 256-bit | Recommended for E2EE, mobile-friendly |
| Shared secret hashing | HMAC-SHA256 | 256-bit | Audit trail only, NOT for encryption |
| Key derivation | HKDF-SHA256 | 256-bit | Derives message keys from shared secret |

### Threat Model

**What these migrations protect against**:
- ✅ OAuth token theft from database dump (tokens encrypted at rest)
- ✅ Message interception (E2EE prevents server from reading content)
- ✅ Unauthorized device access (device keys required for decryption)
- ✅ Token replay attacks (AES-GCM authenticated encryption)

**What these migrations DON'T protect against**:
- ❌ Compromised client device (attacker has plaintext access)
- ❌ Man-in-the-middle (need TLS for transport security)
- ❌ Compromised master key (entire system depends on KMS security)
- ❌ Quantum computer attacks (X25519 not post-quantum secure)

### Key Management Risks

**CRITICAL**: Master key security is paramount. If master key is compromised:
- All OAuth tokens can be decrypted (revoke all, force re-authentication)
- All device private keys can be decrypted (force re-registration)
- Message content remains safe (encrypted with per-conversation keys)

**Mitigation**:
- Use AWS KMS with strict IAM policies
- Enable KMS key rotation (automatic yearly rotation)
- Monitor KMS access logs (CloudTrail)
- Implement key rotation policy (replace master key if compromised)

---

## Performance Impact

### Expected Impact

**Migration execution** (one-time):
- 118: ~10 minutes (creates table + indexes)
- 119: ~5 minutes (adds constraint + index on existing table)
- 122: ~10 minutes (creates 2 tables + indexes)

**Runtime performance** (ongoing):
- OAuth token encryption/decryption: +5-10ms per login
- Device key lookup: +2-5ms per message (cached in Redis)
- E2EE message encryption: +10-20ms per message
- Index overhead: +1-2% on INSERT operations

### Monitoring Recommendations

**Database metrics**:
- `oauth_connections` table size (growth rate)
- `device_keys` table size (1-5 keys per user)
- `key_exchanges` table size (1 per conversation per user pair)
- Index hit rate (should be > 95%)

**Application metrics**:
- OAuth token refresh success rate (should be > 99%)
- E2EE message encryption time (p95 < 100ms)
- Device key cache hit rate (should be > 90%)

---

## Testing Strategy

### Unit Tests

**Database Layer**:
- [ ] Test oauth_connections CRUD operations
- [ ] Test device_keys unique constraint enforcement
- [ ] Test key_exchanges foreign key cascades
- [ ] Test encryption_version constraint (invalid values rejected)

**Application Layer**:
- [ ] Test OAuth token encryption/decryption roundtrip
- [ ] Test X25519 key pair generation
- [ ] Test ECDH shared secret computation
- [ ] Test ChaCha20-Poly1305 message encryption roundtrip

### Integration Tests

- [ ] Test OAuth login → token encryption → token refresh cycle
- [ ] Test device registration → key exchange → E2EE message flow
- [ ] Test multi-device E2EE (same user, multiple devices)
- [ ] Test cross-device E2EE (different users, different devices)

### End-to-End Tests

- [ ] User A registers device, User B registers device
- [ ] User A initiates key exchange with User B
- [ ] User A sends E2EE message to User B
- [ ] User B receives and decrypts message
- [ ] Verify server cannot read message content

---

## Troubleshooting

### Common Issues

**Issue 1: Migration 119 fails with "column does not exist"**
- **Cause**: Migrations 104 or 113 not applied
- **Fix**: Apply missing migrations first, then retry 119

**Issue 2: Migration 122 fails with "foreign key violation"**
- **Cause**: `users` or `conversations` table missing
- **Fix**: Verify migrations 001 and 018 applied, check table exists

**Issue 3: OAuth token refresh fails**
- **Cause**: `tokens_encrypted = FALSE` (using old hashed tokens)
- **Fix**: User must re-authenticate to get new encrypted tokens

**Issue 4: E2EE message send fails**
- **Cause**: No device keys registered
- **Fix**: Client must register device keys before sending E2EE messages

**Issue 5: Constraint violation on encryption_version**
- **Cause**: App trying to set encryption_version to invalid value (not 1 or 2)
- **Fix**: Update app code to use only valid values (1=plaintext, 2=E2EE)

---

## FAQ

**Q: Why are OAuth tokens encrypted instead of hashed?**
A: Hashed tokens cannot be used for token refresh. OAuth providers require the original token to refresh, not a hash. Encryption allows secure storage while maintaining the ability to retrieve the original token.

**Q: Why use X25519 instead of RSA for key exchange?**
A: X25519 is faster, has smaller keys (32 bytes vs 2048+ bits), and is more secure against side-channel attacks. It's the modern standard for ECDH.

**Q: Why ChaCha20-Poly1305 instead of AES-GCM for messages?**
A: Both are secure, but ChaCha20-Poly1305 is faster on mobile devices without hardware AES acceleration. It's the algorithm used by Signal and WhatsApp for E2EE.

**Q: What happens to old hashed OAuth tokens?**
A: They remain in the database with `tokens_encrypted = FALSE` but cannot be used for token refresh. Users will be prompted to re-authenticate when tokens expire.

**Q: Can we support both plaintext and E2EE messages in the same conversation?**
A: Yes, `encryption_version` is per-message, not per-conversation. However, UI should prevent mixing for user clarity.

**Q: What if a user loses their device (and private keys)?**
A: They can register a new device and re-exchange keys with their contacts. Old messages encrypted with the lost device keys are unrecoverable (by design, for security).

**Q: How do we rotate the master encryption key?**
A: Use AWS KMS key rotation (automatic). New encryptions use new key, old ciphertexts remain decryptable. Manual rotation requires re-encrypting all tokens and device keys.

---

## References

### Documentation
- [BATCH_3_MIGRATION_REPORT.md](./BATCH_3_MIGRATION_REPORT.md) - Detailed technical analysis
- [BATCH_3_EXECUTION_CHECKLIST.md](./BATCH_3_EXECUTION_CHECKLIST.md) - Deployment guide
- [BATCH_3_VERIFICATION.sql](./BATCH_3_VERIFICATION.sql) - Verification script

### External References
- [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html)
- [X25519 Specification (RFC 7748)](https://datatracker.ietf.org/doc/html/rfc7748)
- [ChaCha20-Poly1305 Specification (RFC 8439)](https://datatracker.ietf.org/doc/html/rfc8439)
- [Signal Protocol Whitepaper](https://signal.org/docs/specifications/doubleratchet/)

### Related Migrations
- Migration 001: Create users table
- Migration 018: Create conversations table
- Migration 104: Create messages table with encryption_version
- Migration 113: Add content_encrypted/content_nonce to messages

---

## Support

For questions or issues with these migrations, contact:
- **Database Team**: (schema issues, rollback assistance)
- **Security Team**: (cryptography questions, key management)
- **Backend Team**: (application integration, API endpoints)

**Emergency Rollback**: Follow rollback procedure in this document. If issues persist, restore from backup and contact database team immediately.

---

**End of README**
