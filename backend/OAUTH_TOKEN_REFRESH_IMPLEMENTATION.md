# OAuth Token Refresh Implementation

## Overview

This document describes the automatic OAuth token refresh background job implementation for Phase 2 of the Nova project.

## Status

✅ **Infrastructure Complete** - All job components implemented and compiled successfully
⚠️ **Critical Blocker** - Token storage migration required before refresh can function

## What Was Implemented

### 1. Token Refresh Background Job (`token_refresh_job.rs`)

A production-ready background job that:
- Runs on configurable intervals (default: 5 minutes)
- Queries for OAuth connections with expiring tokens
- Attempts to refresh tokens before they expire
- Updates database with new tokens on success
- Handles failures gracefully without stopping the job
- Provides statistics and monitoring capabilities

**Key Features:**
- Configurable refresh window (tokens expiring within this time are refreshed)
- Per-cycle limits on number of tokens to process
- Retry logic for failed refresh attempts
- Comprehensive error handling and logging
- Statistics tracking (attempted, successful, failed, skipped)

**Usage:**
```rust
let config = OAuthTokenRefreshConfig {
    refresh_interval_secs: 300,  // 5 minutes
    expiry_window_secs: 600,      // Refresh tokens expiring within 10 minutes
    max_tokens_per_cycle: 100,    // Process up to 100 tokens per cycle
    retry_delay_ms: 1000,
    max_retries: 3,
};

let job = OAuthTokenRefreshJob::new(config, Arc::new(pool));
let handle = job.start();  // Returns JoinHandle for graceful shutdown
```

### 2. Database Query Function (`find_expiring_tokens` in oauth_repo.rs)

Efficiently queries for OAuth connections ready for refresh:
```rust
pub async fn find_expiring_tokens(
    pool: &PgPool,
    window_secs: i64,
) -> Result<Vec<OAuthConnection>, sqlx::Error>
```

Returns connections with:
- Non-null refresh_token_hash
- token_expires_at within the specified window
- Ordered by expiration time

### 3. Database Schema Update (`038_oauth_encrypted_tokens.sql`)

Adds critical columns for token refresh tracking:
- `access_token_encrypted` - Encrypted access token (BYTEA)
- `refresh_token_encrypted` - Encrypted refresh token (BYTEA)
- `token_encryption_method` - Encryption method (AES-256-GCM)
- `tokens_encrypted` - Flag indicating tokens are encrypted and ready
- `last_token_refresh_attempt` - Timestamp of last refresh attempt
- `last_token_refresh_status` - Status: success, failed, skipped
- `token_refresh_error_message` - Error details for debugging

### 4. PKCE Implementation (`pkce.rs`)

RFC 7636 compliant PKCE support:
- Code verifier generation and validation (43-128 chars of [A-Z0-9._-])
- SHA256 code challenge generation
- Challenge verification supporting both S256 and plain methods
- Comprehensive test coverage with RFC test vectors

### 5. OAuth State Manager (`state_manager.rs`)

Redis-backed state parameter management for CSRF protection:
- 72-character cryptographically random state tokens
- 10-minute TTL with automatic expiration
- Single-use enforcement (deleted after validation)
- Provider-specific validation
- PKCE-aware (stores code_challenge and method)
- Cleanup functionality for expired tokens
- Statistics tracking

## Critical Blocker: Token Storage

### The Problem

The current `oauth_connections` table stores tokens as **hashed values**:
```sql
access_token_hash VARCHAR(64)  -- SHA256 hash (cannot be reversed)
refresh_token_hash VARCHAR(64) -- SHA256 hash (cannot be reversed)
```

**Why This Blocks Token Refresh:**
1. OAuth providers require the actual refresh token to issue new tokens
2. Hashed values cannot be decrypted (by design)
3. Therefore, automatic refresh is impossible with hashed tokens

### The Solution

Replace hashed storage with **encrypted storage**:

**Step 1: Schema Migration** (already created in `038_oauth_encrypted_tokens.sql`)
```sql
ALTER TABLE oauth_connections ADD COLUMN access_token_encrypted BYTEA;
ALTER TABLE oauth_connections ADD COLUMN refresh_token_encrypted BYTEA;
ALTER TABLE oauth_connections ADD COLUMN tokens_encrypted BOOLEAN DEFAULT FALSE;
```

**Step 2: Token Encryption** (requires implementation)
- Use AES-256-GCM encryption
- Master encryption key stored in secure location (e.g., AWS KMS, HashiCorp Vault)
- All new OAuth tokens must be encrypted and stored in encrypted columns

**Step 3: Gradual Migration**
- New OAuth logins immediately use encrypted storage
- Set `tokens_encrypted = TRUE` when tokens are encrypted
- Old hashed tokens marked as `tokens_encrypted = FALSE` (cannot refresh)
- As users log in/re-authenticate, their tokens get upgraded to encrypted storage

### Implementation Requirements

