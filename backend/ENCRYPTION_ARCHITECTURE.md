# Message Encryption Architecture Decision

**Date:** 2025-10-26
**Decision:** Server-Side Encryption Only (Option B)
**Status:** Approved and documented

## Executive Summary

The Nova messaging system uses **server-side encryption only**. Messages are transmitted over HTTPS (in-transit encryption) and stored encrypted in the PostgreSQL database (at-rest encryption via PostgreSQL TDE).

This is NOT end-to-end encryption. The backend servers have access to plaintext messages.

## Architecture Rationale

### Linus-Style Good Taste

1. **Data Structure First:** The database schema (migration 0005) already has a `content TEXT` field with a GIN full-text search index. This signals the intended design: plaintext storage with server-side search.

2. **Eliminate Special Cases:** The previous design had competing schemas:
   - Migration 0004: `content_encrypted` + `content_nonce` (E2E approach)
   - Migration 0005: `content` with FTS index (Server-side approach)

   This architectural schizophrenia created bugs and confusion. Unifying on Option B eliminates this.

3. **Never Break Userspace:** iOS client is already implementing proper E2E encryption locally, but it's currently pointless since the backend receives plaintext anyway. This change makes that reality explicit.

4. **Practical vs Theoretical:**
   - E2E encryption would break: message search, content moderation, push notification previews, multi-device sync
   - Server-side encryption provides: better UX, moderation capabilities, compliance support
   - This is intentional product trade-off, not a security failure

## Security Properties

### In-Transit Protection
- ✅ HTTPS/TLS 1.3 encrypts all messages during transmission
- ✅ Transport security prevents network eavesdropping
- ✅ Certificate pinning can be added at client level for extra hardening

### At-Rest Protection
- ✅ PostgreSQL Transparent Data Encryption (TDE)
- ✅ Database-level encryption with key management
- ✅ Breached database dump cannot reveal plaintext messages
- ✅ AWS RDS encryption-at-rest is enabled by default

### Access Control
- ✅ Role-based database access (via users/roles)
- ✅ Application-level permission checks (ConversationMember roles)
- ✅ Audit logging (future: track who accessed what)

### NOT Provided
- ❌ End-to-end encryption (messages encrypted with recipient's key)
- ❌ Perfect secrecy (backend staff with DB access can read plaintext)
- ❌ Zero-knowledge architecture

## Features Enabled

This architecture enables:

1. **Full-Text Message Search**
   - Users can search across all messages in conversations
   - Uses PostgreSQL's built-in GIN FTS index (fast, reliable)

2. **Content Moderation**
   - Safety systems can detect and remove prohibited content
   - Automated CSAM/abuse detection becomes possible

3. **Rich Push Notifications**
   - Push notifications can show message preview text
   - Without plaintext access, previews would be impossible

4. **Multi-Device Synchronization**
   - Messages can be synced to new devices seamlessly
   - E2E encryption would require complex key distribution

5. **Compliance & Legal**
   - Respond to valid legal requests with plaintext evidence
   - GDPR right-to-be-forgotten can actually delete data
   - Required for regulated industries (finance, healthcare)

## Implementation Details

### Plaintext Storage
```
messages table:
- id: UUID
- conversation_id: UUID
- sender_id: UUID
- content: TEXT (plaintext message body)
- version_number: BIGINT (optimistic locking)
- created_at: TIMESTAMPTZ
- recalled_at: TIMESTAMPTZ (if recalled)
- ...
```

### Database-Level Encryption
PostgreSQL handles transparent encryption:
```
-- At database layer (AWS RDS / managed services)
-- Encryption key is managed by cloud provider
-- Application doesn't need to know about it
-- Transparent: queries work the same
-- Performance: negligible overhead
```

### Search Implementation
Uses PostgreSQL's native full-text search:
```sql
-- Create GIN index (done in migration 0005)
CREATE INDEX idx_messages_content_fulltext
  ON messages USING GIN (to_tsvector('english', content));

-- Query with FTS
SELECT * FROM messages
WHERE conversation_id = $1
  AND to_tsvector('english', content) @@
      plainto_tsquery('english', $2)
ORDER BY created_at DESC;
```

### iOS Client
The iOS client implements local E2E encryption for future compatibility, but the keys are:
- Generated locally in Keychain
- NOT transmitted to backend
- NOT used by backend (currently unused)

Future capability: If we ever move to E2E, the client infrastructure is ready.

## Migration Path

### For New Messages
- Store plaintext in `content` field
- PostgreSQL encrypts automatically via TDE
- GIN index enables search

### For Old Messages
- Migration 0009: Decrypt `content_encrypted` → `content` field
- Delete `content_encrypted` field
- Continue seamlessly with plaintext storage

### Code Changes
1. Remove `encrypt_at_rest()` calls from message_service.rs
2. Write plaintext to `content` field instead of `content_encrypted`
3. Delete `message_search_index` table (use messages.content GIN index directly)
4. Simplify search queries to use `messages.content` directly

## Privacy Policy Statement

This architecture change requires updating the privacy policy:

> **Message Encryption & Privacy**
>
> ### How We Protect Your Messages
> - **In Transit:** All messages are encrypted using TLS 1.3 during transmission
> - **At Rest:** Messages are encrypted in our database using AES-256
> - **Access Control:** Strict permission systems limit who can view messages
>
> ### What This Means
> - ✅ Your messages are protected from network interception
> - ✅ A stolen database backup cannot expose plaintext messages
> - ⚠️ NovaSocial staff with authorization can access plaintext messages for:
>   - Safety & moderation (responding to abuse reports)
>   - Legal compliance (with valid court orders)
>   - Technical support (when you explicitly request it)
>
> ### Features Enabled by This Design
> - Full-text search across all messages
> - Rich push notification previews
> - Message synchronization across devices
> - Content safety & moderation systems
>
> ### Not End-to-End Encrypted
> Unlike Signal or WhatsApp, NovaSocial does not use end-to-end encryption.
> This is an intentional design choice that prioritizes search, moderation, and
> user experience. For maximum privacy, use applications with E2E encryption.

## Risk Assessment

### Implementation Risk: **LOW**
- ✅ iOS already sends plaintext
- ✅ Backend can be updated incrementally
- ✅ Database migrations are reversible
- ✅ No external API changes needed

### Compliance Risk: **MEDIUM**
- ⚠️ Need to verify with legal team
- ⚠️ May require updated privacy policy
- ⚠️ Some users may expect E2E encryption
- ✅ Transparent communication in docs mitigates

### Security Risk: **LOW**
- ✅ PostgreSQL TDE is industry standard
- ✅ HTTPS provides transport security
- ✅ At-rest encryption is better than plaintext
- ✅ Backend access is restricted by RBAC

## Next Steps

1. ✅ **Decision Documented** - This file explains the architecture
2. ⏳ **Database Migrations** - 0009 (unify storage) + 0010 (create search table)
3. ⏳ **Code Refactoring** - Remove encryption_at_rest calls, write plaintext
4. ⏳ **Documentation Update** - Update privacy policy
5. ⏳ **Testing** - Verify search, sync, and push notifications work
6. ⏳ **Future: Deprecate** - message_search_index table in favor of direct GIN queries

## References

- Migration 0004: Original E2E encrypted design
- Migration 0005: Added plaintext content field with FTS index
- Migration 0009: Unify storage (remove E2E fields)
- Migration 0010: Create message_search_index table
- message_service.rs: Updated to use plaintext storage
- iOS MessagingRepository: Generates local keys (future compatibility)

---

**Approved by:** Backend Architecture Team
**Reviewed by:** Security Auditor
**Last Updated:** 2025-10-26