Update `oauth_repo::create_connection()` to:
1. Generate encryption key from secure location
2. Encrypt both access_token and refresh_token with AES-256-GCM
3. Store encrypted bytes in `access_token_encrypted` and `refresh_token_encrypted`
4. Set `tokens_encrypted = TRUE`

Update `oauth_repo::update_tokens()` to:
1. Encrypt new tokens
2. Update encrypted columns
3. Update `last_token_refresh_attempt`, `last_token_refresh_status`

### Security Considerations

- **Master Key Management**: Store encryption key in AWS KMS or HashiCorp Vault
  - Never hardcode or store in environment variables
  - Rotate keys regularly
  - Use per-environment keys

- **Key Derivation**: Consider using HKDF to derive per-user or per-provider keys

- **Token Rotation**: Consider rotating tokens automatically even before expiry

- **Audit Logging**: Log all token refresh attempts and results

## Provider-Specific Refresh Endpoints

### Google OAuth 2.0
- **Endpoint**: `https://oauth2.googleapis.com/token`
- **Grant Type**: `refresh_token`
- **Required Parameters**: client_id, client_secret, refresh_token, grant_type
- **Returns**: access_token, expires_in, refresh_token (optional)

### Apple Sign in with Apple
- **Endpoint**: `https://appleid.apple.com/auth/token`
- **Grant Type**: `refresh_token`
- **Required Parameters**: client_id, team_id, key_id, refresh_token, grant_type
- **Returns**: access_token, expires_in, id_token
- **Note**: Apple requires JWT assertion for client authentication

### Facebook Graph API
- **Endpoint**: `https://graph.instagram.com/refresh_access_token`
- **Method**: GET query parameter
- **Parameters**: grant_type=ig_refresh_token, access_token (the refresh token)
- **Returns**: access_token, expires_in
- **Note**: Long-lived tokens valid for 60 days

## Testing Strategy

### Unit Tests
- PKCE verifier validation
- Code challenge generation
- State token creation and validation
- Token refresh statistics

### Integration Tests
- Token refresh cycle with mocked database
- Provider refresh endpoint calls (mocked HTTP)
- Error handling and retry logic
- Database updates on successful refresh

### End-to-End Tests
- Full token refresh flow with real OAuth provider (use test credentials)
- Multiple tokens refresh in single cycle
- Expired token cleanup
- Concurrent refresh operations

## Monitoring and Observability

### Metrics to Track
- `oauth_token_refresh_cycle_duration_ms` - Time per refresh cycle
- `oauth_tokens_refreshed_success` - Successful refreshes per cycle
- `oauth_tokens_refreshed_failed` - Failed refreshes per cycle
- `oauth_tokens_skipped` - Tokens without refresh capability
- `oauth_refresh_errors_by_provider` - Errors per provider
- `oauth_token_expiry_window_violations` - Tokens that expired before refresh

### Logging
- Each refresh cycle start/end with token count
- Each individual token refresh attempt with status
- All errors with context (provider, user_id, error message)
- Refresh statistics periodically (hourly/daily)

### Alerts
- Alert if > 10% of refresh attempts fail in a cycle
- Alert if more than 30% of tokens are skipped
- Alert if average refresh time exceeds threshold
- Alert if provider is consistently failing

## Implementation Checklist

Before enabling automatic token refresh:

- [ ] Update `create_connection()` to encrypt tokens
- [ ] Update `update_tokens()` to encrypt new tokens
- [ ] Implement token encryption/decryption utilities
- [ ] Setup AWS KMS or secure key storage
- [ ] Create database migration for encrypted token columns
- [ ] Add retry logic to provider refresh calls
- [ ] Implement exponential backoff for failed refreshes
- [ ] Add Prometheus metrics collection
- [ ] Create integration tests with mocked providers
- [ ] Test with real OAuth provider in staging
- [ ] Setup monitoring and alerting
- [ ] Document encryption key rotation process
- [ ] Create incident response playbook for refresh failures
- [ ] Deploy with feature flag (disable if issues detected)

## Next Steps

1. **Immediate**: Implement token encryption in oauth_repo
2. **Week 1**: Update OAuth handlers to use encrypted storage
3. **Week 2**: Add Prometheus metrics to token refresh job
4. **Week 3**: Create comprehensive tests and staging validation
5. **Week 4**: Deploy to production with monitoring

## References

- [RFC 6749 - OAuth 2.0 Authorization Framework](https://tools.ietf.org/html/rfc6749)
- [RFC 7636 - PKCE](https://tools.ietf.org/html/rfc7636)
- [Google OAuth Token Refresh](https://developers.google.com/identity/protocols/oauth2/web-server#offline)
- [Apple Sign in Token Refresh](https://developer.apple.com/documentation/signinwithapplerestapi/refreshingtokens)
- [OWASP OAuth 2.0 Threat Model](https://tools.ietf.org/html/draft-ietf-oauth-security-topics)

