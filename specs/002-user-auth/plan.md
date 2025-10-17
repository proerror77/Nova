# Technical Implementation Plan: User Authentication Service

**Feature**: User Authentication System
**Spec**: [`002-user-auth/spec.md`](./spec.md)
**Created**: 2025-10-17
**Status**: Ready for Implementation
**Constitution Compliance**: ✅ Validated against [Project Constitution](../../.specify/memory/constitution.md)

---

## Executive Summary

**What We're Building**: A production-grade authentication microservice in Rust that handles user registration, login, OAuth2 integration (Apple/Google/Facebook), password reset, 2FA, and session management. Built following Test-Driven Development (TDD) principles.

**Architecture Philosophy** (Linus-style):
- **Data structures first**: PostgreSQL schema drives API design, not the other way around
- **Eliminate special cases**: Unified OAuth provider abstraction (`OAuthProvider` trait) for Apple/Google/Facebook
- **Simplicity wins**: Stateless JWT tokens + Redis for ephemeral state (rate limiting, token blacklist)
- **No breaking changes**: JWT version field supports future token format evolution without user impact

**Tech Stack**:
- **Runtime**: Rust (latest stable) + Actix-web
- **Database**: PostgreSQL 14+ (ACID transactions, foreign keys, indexes)
- **Cache**: Redis 7+ (rate limiting, session blacklist, TOTP secrets)
- **Security**: bcrypt (cost 12), JWT (RS256), TLS 1.3
- **Testing**: `cargo test` (unit) + `reqwest` (integration) + `testcontainers` (E2E)

---

## Table of Contents

1. [Microservice Architecture Design](#1-microservice-architecture-design)
2. [Database Schema Design](#2-database-schema-design)
3. [API Endpoint Specifications](#3-api-endpoint-specifications)
4. [Redis Caching Strategy](#4-redis-caching-strategy)
5. [JWT Token Flow](#5-jwt-token-flow)
6. [OAuth2 Integration](#6-oauth2-integration)
7. [Security Implementation](#7-security-implementation)
8. [Test Strategy (TDD)](#8-test-strategy-tdd)
9. [Implementation Phases](#9-implementation-phases)
10. [Operational Considerations](#10-operational-considerations)

---

## 1. Microservice Architecture Design

### 1.1 Service Boundary

**Auth Service Responsibilities** (Single Responsibility Principle):
- User registration, login, logout
- Password hashing, verification, reset
- OAuth2 provider integration (Apple/Google/Facebook)
- JWT token issuance, validation, refresh, revocation
- Two-factor authentication (TOTP)
- Rate limiting, authentication logging
- Email verification (delegates sending to Email Service)

**Does NOT Handle** (Bounded Context):
- User profiles (name, bio, avatar) → User Profile Service (future)
- Social features (followers, posts, feed) → Dedicated services
- Email delivery → Email Service (async via message queue)

**Why This Boundary?**
Authentication is security-critical and requires independent scaling. Login traffic spikes (morning rush hour) differ from profile update patterns. Isolation limits blast radius of security vulnerabilities.

### 1.2 Service Architecture

```mermaid
graph TB
    Client[iOS App / API Client]
    Gateway[API Gateway<br/>NGINX/Kong]
    AuthSvc[Auth Service<br/>Rust/Actix-web]
    DB[(PostgreSQL<br/>Users, Tokens)]
    Redis[(Redis<br/>Cache, Rate Limit)]
    EmailQueue[Message Queue<br/>Kafka/RabbitMQ]
    EmailSvc[Email Service<br/>SendGrid/SES]
    OAuthProviders[OAuth Providers<br/>Apple/Google/Facebook]

    Client -->|HTTPS| Gateway
    Gateway -->|Internal gRPC/REST| AuthSvc
    AuthSvc -->|SQL| DB
    AuthSvc -->|GET/SET/INCR| Redis
    AuthSvc -->|Publish event| EmailQueue
    EmailQueue -->|Consume| EmailSvc
    AuthSvc -->|OAuth2 flow| OAuthProviders

    style AuthSvc fill:#f9f,stroke:#333,stroke-width:4px
    style DB fill:#ccf
    style Redis fill:#fcc
```

**Component Descriptions**:
- **API Gateway**: SSL termination, rate limiting (coarse-grained per IP), request routing, CORS handling
- **Auth Service**: Core business logic, runs in Kubernetes pods (3+ replicas for HA)
- **PostgreSQL**: Master-replica setup, connection pooling via PgBouncer
- **Redis**: Sentinel mode (HA), dedicated instances for rate limiting vs session data
- **Message Queue**: Async email delivery (fire-and-forget pattern)

### 1.3 API Gateway Integration

**Gateway Responsibilities**:
- **SSL/TLS Termination**: Enforce HTTPS, redirect HTTP → HTTPS
- **CORS Handling**: Preflight requests for web clients
- **IP Rate Limiting**: Max 100 requests/minute per IP (DDoS protection)
- **Request Routing**: `/auth/*` → Auth Service, `/api/*` → Other services

**Auth Service Responsibilities** (Fine-Grained):
- **User-Level Rate Limiting**: Max 5 login attempts per email per 15 minutes
- **Token Validation Middleware**: Inject user context into downstream services
- **Audit Logging**: Record all authentication events

**NGINX Config Example** (simplified):
```nginx
upstream auth_service {
    server auth-service:8080;
    keepalive 32;
}

server {
    listen 443 ssl http2;
    ssl_protocols TLSv1.3;

    location /auth/ {
        proxy_pass http://auth_service/;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

### 1.4 Service Communication Patterns

**Synchronous** (Request-Reply):
- Client → Auth Service: REST APIs (registration, login, refresh token)
- Auth Service → PostgreSQL: SQL queries (user lookup, token storage)
- Auth Service → Redis: Cache checks (rate limiting, token blacklist)

**Asynchronous** (Event-Driven):
- Auth Service → Email Service: Publish `EmailVerificationRequested` event to Kafka/RabbitMQ
- Email Service consumes event → Sends verification email via SendGrid/SES
- **Why Async?**: Email delivery is non-critical path (200ms+ latency). User shouldn't wait for email to be sent before seeing "Check your inbox" message.

**Event Schema Example** (JSON over Kafka):
```json
{
  "event_type": "EmailVerificationRequested",
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "user@example.com",
  "verification_token": "abc123...",
  "timestamp": "2025-10-17T10:30:00Z"
}
```

---

## 2. Database Schema Design

### 2.1 Schema Overview (PostgreSQL 14+)

**Design Principles**:
- **Normalize to 3NF**: Eliminate redundancy, enforce referential integrity
- **UUIDs for IDs**: Distributed-system friendly, no auto-increment collisions
- **Timestamps**: Always include `created_at`, `updated_at` (audit trail)
- **Soft Deletes**: `deleted_at` column (GDPR compliance, data retention policies)
- **Indexes**: Cover common queries (email lookup, username lookup, token validation)

### 2.2 Table Definitions

#### 2.2.1 `users` Table

**Purpose**: Core user account information

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    email_verified_at TIMESTAMP WITH TIME ZONE,
    username VARCHAR(30) UNIQUE NOT NULL,
    password_hash VARCHAR(255), -- bcrypt hash, NULL for OAuth-only users
    account_status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (account_status IN ('active', 'suspended', 'deleted')),
    totp_secret VARCHAR(64), -- Base32-encoded TOTP secret, NULL if 2FA disabled
    totp_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMP WITH TIME ZONE -- Soft delete
);

-- Indexes for performance
CREATE INDEX idx_users_email ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_username ON users(LOWER(username)) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_created_at ON users(created_at);
```

**Key Decisions**:
- `email_verified_at`: NULL = unverified, timestamp = verified (explicit state)
- `password_hash`: Nullable to support OAuth-only users (no email/password)
- `username`: Case-insensitive uniqueness via `LOWER()` index
- `deleted_at`: Soft delete enables 30-day grace period (App Store compliance)

#### 2.2.2 `oauth_connections` Table

**Purpose**: Link users to external OAuth providers

```sql
CREATE TABLE oauth_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider VARCHAR(20) NOT NULL CHECK (provider IN ('apple', 'google', 'facebook')),
    provider_user_id VARCHAR(255) NOT NULL,
    provider_email VARCHAR(255), -- May differ from users.email
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    UNIQUE(provider, provider_user_id) -- Prevent duplicate OAuth links
);

-- Indexes
CREATE INDEX idx_oauth_user_id ON oauth_connections(user_id);
CREATE INDEX idx_oauth_provider ON oauth_connections(provider, provider_user_id);
```

**Key Decisions**:
- **Composite Uniqueness**: `(provider, provider_user_id)` prevents same Apple ID linking twice
- **Cascade Delete**: When user deletes account, remove OAuth links automatically
- **provider_email**: Stored separately from `users.email` (user may change primary email)

#### 2.2.3 `auth_tokens` Table

**Purpose**: Track issued JWT refresh tokens for revocation

```sql
CREATE TABLE auth_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE, -- SHA-256 hash of refresh token
    token_type VARCHAR(20) NOT NULL DEFAULT 'refresh' CHECK (token_type IN ('refresh')),
    device_id VARCHAR(255), -- Optional: identify device for session management
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMP WITH TIME ZONE -- NULL = active, timestamp = revoked
);

-- Indexes
CREATE INDEX idx_tokens_user_id ON auth_tokens(user_id);
CREATE INDEX idx_tokens_hash ON auth_tokens(token_hash) WHERE revoked_at IS NULL;
CREATE INDEX idx_tokens_expires_at ON auth_tokens(expires_at); -- Cleanup expired tokens
```

**Key Decisions**:
- **Only Refresh Tokens Stored**: Access tokens are stateless JWT (not stored in DB)
- **Token Hash**: Store SHA-256 hash, not plaintext (defense in depth)
- **revoked_at**: Explicit revocation for logout/logout-all operations
- **device_id**: Optional future feature for "Active Sessions" management

#### 2.2.4 `password_reset_tokens` Table

**Purpose**: One-time password reset links (1-hour expiry)

```sql
CREATE TABLE password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_email VARCHAR(255) NOT NULL, -- Email, not user_id (user may not exist yet)
    token_hash VARCHAR(255) NOT NULL UNIQUE, -- SHA-256 hash
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL, -- created_at + 1 hour
    used_at TIMESTAMP WITH TIME ZONE -- NULL = unused, timestamp = consumed
);

-- Indexes
CREATE INDEX idx_reset_tokens_email ON password_reset_tokens(user_email);
CREATE INDEX idx_reset_tokens_expires_at ON password_reset_tokens(expires_at); -- Cleanup
```

**Key Decisions**:
- **Email-Based**: Use email instead of user_id (supports "forgot username" scenario)
- **One-Time Use**: `used_at` prevents token reuse attacks
- **Automatic Expiry**: Cleanup job deletes tokens older than 24 hours

#### 2.2.5 `auth_logs` Table

**Purpose**: Audit trail for security events (GDPR compliance, fraud detection)

```sql
CREATE TABLE auth_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID, -- Nullable: failed logins don't have user_id yet
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN (
        'registration', 'login_success', 'login_failed', 'logout',
        'password_reset_requested', 'password_reset_completed',
        'email_verified', '2fa_enabled', '2fa_disabled', 'account_deleted'
    )),
    ip_address INET NOT NULL, -- PostgreSQL native IP type
    user_agent TEXT,
    success BOOLEAN NOT NULL,
    failure_reason VARCHAR(255), -- e.g., "invalid_password", "rate_limited"
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_logs_user_id ON auth_logs(user_id, created_at DESC);
CREATE INDEX idx_logs_event_type ON auth_logs(event_type, created_at DESC);
CREATE INDEX idx_logs_created_at ON auth_logs(created_at); -- Time-series queries
```

**Key Decisions**:
- **INET Type**: Native PostgreSQL IP address type (supports IPv4/IPv6, range queries)
- **Nullable user_id**: Failed logins may not resolve to valid user
- **Retention Policy**: Archive/delete logs older than 90 days (GDPR compliance)

#### 2.2.6 `password_history` Table

**Purpose**: Prevent password reuse (FR-015)

```sql
CREATE TABLE password_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    password_hash VARCHAR(255) NOT NULL, -- bcrypt hash
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_password_history_user ON password_history(user_id, created_at DESC);
```

**Key Decisions**:
- **Keep Last 3 Passwords**: Application logic enforces checking last 3 hashes
- **Cascade Delete**: User deletion removes password history (GDPR)

### 2.3 Database Constraints & Triggers

#### 2.3.1 Updated Timestamp Trigger

**Automatically update `updated_at` on row modification**:

```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
```

#### 2.3.2 Foreign Key Constraints

**Already defined via `REFERENCES` clauses above. Summary**:
- `oauth_connections.user_id` → `users.id` (CASCADE DELETE)
- `auth_tokens.user_id` → `users.id` (CASCADE DELETE)
- `password_history.user_id` → `users.id` (CASCADE DELETE)

**Why CASCADE DELETE?**: When user deletes account, all related data must be purged (GDPR "right to be forgotten").

### 2.4 Sample Data (for Testing)

```sql
-- Test user: alice@example.com / Password123!
INSERT INTO users (id, email, email_verified_at, username, password_hash, account_status)
VALUES (
    '550e8400-e29b-41d4-a716-446655440000',
    'alice@example.com',
    NOW(),
    'alice',
    '$2b$12$KIXxLVq2gF.6wQ9zYv0VZeR9XQ9Q9Q9Q9Q9Q9Q9Q9Q9Q9Q9Q9Q9', -- bcrypt hash
    'active'
);

-- OAuth connection: Alice linked to Google
INSERT INTO oauth_connections (user_id, provider, provider_user_id, provider_email)
VALUES (
    '550e8400-e29b-41d4-a716-446655440000',
    'google',
    '1234567890',
    'alice@gmail.com'
);
```

---

## 3. API Endpoint Specifications

### 3.1 API Design Principles

- **RESTful Routes**: Standard HTTP methods (GET, POST, PUT, DELETE)
- **JSON Payloads**: Request/response bodies in JSON (UTF-8)
- **Versioning**: URL-based (`/v1/auth/*`) for future-proofing
- **Error Handling**: Consistent error format (RFC 7807 Problem Details)
- **Rate Limiting**: HTTP 429 with `Retry-After` header
- **CORS**: Enabled for web clients (preflight `OPTIONS` requests)

### 3.2 Base URL & Headers

**Base URL**: `https://api.nova.example.com/v1/auth`

**Common Headers**:
```http
Content-Type: application/json
Accept: application/json
X-Request-ID: <UUID>  # Client-generated for tracing
Authorization: Bearer <JWT>  # For authenticated endpoints
```

### 3.3 Endpoint Catalog

#### 3.3.1 User Registration

**Endpoint**: `POST /v1/auth/register`

**Request Body**:
```json
{
  "email": "alice@example.com",
  "password": "StrongP@ssw0rd!",
  "username": "alice"
}
```

**Validation Rules**:
- `email`: RFC 5322 format, max 255 chars
- `password`: Min 8 chars, max 128 chars, must contain: uppercase, lowercase, digit, special char
- `username`: 3-30 alphanumeric chars + underscores, case-insensitive unique

**Response** (201 Created):
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "alice@example.com",
  "username": "alice",
  "email_verified": false,
  "message": "Registration successful. Check your email to verify your account."
}
```

**Error Responses**:
- **400 Bad Request**: Invalid email format, weak password, username taken
  ```json
  {
    "type": "https://api.nova.example.com/errors/validation-error",
    "title": "Validation Error",
    "status": 400,
    "detail": "Password must be at least 8 characters and contain uppercase, lowercase, digit, and special character.",
    "instance": "/v1/auth/register",
    "errors": {
      "password": ["too_weak"]
    }
  }
  ```
- **409 Conflict**: Email already registered
  ```json
  {
    "type": "https://api.nova.example.com/errors/conflict",
    "title": "Email Already Registered",
    "status": 409,
    "detail": "An account with this email already exists. Try logging in instead.",
    "instance": "/v1/auth/register"
  }
  ```
- **429 Too Many Requests**: Rate limit exceeded
  ```json
  {
    "type": "https://api.nova.example.com/errors/rate-limit",
    "title": "Too Many Requests",
    "status": 429,
    "detail": "Maximum 5 registration attempts per 15 minutes. Try again later.",
    "retry_after": 600
  }
  ```

**Side Effects**:
1. Hash password with bcrypt (cost 12)
2. Insert user into `users` table
3. Generate email verification token (UUID)
4. Publish `EmailVerificationRequested` event to message queue
5. Log `registration` event to `auth_logs`

#### 3.3.2 Email Verification

**Endpoint**: `POST /v1/auth/verify-email`

**Request Body**:
```json
{
  "token": "abc123def456ghi789jkl012mno345pqr678stu901vwx234yz"
}
```

**Response** (200 OK):
```json
{
  "message": "Email verified successfully. You can now log in.",
  "email_verified": true
}
```

**Error Responses**:
- **400 Bad Request**: Invalid token format
- **404 Not Found**: Token not found or already used
- **410 Gone**: Token expired (>24 hours old)

**Side Effects**:
1. Validate token exists in Redis (key: `email_verify:{token}`, value: `user_id`)
2. Update `users.email_verified_at` to current timestamp
3. Delete token from Redis
4. Log `email_verified` event

#### 3.3.3 User Login (Email/Password)

**Endpoint**: `POST /v1/auth/login`

**Request Body**:
```json
{
  "email": "alice@example.com",
  "password": "StrongP@ssw0rd!"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "550e8400-e29b-41d4-a716-446655440000",
  "token_type": "Bearer",
  "expires_in": 3600,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "alice@example.com",
    "username": "alice",
    "email_verified": true,
    "totp_enabled": false
  }
}
```

**Error Responses**:
- **400 Bad Request**: Missing email/password
- **401 Unauthorized**: Invalid credentials
  ```json
  {
    "type": "https://api.nova.example.com/errors/unauthorized",
    "title": "Invalid Credentials",
    "status": 401,
    "detail": "Email or password is incorrect.",
    "instance": "/v1/auth/login"
  }
  ```
- **403 Forbidden**: Account locked (too many failed attempts)
  ```json
  {
    "type": "https://api.nova.example.com/errors/account-locked",
    "title": "Account Temporarily Locked",
    "status": 403,
    "detail": "Too many failed login attempts. Try again in 15 minutes.",
    "retry_after": 900
  }
  ```
- **428 Precondition Required**: Email not verified
  ```json
  {
    "type": "https://api.nova.example.com/errors/email-not-verified",
    "title": "Email Not Verified",
    "status": 428,
    "detail": "Please verify your email before logging in.",
    "instance": "/v1/auth/login"
  }
  ```

**Side Effects**:
1. Check rate limit in Redis (`login_attempts:{email}`)
2. Lookup user by email
3. Verify password with bcrypt
4. Generate JWT access token (1-hour expiry)
5. Generate refresh token (UUID, 30-day expiry)
6. Store refresh token hash in `auth_tokens` table
7. Log `login_success` or `login_failed` event
8. Increment failed login counter (Redis INCR with 15-min TTL)

#### 3.3.4 User Login (2FA Flow)

**Step 1**: Same as 3.3.3, but if `totp_enabled = true`, return:

**Response** (200 OK):
```json
{
  "requires_2fa": true,
  "temp_token": "temp_abc123...",
  "message": "Enter the 6-digit code from your authenticator app."
}
```

**Step 2**: Submit TOTP code

**Endpoint**: `POST /v1/auth/login/2fa`

**Request Body**:
```json
{
  "temp_token": "temp_abc123...",
  "totp_code": "123456"
}
```

**Response** (200 OK): Same as 3.3.3 (access + refresh tokens)

**Error Responses**:
- **401 Unauthorized**: Invalid TOTP code
- **410 Gone**: Temp token expired (5 minutes)

#### 3.3.5 Refresh Access Token

**Endpoint**: `POST /v1/auth/refresh`

**Request Body**:
```json
{
  "refresh_token": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response** (200 OK):
```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

**Error Responses**:
- **401 Unauthorized**: Invalid or expired refresh token
- **403 Forbidden**: Refresh token revoked (user logged out)

**Side Effects**:
1. Validate refresh token hash exists in `auth_tokens` and not revoked
2. Check `expires_at` timestamp
3. Generate new JWT access token
4. **Optional (Refresh Token Rotation)**: Generate new refresh token, revoke old one (defense against token theft)

#### 3.3.6 Logout (Single Device)

**Endpoint**: `POST /v1/auth/logout`

**Headers**: `Authorization: Bearer <access_token>`

**Request Body**: None (or optional `device_id`)

**Response** (200 OK):
```json
{
  "message": "Logged out successfully."
}
```

**Side Effects**:
1. Decode JWT to extract `user_id` and `jti` (JWT ID)
2. Add `jti` to Redis blacklist (key: `blacklist:{jti}`, TTL: remaining token lifetime)
3. Mark refresh token as revoked in `auth_tokens.revoked_at`
4. Log `logout` event

#### 3.3.7 Logout (All Devices)

**Endpoint**: `POST /v1/auth/logout-all`

**Headers**: `Authorization: Bearer <access_token>`

**Response** (200 OK):
```json
{
  "message": "Logged out from all devices successfully.",
  "revoked_count": 3
}
```

**Side Effects**:
1. Decode JWT to extract `user_id`
2. Mark all user's refresh tokens as revoked (`UPDATE auth_tokens SET revoked_at = NOW() WHERE user_id = ? AND revoked_at IS NULL`)
3. Add all active JWT IDs to Redis blacklist (requires tracking JTIs in DB or short-lived blacklist)
4. Log `logout_all` event

#### 3.3.8 Password Reset Request

**Endpoint**: `POST /v1/auth/password-reset`

**Request Body**:
```json
{
  "email": "alice@example.com"
}
```

**Response** (200 OK):
```json
{
  "message": "If this email is registered, you will receive a password reset link."
}
```

**Note**: Always return success (prevents email enumeration attack).

**Side Effects**:
1. Lookup user by email (if not found, silently succeed)
2. Generate password reset token (UUID)
3. Store token hash in `password_reset_tokens` (expires_at: NOW() + 1 hour)
4. Publish `PasswordResetRequested` event to message queue
5. Log `password_reset_requested` event

#### 3.3.9 Password Reset Completion

**Endpoint**: `POST /v1/auth/password-reset/confirm`

**Request Body**:
```json
{
  "token": "abc123def456ghi789...",
  "new_password": "NewStrongP@ssw0rd!"
}
```

**Response** (200 OK):
```json
{
  "message": "Password reset successfully. You can now log in with your new password."
}
```

**Error Responses**:
- **400 Bad Request**: Weak password, password reuse (matches last 3)
- **404 Not Found**: Invalid token
- **410 Gone**: Token expired or already used

**Side Effects**:
1. Validate token exists in `password_reset_tokens` and not used
2. Check `expires_at` timestamp
3. Validate new password strength
4. Check against last 3 passwords in `password_history` (bcrypt compare)
5. Hash new password with bcrypt
6. Update `users.password_hash`
7. Insert old password into `password_history`
8. Mark token as used (`used_at = NOW()`)
9. Revoke all existing refresh tokens (force re-login)
10. Log `password_reset_completed` event

#### 3.3.10 OAuth2 Login (Apple/Google/Facebook)

**Endpoint**: `POST /v1/auth/oauth/{provider}/callback`

**Path Parameters**: `provider` ∈ {`apple`, `google`, `facebook`}

**Request Body** (after OAuth2 redirect):
```json
{
  "code": "oauth_authorization_code",
  "state": "csrf_protection_token"
}
```

**Response** (200 OK):
- If user exists (linked OAuth): Return access + refresh tokens (same as 3.3.3)
- If new user: Create account, return tokens
- If email conflict: Return account linking prompt

**Error Responses**:
- **400 Bad Request**: Invalid OAuth code or state mismatch (CSRF)
- **401 Unauthorized**: OAuth provider rejected request
- **409 Conflict**: Email already registered with different provider
  ```json
  {
    "type": "https://api.nova.example.com/errors/oauth-conflict",
    "title": "Account Already Exists",
    "status": 409,
    "detail": "An account with this email (alice@example.com) already exists. Link this Google account in Settings.",
    "instance": "/v1/auth/oauth/google/callback"
  }
  ```

**Side Effects** (detailed in Section 6):
1. Validate `state` parameter matches session (CSRF protection)
2. Exchange `code` for access token with OAuth provider
3. Fetch user profile from provider API
4. Check if `oauth_connections` entry exists
5. If exists: Generate JWT tokens
6. If new: Create user in `users`, insert `oauth_connections`, generate tokens
7. Log `oauth_login` event

#### 3.3.11 Enable 2FA

**Endpoint**: `POST /v1/auth/2fa/enable`

**Headers**: `Authorization: Bearer <access_token>`

**Request Body**: None

**Response** (200 OK):
```json
{
  "totp_secret": "JBSWY3DPEHPK3PXP",
  "qr_code_url": "otpauth://totp/Nova:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Nova",
  "message": "Scan the QR code with your authenticator app, then verify with a 6-digit code."
}
```

**Side Effects**:
1. Generate random TOTP secret (Base32-encoded)
2. Store secret in Redis temporarily (key: `totp_setup:{user_id}`, TTL: 10 minutes)
3. Return secret + QR code URL (frontend generates QR code)

**Step 2**: Verify TOTP code

**Endpoint**: `POST /v1/auth/2fa/verify`

**Request Body**:
```json
{
  "totp_code": "123456"
}
```

**Response** (200 OK):
```json
{
  "message": "Two-factor authentication enabled successfully.",
  "backup_codes": ["abc123", "def456", "ghi789", ...]
}
```

**Side Effects**:
1. Retrieve TOTP secret from Redis
2. Validate TOTP code against secret
3. Update `users.totp_secret` and `users.totp_enabled = TRUE`
4. Generate 10 backup codes (random UUIDs), store hashes in Redis
5. Delete temporary setup secret from Redis
6. Log `2fa_enabled` event

#### 3.3.12 Disable 2FA

**Endpoint**: `POST /v1/auth/2fa/disable`

**Headers**: `Authorization: Bearer <access_token>`

**Request Body**:
```json
{
  "password": "StrongP@ssw0rd!" // Require password confirmation
}
```

**Response** (200 OK):
```json
{
  "message": "Two-factor authentication disabled."
}
```

**Side Effects**:
1. Verify password
2. Update `users.totp_secret = NULL` and `users.totp_enabled = FALSE`
3. Delete backup codes from Redis
4. Log `2fa_disabled` event

---

## 4. Redis Caching Strategy

### 4.1 Redis Use Cases

**Why Redis?**
- **In-Memory Speed**: Sub-millisecond latency for rate limiting checks
- **Atomic Operations**: `INCR`, `EXPIRE`, Lua scripts for race-condition-free counters
- **TTL Support**: Automatic expiration (no manual cleanup for ephemeral data)
- **Pub/Sub**: Real-time notifications (future feature: session invalidation events)

### 4.2 Rate Limiting Implementation

**Requirement**: Max 5 login attempts per email per 15 minutes (FR-007)

**Algorithm**: Fixed Window Counter with Sliding Window Approximation

**Redis Keys**:
- `rate_limit:login:{email}` → Counter (INCR)
- TTL: 900 seconds (15 minutes)

**Pseudocode**:
```rust
async fn check_rate_limit(redis: &RedisClient, email: &str) -> Result<(), RateLimitError> {
    let key = format!("rate_limit:login:{}", email);
    let current_count: u32 = redis.incr(&key).await?;

    if current_count == 1 {
        redis.expire(&key, 900).await?; // Set TTL on first attempt
    }

    if current_count > 5 {
        return Err(RateLimitError::TooManyAttempts { retry_after: 900 });
    }

    Ok(())
}
```

**Edge Case Handling**:
- **Race Condition**: `INCR` is atomic (no locking needed)
- **Key Expiry**: TTL set on first attempt (idempotent with `EXPIRE`)
- **Distributed Setup**: Redis Sentinel ensures consistency across replicas

**Alternative (Sliding Window)**:
Use sorted sets (ZSET) with timestamps for more accurate sliding window:
```lua
-- Lua script for sliding window (atomic)
local key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2]) -- 900 seconds
local limit = tonumber(ARGV[3]) -- 5

redis.call('ZREMRANGEBYSCORE', key, 0, now - window)
local count = redis.call('ZCARD', key)

if count < limit then
    redis.call('ZADD', key, now, now)
    redis.call('EXPIRE', key, window)
    return 0
else
    return 1
end
```

### 4.3 Session Management (JWT Blacklist)

**Problem**: JWTs are stateless (can't revoke before expiry)

**Solution**: Blacklist revoked tokens in Redis (short-lived cache)

**Redis Keys**:
- `jwt_blacklist:{jti}` → `1` (boolean flag)
- TTL: Remaining token lifetime (max 1 hour for access tokens)

**Workflow**:
1. User logs out → Extract `jti` from JWT → Add to blacklist
2. Token validation middleware → Check if `jti` exists in blacklist → Reject if found

**Code Example**:
```rust
async fn is_token_blacklisted(redis: &RedisClient, jti: &str) -> bool {
    let key = format!("jwt_blacklist:{}", jti);
    redis.exists(&key).await.unwrap_or(false)
}

async fn blacklist_token(redis: &RedisClient, jti: &str, ttl_seconds: u64) {
    let key = format!("jwt_blacklist:{}", jti);
    redis.set_ex(&key, "1", ttl_seconds).await.unwrap();
}
```

### 4.4 Email Verification Token Storage

**Redis Keys**:
- `email_verify:{token}` → `user_id` (UUID)
- TTL: 86400 seconds (24 hours)

**Workflow**:
1. User registers → Generate UUID token → Store in Redis
2. User clicks email link → Retrieve `user_id` from Redis → Verify email
3. Token expires automatically after 24 hours (no DB cleanup needed)

**Why Redis vs PostgreSQL?**
- **Performance**: Faster lookup (no disk I/O)
- **Automatic Cleanup**: TTL handles expiration (no cron job)
- **Lower Load**: Offloads ephemeral data from primary database

### 4.5 TOTP Secret Temporary Storage

**Redis Keys**:
- `totp_setup:{user_id}` → `base32_secret`
- TTL: 600 seconds (10 minutes)

**Workflow**:
1. User initiates 2FA setup → Generate secret → Store in Redis
2. User scans QR code and submits verification code → Retrieve secret → Validate
3. On success → Move secret to `users.totp_secret` in PostgreSQL
4. Secret expires after 10 minutes if not verified (security)

### 4.6 Redis High Availability Setup

**Deployment Mode**: Redis Sentinel (Master-Replica with Automatic Failover)

**Configuration**:
- **Master**: 1 instance (writes)
- **Replicas**: 2 instances (read scaling)
- **Sentinels**: 3 instances (quorum for failover)

**Kubernetes StatefulSet Example**:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
spec:
  serviceName: redis
  replicas: 3
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

**Connection Pooling**:
```rust
use redis::aio::ConnectionManager;

let redis_client = redis::Client::open("redis://redis-master:6379")?;
let conn_manager = ConnectionManager::new(redis_client).await?;
```

---

## 5. JWT Token Flow

### 5.1 Token Architecture

**Two-Token System**:
1. **Access Token** (JWT): Short-lived (1 hour), stateless, contains user claims
2. **Refresh Token** (Opaque UUID): Long-lived (30 days), stored in DB, used to issue new access tokens

**Why Two Tokens?**
- **Security**: Compromised access token has limited blast radius (1 hour)
- **Performance**: Access token validation is fast (signature check, no DB lookup)
- **Revocation**: Refresh tokens can be revoked in DB (logout, password change)

### 5.2 Access Token (JWT) Structure

**Algorithm**: RS256 (RSA Signature with SHA-256)

**Header**:
```json
{
  "alg": "RS256",
  "typ": "JWT",
  "kid": "nova-2025-10-17" // Key ID for rotation
}
```

**Payload (Claims)**:
```json
{
  "iss": "https://api.nova.example.com", // Issuer
  "sub": "550e8400-e29b-41d4-a716-446655440000", // Subject (user_id)
  "aud": "nova-mobile-app", // Audience (client app)
  "exp": 1729166400, // Expiration (Unix timestamp, 1 hour from iat)
  "iat": 1729162800, // Issued At
  "jti": "abc123def456", // JWT ID (unique identifier for blacklisting)
  "email": "alice@example.com",
  "username": "alice",
  "email_verified": true,
  "totp_enabled": false,
  "version": 1 // Token format version (future-proofing)
}
```

**Signature**:
```
RSASSA-PKCS1-v1_5(
  base64UrlEncode(header) + "." + base64UrlEncode(payload),
  privateKey
)
```

**Rust Implementation** (using `jsonwebtoken` crate):
```rust
use jsonwebtoken::{encode, decode, Header, Validation, EncodingKey, DecodingKey, Algorithm};
use serde::{Serialize, Deserialize};

#[derive(Debug, Serialize, Deserialize)]
struct Claims {
    iss: String,
    sub: String,
    aud: String,
    exp: usize,
    iat: usize,
    jti: String,
    email: String,
    username: String,
    email_verified: bool,
    totp_enabled: bool,
    version: u8,
}

fn generate_access_token(user: &User, private_key: &[u8]) -> Result<String, Error> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let claims = Claims {
        iss: "https://api.nova.example.com".to_string(),
        sub: user.id.to_string(),
        aud: "nova-mobile-app".to_string(),
        exp: (now + 3600) as usize, // 1 hour
        iat: now as usize,
        jti: Uuid::new_v4().to_string(),
        email: user.email.clone(),
        username: user.username.clone(),
        email_verified: user.email_verified_at.is_some(),
        totp_enabled: user.totp_enabled,
        version: 1,
    };

    let mut header = Header::new(Algorithm::RS256);
    header.kid = Some("nova-2025-10-17".to_string());

    encode(&header, &claims, &EncodingKey::from_rsa_pem(private_key)?)
}

fn validate_access_token(token: &str, public_key: &[u8]) -> Result<Claims, Error> {
    let mut validation = Validation::new(Algorithm::RS256);
    validation.set_audience(&["nova-mobile-app"]);
    validation.set_issuer(&["https://api.nova.example.com"]);

    let token_data = decode::<Claims>(token, &DecodingKey::from_rsa_pem(public_key)?, &validation)?;
    Ok(token_data.claims)
}
```

### 5.3 Refresh Token Structure

**Format**: Opaque UUID (e.g., `550e8400-e29b-41d4-a716-446655440000`)

**Storage**: PostgreSQL `auth_tokens` table (SHA-256 hash)

**Why Hash?**: Defense in depth (DB breach doesn't leak usable tokens)

**Generation**:
```rust
use uuid::Uuid;
use sha2::{Sha256, Digest};

fn generate_refresh_token() -> (String, String) {
    let token = Uuid::new_v4().to_string();
    let hash = format!("{:x}", Sha256::digest(token.as_bytes()));
    (token, hash) // Return plaintext + hash
}
```

**Validation**:
```rust
async fn validate_refresh_token(
    db: &PgPool,
    token: &str
) -> Result<User, Error> {
    let hash = format!("{:x}", Sha256::digest(token.as_bytes()));

    let token_record = sqlx::query!(
        "SELECT user_id, expires_at, revoked_at
         FROM auth_tokens
         WHERE token_hash = $1 AND token_type = 'refresh'",
        hash
    )
    .fetch_optional(db)
    .await?;

    let token_record = token_record.ok_or(Error::InvalidToken)?;

    if token_record.revoked_at.is_some() {
        return Err(Error::TokenRevoked);
    }

    if token_record.expires_at < Utc::now() {
        return Err(Error::TokenExpired);
    }

    let user = fetch_user_by_id(db, &token_record.user_id).await?;
    Ok(user)
}
```

### 5.4 Token Refresh Flow

**Sequence Diagram**:
```mermaid
sequenceDiagram
    participant Client as iOS App
    participant API as Auth Service
    participant DB as PostgreSQL
    participant Redis

    Client->>API: POST /v1/auth/refresh<br/>{refresh_token}
    API->>DB: Query auth_tokens by token_hash
    DB-->>API: Token record (user_id, expires_at)
    API->>API: Validate: not revoked, not expired
    API->>DB: Fetch user details
    DB-->>API: User (email, username, ...)
    API->>API: Generate new access token (JWT)
    opt Refresh Token Rotation
        API->>DB: Revoke old refresh token
        API->>API: Generate new refresh token
        API->>DB: Insert new refresh token
    end
    API-->>Client: {access_token, refresh_token}
```

**Refresh Token Rotation** (Optional but Recommended):
- On each refresh, issue new refresh token and revoke old one
- **Benefit**: Limits window for stolen tokens (compromised token only works once)
- **Trade-off**: Slightly higher DB load (1 extra write per refresh)

**Implementation**:
```rust
async fn refresh_access_token(
    db: &PgPool,
    old_refresh_token: &str,
    private_key: &[u8]
) -> Result<TokenPair, Error> {
    let user = validate_refresh_token(db, old_refresh_token).await?;

    // Generate new tokens
    let access_token = generate_access_token(&user, private_key)?;
    let (new_refresh_token, new_hash) = generate_refresh_token();

    // Revoke old token + insert new token (transaction)
    let old_hash = format!("{:x}", Sha256::digest(old_refresh_token.as_bytes()));
    sqlx::query!(
        "UPDATE auth_tokens SET revoked_at = NOW() WHERE token_hash = $1",
        old_hash
    )
    .execute(db)
    .await?;

    sqlx::query!(
        "INSERT INTO auth_tokens (user_id, token_hash, expires_at)
         VALUES ($1, $2, NOW() + INTERVAL '30 days')",
        user.id,
        new_hash
    )
    .execute(db)
    .await?;

    Ok(TokenPair {
        access_token,
        refresh_token: new_refresh_token,
    })
}
```

### 5.5 Token Validation Middleware

**Actix-web Middleware Example**:
```rust
use actix_web::{dev::ServiceRequest, Error, HttpMessage};
use actix_web_httpauth::extractors::bearer::BearerAuth;

async fn jwt_validator(
    req: ServiceRequest,
    credentials: BearerAuth,
) -> Result<ServiceRequest, Error> {
    let token = credentials.token();
    let public_key = &req.app_data::<PublicKey>().unwrap();
    let redis = &req.app_data::<RedisClient>().unwrap();

    // Validate JWT signature and claims
    let claims = validate_access_token(token, public_key)
        .map_err(|_| ErrorUnauthorized("Invalid token"))?;

    // Check token blacklist (logout)
    if is_token_blacklisted(redis, &claims.jti).await {
        return Err(ErrorUnauthorized("Token revoked"));
    }

    // Inject user context into request
    req.extensions_mut().insert(claims);
    Ok(req)
}
```

**Usage**:
```rust
use actix_web::{web, App, HttpResponse, HttpServer};
use actix_web_httpauth::middleware::HttpAuthentication;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        let auth_middleware = HttpAuthentication::bearer(jwt_validator);

        App::new()
            .route("/v1/auth/login", web::post().to(login_handler))
            .service(
                web::scope("/v1/protected")
                    .wrap(auth_middleware)
                    .route("/profile", web::get().to(get_profile))
            )
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}
```

### 5.6 Key Rotation Strategy

**Problem**: JWT private keys should be rotated periodically (every 6-12 months)

**Solution**: Key Versioning with `kid` (Key ID)

**Process**:
1. Generate new RSA key pair (2048-bit)
2. Add to key store with new `kid` (e.g., `nova-2025-04-17`)
3. Update token generation to use new key
4. **Keep old key for validation** (tokens signed with old key still valid until expiry)
5. After old tokens expire (1 hour), decommission old key

**JWKS Endpoint** (future enhancement):
```rust
#[derive(Serialize)]
struct JWK {
    kty: String, // "RSA"
    kid: String,
    use_: String, // "sig"
    n: String, // Modulus (base64url)
    e: String, // Exponent (base64url)
}

#[get("/v1/auth/.well-known/jwks.json")]
async fn jwks_endpoint() -> HttpResponse {
    let jwks = JWKSet {
        keys: vec![
            JWK { kid: "nova-2025-10-17", ... },
            JWK { kid: "nova-2025-04-17", ... }, // Old key (still valid)
        ],
    };
    HttpResponse::Ok().json(jwks)
}
```

---

## 6. OAuth2 Integration

### 6.1 OAuth2 Flow Overview

**Standard**: OAuth 2.0 Authorization Code Flow (RFC 6749)

**Supported Providers**:
1. **Apple Sign In** (mandatory for iOS apps per App Store guidelines)
2. **Google OAuth 2.0**
3. **Facebook Login**

**Flow Sequence**:
```mermaid
sequenceDiagram
    participant User as User (Browser)
    participant App as iOS App
    participant Auth as Auth Service
    participant Provider as OAuth Provider<br/>(Apple/Google/Facebook)
    participant DB as PostgreSQL

    User->>App: Tap "Continue with Apple"
    App->>Auth: GET /v1/auth/oauth/apple/login
    Auth->>Auth: Generate state (CSRF token)
    Auth->>Redis: Store state → user_session_id
    Auth-->>App: Redirect URL with state
    App->>Provider: Redirect to provider login page
    User->>Provider: Authenticate + authorize app
    Provider-->>App: Redirect to callback URL + code + state
    App->>Auth: POST /v1/auth/oauth/apple/callback<br/>{code, state}
    Auth->>Redis: Validate state matches session
    Auth->>Provider: Exchange code for access token
    Provider-->>Auth: Access token + user profile
    Auth->>DB: Check if oauth_connection exists
    alt User exists
        Auth->>Auth: Generate JWT tokens
    else New user
        Auth->>DB: Create user + oauth_connection
        Auth->>Auth: Generate JWT tokens
    end
    Auth-->>App: {access_token, refresh_token}
    App-->>User: Logged in
```

### 6.2 Apple Sign In Integration

**OAuth Provider**: `https://appleid.apple.com`

**Required Setup**:
1. Apple Developer account with App ID configured
2. Services ID for web authentication
3. Private key for JWT client secret generation

**Scopes**: `name email`

**Redirect URI**: `https://api.nova.example.com/v1/auth/oauth/apple/callback`

**Authorization URL**:
```
https://appleid.apple.com/auth/authorize?
  client_id=com.nova.app.services&
  redirect_uri=https://api.nova.example.com/v1/auth/oauth/apple/callback&
  response_type=code&
  scope=name%20email&
  state=<CSRF_TOKEN>&
  response_mode=form_post
```

**Token Exchange** (code → access token):
```rust
use reqwest::Client;
use serde::{Deserialize, Serialize};

#[derive(Serialize)]
struct AppleTokenRequest {
    client_id: String,
    client_secret: String, // JWT generated with Apple private key
    code: String,
    grant_type: String,
    redirect_uri: String,
}

#[derive(Deserialize)]
struct AppleTokenResponse {
    access_token: String,
    token_type: String,
    expires_in: u64,
    refresh_token: Option<String>,
    id_token: String, // JWT with user info
}

async fn exchange_apple_code(code: &str) -> Result<AppleTokenResponse, Error> {
    let client_secret = generate_apple_client_secret()?; // JWT with ES256 alg

    let client = Client::new();
    let response = client
        .post("https://appleid.apple.com/auth/token")
        .form(&AppleTokenRequest {
            client_id: "com.nova.app.services".to_string(),
            client_secret,
            code: code.to_string(),
            grant_type: "authorization_code".to_string(),
            redirect_uri: "https://api.nova.example.com/v1/auth/oauth/apple/callback".to_string(),
        })
        .send()
        .await?
        .json()
        .await?;

    Ok(response)
}
```

**User Profile Extraction**:
```rust
#[derive(Deserialize)]
struct AppleIdToken {
    sub: String, // Apple user ID
    email: String,
    email_verified: bool,
}

fn decode_apple_id_token(id_token: &str) -> Result<AppleIdToken, Error> {
    // Decode JWT (Apple public key from JWKS endpoint)
    let public_key = fetch_apple_public_key().await?;
    let token_data = decode::<AppleIdToken>(id_token, &public_key, &Validation::default())?;
    Ok(token_data.claims)
}
```

**Client Secret Generation** (Apple-specific):
```rust
use jsonwebtoken::{encode, Header, Algorithm, EncodingKey};

fn generate_apple_client_secret() -> Result<String, Error> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();
    let claims = serde_json::json!({
        "iss": "TEAM_ID", // Apple Team ID
        "iat": now,
        "exp": now + 15777000, // 6 months
        "aud": "https://appleid.apple.com",
        "sub": "com.nova.app.services" // Services ID
    });

    let header = Header::new(Algorithm::ES256);
    let private_key = std::fs::read("apple_auth_key.p8")?; // Downloaded from Apple
    encode(&header, &claims, &EncodingKey::from_ec_pem(&private_key)?)
}
```

### 6.3 Google OAuth Integration

**OAuth Provider**: `https://accounts.google.com`

**Required Setup**:
1. Google Cloud Console project
2. OAuth 2.0 Client ID (iOS + Web)
3. Enable Google+ API

**Scopes**: `openid email profile`

**Redirect URI**: `https://api.nova.example.com/v1/auth/oauth/google/callback`

**Authorization URL**:
```
https://accounts.google.com/o/oauth2/v2/auth?
  client_id=YOUR_CLIENT_ID.apps.googleusercontent.com&
  redirect_uri=https://api.nova.example.com/v1/auth/oauth/google/callback&
  response_type=code&
  scope=openid%20email%20profile&
  state=<CSRF_TOKEN>
```

**Token Exchange**:
```rust
#[derive(Serialize)]
struct GoogleTokenRequest {
    client_id: String,
    client_secret: String,
    code: String,
    grant_type: String,
    redirect_uri: String,
}

#[derive(Deserialize)]
struct GoogleTokenResponse {
    access_token: String,
    expires_in: u64,
    id_token: String,
    refresh_token: Option<String>,
}

async fn exchange_google_code(code: &str) -> Result<GoogleTokenResponse, Error> {
    let client = Client::new();
    let response = client
        .post("https://oauth2.googleapis.com/token")
        .json(&GoogleTokenRequest {
            client_id: env::var("GOOGLE_CLIENT_ID")?,
            client_secret: env::var("GOOGLE_CLIENT_SECRET")?,
            code: code.to_string(),
            grant_type: "authorization_code".to_string(),
            redirect_uri: "https://api.nova.example.com/v1/auth/oauth/google/callback".to_string(),
        })
        .send()
        .await?
        .json()
        .await?;

    Ok(response)
}
```

**User Profile**:
```rust
#[derive(Deserialize)]
struct GoogleUserInfo {
    sub: String, // Google user ID
    email: String,
    email_verified: bool,
    name: String,
    picture: String,
}

async fn fetch_google_user_info(access_token: &str) -> Result<GoogleUserInfo, Error> {
    let client = Client::new();
    let response = client
        .get("https://www.googleapis.com/oauth2/v3/userinfo")
        .bearer_auth(access_token)
        .send()
        .await?
        .json()
        .await?;

    Ok(response)
}
```

### 6.4 Facebook Login Integration

**OAuth Provider**: `https://www.facebook.com`

**Required Setup**:
1. Facebook App ID (from Facebook for Developers)
2. App Secret
3. Redirect URI whitelisted

**Scopes**: `email public_profile`

**Redirect URI**: `https://api.nova.example.com/v1/auth/oauth/facebook/callback`

**Authorization URL**:
```
https://www.facebook.com/v18.0/dialog/oauth?
  client_id=YOUR_APP_ID&
  redirect_uri=https://api.nova.example.com/v1/auth/oauth/facebook/callback&
  scope=email,public_profile&
  state=<CSRF_TOKEN>
```

**Token Exchange**:
```rust
async fn exchange_facebook_code(code: &str) -> Result<String, Error> {
    let client = Client::new();
    let response: serde_json::Value = client
        .get("https://graph.facebook.com/v18.0/oauth/access_token")
        .query(&[
            ("client_id", &env::var("FACEBOOK_APP_ID")?),
            ("client_secret", &env::var("FACEBOOK_APP_SECRET")?),
            ("code", &code.to_string()),
            ("redirect_uri", &"https://api.nova.example.com/v1/auth/oauth/facebook/callback".to_string()),
        ])
        .send()
        .await?
        .json()
        .await?;

    Ok(response["access_token"].as_str().unwrap().to_string())
}
```

**User Profile**:
```rust
#[derive(Deserialize)]
struct FacebookUserInfo {
    id: String, // Facebook user ID
    email: String,
    name: String,
    picture: serde_json::Value,
}

async fn fetch_facebook_user_info(access_token: &str) -> Result<FacebookUserInfo, Error> {
    let client = Client::new();
    let response = client
        .get("https://graph.facebook.com/v18.0/me")
        .query(&[
            ("fields", "id,email,name,picture"),
            ("access_token", access_token),
        ])
        .send()
        .await?
        .json()
        .await?;

    Ok(response)
}
```

### 6.5 Unified OAuth Provider Abstraction

**Trait Definition** (eliminate special cases):
```rust
#[async_trait]
trait OAuthProvider {
    fn provider_name(&self) -> &'static str;
    fn authorization_url(&self, state: &str) -> String;
    async fn exchange_code(&self, code: &str) -> Result<String, Error>; // Returns access token
    async fn fetch_user_profile(&self, access_token: &str) -> Result<OAuthUserProfile, Error>;
}

struct OAuthUserProfile {
    provider_user_id: String,
    email: String,
    email_verified: bool,
    name: Option<String>,
}

struct AppleOAuthProvider;
struct GoogleOAuthProvider;
struct FacebookOAuthProvider;

#[async_trait]
impl OAuthProvider for AppleOAuthProvider {
    fn provider_name(&self) -> &'static str { "apple" }
    // ... implement methods
}

// Same for Google, Facebook
```

**Usage**:
```rust
async fn handle_oauth_callback(
    provider: Box<dyn OAuthProvider>,
    code: &str,
    state: &str,
    db: &PgPool,
    redis: &RedisClient,
) -> Result<TokenPair, Error> {
    // Validate CSRF state
    validate_oauth_state(redis, state).await?;

    // Exchange code for access token
    let access_token = provider.exchange_code(code).await?;

    // Fetch user profile
    let profile = provider.fetch_user_profile(&access_token).await?;

    // Check if user exists
    let user = match find_oauth_connection(db, provider.provider_name(), &profile.provider_user_id).await? {
        Some(user) => user,
        None => create_user_from_oauth(db, provider.provider_name(), &profile).await?,
    };

    // Generate JWT tokens
    let access_token = generate_access_token(&user, &PRIVATE_KEY)?;
    let (refresh_token, hash) = generate_refresh_token();
    store_refresh_token(db, &user.id, &hash).await?;

    Ok(TokenPair { access_token, refresh_token })
}
```

### 6.6 Account Linking Strategy

**Scenario**: User registered with email, later wants to link Google account

**Flow**:
1. User logs in with email/password
2. Goes to Settings → Linked Accounts → "Connect Google"
3. Auth service redirects to Google OAuth (with `link_account=true` flag)
4. After Google auth, check if `oauth_connections` exists for Google ID
5. If not, insert new row with same `user_id`

**Conflict Handling**:
- **Email Match**: If Google email matches existing user email → Auto-link
- **Email Mismatch**: Prompt user "Link this Google account to your existing account?" (require password confirmation)
- **Duplicate OAuth**: If Google ID already linked to different user → Error "This Google account is already linked to another account"

**Code Example**:
```rust
async fn link_oauth_account(
    db: &PgPool,
    user_id: &Uuid,
    provider: &str,
    provider_user_id: &str,
    provider_email: &str,
) -> Result<(), Error> {
    // Check if this OAuth connection already exists for another user
    let existing = sqlx::query!(
        "SELECT user_id FROM oauth_connections WHERE provider = $1 AND provider_user_id = $2",
        provider,
        provider_user_id
    )
    .fetch_optional(db)
    .await?;

    if let Some(record) = existing {
        if &record.user_id != user_id {
            return Err(Error::OAuthAlreadyLinked);
        }
    }

    // Insert new OAuth connection
    sqlx::query!(
        "INSERT INTO oauth_connections (user_id, provider, provider_user_id, provider_email)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (provider, provider_user_id) DO NOTHING",
        user_id,
        provider,
        provider_user_id,
        provider_email
    )
    .execute(db)
    .await?;

    Ok(())
}
```

---

## 7. Security Implementation

### 7.1 Password Security

#### 7.1.1 Hashing Algorithm

**Algorithm**: bcrypt (cost factor 12)

**Why bcrypt?**
- **Adaptive**: Cost factor increases with hardware improvements
- **Salt Built-In**: Random salt generated per password
- **Slow**: Intentionally slow (100-300ms) to resist brute-force attacks

**Rust Implementation**:
```rust
use bcrypt::{hash, verify, DEFAULT_COST};

const BCRYPT_COST: u32 = 12;

fn hash_password(password: &str) -> Result<String, Error> {
    if password.len() < 8 || password.len() > 128 {
        return Err(Error::InvalidPasswordLength);
    }

    hash(password, BCRYPT_COST).map_err(|e| Error::HashingFailed(e))
}

fn verify_password(password: &str, hash: &str) -> Result<bool, Error> {
    verify(password, hash).map_err(|e| Error::VerificationFailed(e))
}
```

**Cost Factor Rationale**:
- **Cost 12**: ~300ms per hash on modern CPU (good balance between security and UX)
- **Cost 10**: ~75ms (too fast, vulnerable to GPU attacks)
- **Cost 14**: ~1.2s (too slow, poor user experience)

#### 7.1.2 Password Validation

**Strength Requirements** (FR-001):
- Minimum 8 characters, maximum 128 characters
- Must contain: uppercase letter, lowercase letter, digit, special character
- Not in common password list (e.g., "123456", "password")

**Validation Function**:
```rust
use regex::Regex;
use lazy_static::lazy_static;

lazy_static! {
    static ref PASSWORD_REGEX: Regex = Regex::new(
        r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&#])[A-Za-z\d@$!%*?&#]{8,128}$"
    ).unwrap();
}

const COMMON_PASSWORDS: &[&str] = &[
    "123456", "password", "12345678", "qwerty", "abc123",
    "monkey", "1234567", "letmein", "trustno1", "dragon"
];

fn validate_password_strength(password: &str) -> Result<(), Error> {
    if !PASSWORD_REGEX.is_match(password) {
        return Err(Error::WeakPassword);
    }

    if COMMON_PASSWORDS.contains(&password.to_lowercase().as_str()) {
        return Err(Error::CommonPassword);
    }

    Ok(())
}
```

#### 7.1.3 Password Reuse Prevention

**Requirement**: Check against last 3 passwords (FR-015)

**Implementation**:
```rust
async fn check_password_reuse(
    db: &PgPool,
    user_id: &Uuid,
    new_password: &str,
) -> Result<(), Error> {
    let history = sqlx::query!(
        "SELECT password_hash FROM password_history
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT 3",
        user_id
    )
    .fetch_all(db)
    .await?;

    for record in history {
        if verify_password(new_password, &record.password_hash)? {
            return Err(Error::PasswordReused);
        }
    }

    Ok(())
}

async fn update_password(
    db: &PgPool,
    user_id: &Uuid,
    new_password: &str,
) -> Result<(), Error> {
    validate_password_strength(new_password)?;
    check_password_reuse(db, user_id, new_password).await?;

    let new_hash = hash_password(new_password)?;

    // Get current password hash before updating
    let current_hash = sqlx::query_scalar!(
        "SELECT password_hash FROM users WHERE id = $1",
        user_id
    )
    .fetch_one(db)
    .await?;

    // Update password
    sqlx::query!(
        "UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2",
        new_hash,
        user_id
    )
    .execute(db)
    .await?;

    // Insert old password into history
    if let Some(old_hash) = current_hash {
        sqlx::query!(
            "INSERT INTO password_history (user_id, password_hash) VALUES ($1, $2)",
            user_id,
            old_hash
        )
        .execute(db)
        .await?;
    }

    Ok(())
}
```

### 7.2 HTTPS/TLS Enforcement

**Requirement**: TLS 1.3+ for all API communication (Constitution mandate)

**NGINX Configuration**:
```nginx
server {
    listen 80;
    server_name api.nova.example.com;
    return 301 https://$server_name$request_uri; # Force HTTPS
}

server {
    listen 443 ssl http2;
    server_name api.nova.example.com;

    # TLS 1.3 only
    ssl_protocols TLSv1.3;
    ssl_certificate /etc/nginx/certs/api.nova.example.com.crt;
    ssl_certificate_key /etc/nginx/certs/api.nova.example.com.key;

    # Modern cipher suites (TLS 1.3)
    ssl_ciphers 'TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256';
    ssl_prefer_server_ciphers off;

    # HSTS (force HTTPS for 1 year)
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Security headers
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        proxy_pass http://auth-service:8080;
    }
}
```

**Actix-web TLS Configuration** (for local testing):
```rust
use actix_web::{App, HttpServer};
use rustls::{Certificate, PrivateKey, ServerConfig};
use rustls_pemfile::{certs, pkcs8_private_keys};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let mut config = ServerConfig::builder()
        .with_safe_defaults()
        .with_no_client_auth()
        .with_single_cert(load_certs()?, load_private_key()?)
        .expect("Bad certificate/key");

    HttpServer::new(|| App::new().service(...))
        .bind_rustls("0.0.0.0:8443", config)?
        .run()
        .await
}

fn load_certs() -> std::io::Result<Vec<Certificate>> {
    let cert_file = &mut BufReader::new(File::open("cert.pem")?);
    Ok(certs(cert_file)?.into_iter().map(Certificate).collect())
}

fn load_private_key() -> std::io::Result<PrivateKey> {
    let key_file = &mut BufReader::new(File::open("key.pem")?);
    Ok(PrivateKey(pkcs8_private_keys(key_file)?.remove(0)))
}
```

### 7.3 CSRF Protection

**Attack Vector**: Malicious website tricks user's browser into making authenticated requests

**Mitigation**: `state` parameter in OAuth flows (already implemented)

**Additional Protection for Web Clients**:
```rust
use actix_web::{web, HttpRequest, HttpResponse};
use actix_web_csrf::{CsrfProtection, CsrfToken};

async fn protected_endpoint(
    req: HttpRequest,
    csrf: CsrfToken,
) -> HttpResponse {
    // CSRF token automatically validated by middleware
    HttpResponse::Ok().body("Success")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .wrap(CsrfProtection::default())
            .route("/api/protected", web::post().to(protected_endpoint))
    })
    .bind("0.0.0.0:8080")?
    .run()
    .await
}
```

### 7.4 Input Validation & Sanitization

**Validation Layers**:
1. **Schema Validation**: Use `serde` + custom validators
2. **Database Constraints**: NOT NULL, CHECK, UNIQUE
3. **Business Logic Validation**: Password strength, username format

**Example (Email Registration)**:
```rust
use validator::{Validate, ValidationError};
use serde::Deserialize;

#[derive(Debug, Deserialize, Validate)]
struct RegisterRequest {
    #[validate(email, length(max = 255))]
    email: String,

    #[validate(length(min = 8, max = 128), custom = "validate_password_strength")]
    password: String,

    #[validate(length(min = 3, max = 30), regex = "USERNAME_REGEX")]
    username: String,
}

fn validate_password_strength(password: &str) -> Result<(), ValidationError> {
    if !PASSWORD_REGEX.is_match(password) {
        return Err(ValidationError::new("weak_password"));
    }
    Ok(())
}

async fn register_handler(
    body: web::Json<RegisterRequest>,
) -> Result<HttpResponse, Error> {
    body.validate()?; // Automatic validation

    // Proceed with registration...
    Ok(HttpResponse::Created().json(...))
}
```

**SQL Injection Prevention**:
- **Parameterized Queries**: Use `sqlx` macros (compile-time checked)
- **ORM**: `sqlx::query!` prevents SQL injection by design

```rust
// ✅ Safe (parameterized)
sqlx::query!("SELECT * FROM users WHERE email = $1", email)
    .fetch_one(pool)
    .await?;

// ❌ Unsafe (string concatenation - NEVER DO THIS)
// let query = format!("SELECT * FROM users WHERE email = '{}'", email);
```

### 7.5 Secrets Management

**Requirement**: No secrets in code or version control (Constitution mandate)

**Strategy**: Environment variables + Secret management service

**Environment Variables** (.env file for local dev):
```bash
DATABASE_URL=postgresql://user:pass@localhost/nova_auth
REDIS_URL=redis://localhost:6379
JWT_PRIVATE_KEY_PATH=/secrets/jwt_private.pem
JWT_PUBLIC_KEY_PATH=/secrets/jwt_public.pem
GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=xxx
APPLE_TEAM_ID=ABCD123
APPLE_KEY_ID=XYZ789
FACEBOOK_APP_ID=123456789
FACEBOOK_APP_SECRET=xxx
EMAIL_SERVICE_API_KEY=sendgrid_api_key
```

**Production**: Kubernetes Secrets or AWS Secrets Manager
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: auth-service-secrets
type: Opaque
data:
  DATABASE_URL: <base64-encoded>
  JWT_PRIVATE_KEY: <base64-encoded>
  GOOGLE_CLIENT_SECRET: <base64-encoded>
```

**Loading Secrets** (Rust):
```rust
use std::env;

struct Config {
    database_url: String,
    jwt_private_key: Vec<u8>,
    google_client_secret: String,
}

fn load_config() -> Result<Config, Error> {
    dotenv::dotenv().ok(); // Load .env file in dev

    Ok(Config {
        database_url: env::var("DATABASE_URL")?,
        jwt_private_key: std::fs::read(env::var("JWT_PRIVATE_KEY_PATH")?)?,
        google_client_secret: env::var("GOOGLE_CLIENT_SECRET")?,
    })
}
```

### 7.6 Audit Logging

**Requirement**: Log all authentication events (FR-013)

**Events to Log**:
- Registration, email verification
- Login (success/failure), logout
- Password reset (requested/completed)
- 2FA enable/disable
- OAuth connections
- Account deletion

**Implementation**:
```rust
async fn log_auth_event(
    db: &PgPool,
    user_id: Option<&Uuid>,
    event_type: &str,
    ip_address: &str,
    user_agent: &str,
    success: bool,
    failure_reason: Option<&str>,
) -> Result<(), Error> {
    sqlx::query!(
        "INSERT INTO auth_logs (user_id, event_type, ip_address, user_agent, success, failure_reason)
         VALUES ($1, $2, $3::inet, $4, $5, $6)",
        user_id,
        event_type,
        ip_address,
        user_agent,
        success,
        failure_reason
    )
    .execute(db)
    .await?;

    Ok(())
}
```

**Usage**:
```rust
async fn login_handler(
    req: HttpRequest,
    body: web::Json<LoginRequest>,
    db: web::Data<PgPool>,
) -> Result<HttpResponse, Error> {
    let ip = req.connection_info().realip_remote_addr().unwrap_or("unknown");
    let user_agent = req.headers().get("user-agent").and_then(|v| v.to_str().ok()).unwrap_or("unknown");

    match authenticate_user(&db, &body.email, &body.password).await {
        Ok(user) => {
            log_auth_event(&db, Some(&user.id), "login_success", ip, user_agent, true, None).await?;
            // Generate tokens...
        }
        Err(e) => {
            log_auth_event(&db, None, "login_failed", ip, user_agent, false, Some("invalid_credentials")).await?;
            return Err(e);
        }
    }

    Ok(HttpResponse::Ok().json(...))
}
```

**Log Retention**: Archive logs older than 90 days (GDPR compliance)

```sql
-- Scheduled job (cron)
DELETE FROM auth_logs WHERE created_at < NOW() - INTERVAL '90 days';
```

---

## 8. Test Strategy (TDD)

### 8.1 TDD Cycle (Red-Green-Refactor)

**Principle**: Write tests BEFORE implementation code (Constitution mandate)

**Workflow**:
1. **Red**: Write a failing test that defines desired behavior
2. **Green**: Write minimal code to make the test pass
3. **Refactor**: Improve code quality without changing behavior (all tests still pass)
4. **Repeat**: Add next test case

**Example (Password Hashing)**:

**Step 1 - Red (Failing Test)**:
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_password_returns_different_hash() {
        let password = "StrongP@ssw0rd!";
        let hash1 = hash_password(password).unwrap();
        let hash2 = hash_password(password).unwrap();

        assert_ne!(hash1, hash2, "Hashes should differ due to random salt");
        assert!(hash1.starts_with("$2b$12$"), "Should use bcrypt cost 12");
    }
}
```

**Step 2 - Green (Implementation)**:
```rust
fn hash_password(password: &str) -> Result<String, Error> {
    bcrypt::hash(password, 12).map_err(|e| Error::HashingFailed(e))
}
```

**Step 3 - Refactor (Add validation)**:
```rust
fn hash_password(password: &str) -> Result<String, Error> {
    if password.len() < 8 {
        return Err(Error::InvalidPasswordLength);
    }
    bcrypt::hash(password, BCRYPT_COST).map_err(|e| Error::HashingFailed(e))
}

#[test]
fn test_hash_password_rejects_short_password() {
    let result = hash_password("short");
    assert!(result.is_err());
}
```

### 8.2 Test Pyramid

**Target Coverage**: 80% minimum for business logic (Constitution mandate)

**Test Distribution**:
- **70% Unit Tests**: Fast, isolated, cover all edge cases
- **20% Integration Tests**: Database, Redis, HTTP endpoints
- **10% End-to-End Tests**: Full user flows (register → verify → login)

```
       /\
      /  \  E2E Tests (Slow, Expensive)
     /    \
    /------\
   / Integ. \ Integration Tests (Moderate)
  /----------\
 /   Unit     \ Unit Tests (Fast, Cheap)
/--------------\
```

### 8.3 Unit Tests

**Scope**: Test individual functions in isolation (no I/O, no DB)

**Tools**: `cargo test`, `mockall` for mocking

**Example (Password Validation)**:
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_password_strength_accepts_strong_password() {
        assert!(validate_password_strength("StrongP@ssw0rd!").is_ok());
    }

    #[test]
    fn test_validate_password_strength_rejects_short_password() {
        let result = validate_password_strength("Short1!");
        assert!(result.is_err());
    }

    #[test]
    fn test_validate_password_strength_rejects_no_uppercase() {
        let result = validate_password_strength("weakp@ssw0rd");
        assert!(result.is_err());
    }

    #[test]
    fn test_validate_password_strength_rejects_common_password() {
        let result = validate_password_strength("password");
        assert!(result.is_err());
    }

    #[test]
    fn test_generate_refresh_token_returns_uuid_and_hash() {
        let (token, hash) = generate_refresh_token();
        assert_eq!(token.len(), 36); // UUID v4 length
        assert_eq!(hash.len(), 64); // SHA-256 hex length
        assert_ne!(token, hash);
    }
}
```

**Mocking External Dependencies**:
```rust
use mockall::predicate::*;
use mockall::mock;

mock! {
    RedisClient {
        async fn incr(&self, key: &str) -> Result<u32, Error>;
        async fn expire(&self, key: &str, ttl: u64) -> Result<(), Error>;
    }
}

#[tokio::test]
async fn test_rate_limiting_increments_counter() {
    let mut mock_redis = MockRedisClient::new();
    mock_redis
        .expect_incr()
        .with(eq("rate_limit:login:alice@example.com"))
        .times(1)
        .returning(|_| Ok(1));

    mock_redis
        .expect_expire()
        .times(1)
        .returning(|_, _| Ok(()));

    let result = check_rate_limit(&mock_redis, "alice@example.com").await;
    assert!(result.is_ok());
}
```

### 8.4 Integration Tests

**Scope**: Test API endpoints with real database and Redis (isolated test environment)

**Tools**: `actix-web::test`, `testcontainers-rs` (spin up PostgreSQL/Redis in Docker)

**Setup**:
```rust
use testcontainers::{clients, images};
use sqlx::PgPool;

async fn setup_test_db() -> PgPool {
    let docker = clients::Cli::default();
    let postgres_image = images::postgres::Postgres::default();
    let node = docker.run(postgres_image);

    let connection_string = format!(
        "postgresql://postgres:postgres@127.0.0.1:{}/postgres",
        node.get_host_port_ipv4(5432)
    );

    let pool = PgPool::connect(&connection_string).await.unwrap();

    // Run migrations
    sqlx::migrate!("./migrations").run(&pool).await.unwrap();

    pool
}

#[actix_web::test]
async fn test_register_endpoint_creates_user() {
    let pool = setup_test_db().await;
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .route("/v1/auth/register", web::post().to(register_handler))
    ).await;

    let req = test::TestRequest::post()
        .uri("/v1/auth/register")
        .set_json(&serde_json::json!({
            "email": "test@example.com",
            "password": "StrongP@ss1!",
            "username": "testuser"
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), StatusCode::CREATED);

    // Verify user exists in database
    let user = sqlx::query!("SELECT * FROM users WHERE email = $1", "test@example.com")
        .fetch_one(&pool)
        .await
        .unwrap();

    assert_eq!(user.username, "testuser");
    assert!(user.email_verified_at.is_none());
}
```

### 8.5 End-to-End Tests

**Scope**: Test complete user flows across multiple endpoints

**Tools**: `reqwest` for HTTP client, `testcontainers` for infrastructure

**Example (Full Registration Flow)**:
```rust
#[tokio::test]
async fn test_full_registration_and_login_flow() {
    // Setup test environment
    let (pool, redis) = setup_test_environment().await;
    let base_url = "http://localhost:8080";

    // 1. Register user
    let client = reqwest::Client::new();
    let resp = client.post(&format!("{}/v1/auth/register", base_url))
        .json(&serde_json::json!({
            "email": "alice@example.com",
            "password": "StrongP@ss1!",
            "username": "alice"
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let body: serde_json::Value = resp.json().await.unwrap();
    let user_id = body["user_id"].as_str().unwrap();

    // 2. Verify email (simulate clicking link)
    let verification_token = get_verification_token_from_redis(&redis, user_id).await;
    let resp = client.post(&format!("{}/v1/auth/verify-email", base_url))
        .json(&serde_json::json!({ "token": verification_token }))
        .send()
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);

    // 3. Login
    let resp = client.post(&format!("{}/v1/auth/login", base_url))
        .json(&serde_json::json!({
            "email": "alice@example.com",
            "password": "StrongP@ss1!"
        }))
        .send()
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value = resp.json().await.unwrap();
    assert!(body["access_token"].is_string());
    assert!(body["refresh_token"].is_string());
}
```

### 8.6 Security Tests

**Scope**: Test vulnerabilities and attack scenarios

**Test Cases**:
1. **Rate Limiting**: Verify account lock after 5 failed logins
2. **SQL Injection**: Send malicious input (e.g., `' OR '1'='1`)
3. **XSS**: Send script tags in username/email
4. **JWT Tampering**: Modify JWT payload and verify rejection
5. **CSRF**: Send OAuth callback without valid `state` parameter

**Example (Rate Limiting Test)**:
```rust
#[actix_web::test]
async fn test_rate_limiting_blocks_after_5_attempts() {
    let pool = setup_test_db().await;
    let redis = setup_test_redis().await;
    let app = setup_app(pool, redis).await;

    let email = "victim@example.com";
    let wrong_password = "WrongPassword123!";

    // Attempt login 5 times with wrong password
    for _ in 0..5 {
        let req = test::TestRequest::post()
            .uri("/v1/auth/login")
            .set_json(&serde_json::json!({
                "email": email,
                "password": wrong_password
            }))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    }

    // 6th attempt should be blocked
    let req = test::TestRequest::post()
        .uri("/v1/auth/login")
        .set_json(&serde_json::json!({
            "email": email,
            "password": wrong_password
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), StatusCode::FORBIDDEN); // Account locked
}
```

**SQL Injection Test**:
```rust
#[actix_web::test]
async fn test_sql_injection_is_prevented() {
    let pool = setup_test_db().await;
    let app = setup_app(pool).await;

    // Attempt SQL injection in email field
    let req = test::TestRequest::post()
        .uri("/v1/auth/login")
        .set_json(&serde_json::json!({
            "email": "admin@example.com' OR '1'='1",
            "password": "anything"
        }))
        .to_request();

    let resp = test::call_service(&app, req).await;

    // Should fail validation, not succeed with SQL injection
    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
}
```

### 8.7 Test Coverage Reporting

**Tool**: `cargo-tarpaulin` (code coverage for Rust)

**Installation**:
```bash
cargo install cargo-tarpaulin
```

**Run Tests with Coverage**:
```bash
cargo tarpaulin --out Xml --output-dir ./coverage
```

**CI/CD Integration** (GitHub Actions):
```yaml
name: Test Coverage

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
      - name: Run tests with coverage
        run: cargo tarpaulin --out Xml --output-dir ./coverage
      - name: Upload coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage/cobertura.xml
      - name: Check coverage threshold
        run: |
          COVERAGE=$(grep -oP 'line-rate="\K[^"]+' coverage/cobertura.xml | head -1)
          if (( $(echo "$COVERAGE < 0.80" | bc -l) )); then
            echo "Coverage $COVERAGE is below 80% threshold"
            exit 1
          fi
```

---

## 9. Implementation Phases

### 9.1 Phase Breakdown

**Principle**: Ship incrementally, validate early (avoid big-bang integration)

#### Phase 1: Core Email Authentication (Priority P1) - **Weeks 1-2**

**Deliverables**:
- ✅ PostgreSQL schema (users, auth_tokens, auth_logs tables)
- ✅ Redis setup (rate limiting, email verification tokens)
- ✅ User registration endpoint (POST /v1/auth/register)
- ✅ Email verification endpoint (POST /v1/auth/verify-email)
- ✅ Login endpoint (POST /v1/auth/login)
- ✅ Logout endpoint (POST /v1/auth/logout)
- ✅ JWT token generation/validation
- ✅ bcrypt password hashing
- ✅ Rate limiting (5 attempts per 15 min)
- ✅ Unit tests (80% coverage for auth logic)
- ✅ Integration tests (API endpoints)

**Testing Checkpoint**:
- User can register → verify email → log in → log out
- Failed login attempts trigger rate limiting
- Passwords are hashed (verify in DB: no plaintext)
- JWT tokens are valid and expire after 1 hour

**Dependencies**: None (standalone)

---

#### Phase 2: Password Reset (Priority P1) - **Week 3**

**Deliverables**:
- ✅ Password reset request endpoint (POST /v1/auth/password-reset)
- ✅ Password reset confirmation endpoint (POST /v1/auth/password-reset/confirm)
- ✅ `password_reset_tokens` table
- ✅ `password_history` table (prevent reuse)
- ✅ Email event publishing (async via Kafka/RabbitMQ)
- ✅ Integration tests (full reset flow)

**Testing Checkpoint**:
- User requests reset → receives email → resets password → logs in with new password
- Old passwords cannot be reused (last 3 checked)
- Expired tokens (>1 hour) are rejected

**Dependencies**: Email Service (can be mocked initially)

---

#### Phase 3: OAuth2 Integration (Priority P2) - **Weeks 4-5**

**Deliverables**:
- ✅ `oauth_connections` table
- ✅ OAuth provider abstraction (`OAuthProvider` trait)
- ✅ Apple Sign In implementation
- ✅ Google OAuth implementation
- ✅ Facebook OAuth implementation
- ✅ OAuth callback endpoints (POST /v1/auth/oauth/{provider}/callback)
- ✅ Account linking logic (handle email conflicts)
- ✅ CSRF protection (state parameter validation)
- ✅ Integration tests (mock OAuth provider responses)

**Testing Checkpoint**:
- User can log in with Apple/Google/Facebook
- OAuth account can be linked to existing email account
- Email conflicts are handled (prompt user to link or create new account)
- CSRF attacks are blocked (invalid state parameter rejected)

**Dependencies**: OAuth provider accounts (Apple Developer, Google Cloud, Facebook for Developers)

---

#### Phase 4: Two-Factor Authentication (Priority P3) - **Week 6**

**Deliverables**:
- ✅ TOTP secret generation (Base32-encoded)
- ✅ 2FA enable endpoint (POST /v1/auth/2fa/enable)
- ✅ 2FA verify endpoint (POST /v1/auth/2fa/verify)
- ✅ 2FA disable endpoint (POST /v1/auth/2fa/disable)
- ✅ Login flow modification (require TOTP code if enabled)
- ✅ Backup codes generation (10 codes, stored as hashes in Redis)
- ✅ Unit tests (TOTP validation)
- ✅ Integration tests (enable 2FA → log out → log in with code)

**Testing Checkpoint**:
- User enables 2FA → scans QR code → verifies with authenticator app
- Login requires 6-digit TOTP code when 2FA enabled
- Backup codes work as fallback (one-time use)
- 2FA can be disabled with password confirmation

**Dependencies**: None (standalone)

---

#### Phase 5: Production Hardening (Priority P1) - **Week 7**

**Deliverables**:
- ✅ HTTPS/TLS 1.3 configuration (NGINX or load balancer)
- ✅ Security headers (HSTS, CSP, X-Frame-Options)
- ✅ Database connection pooling (PgBouncer)
- ✅ Redis Sentinel setup (HA)
- ✅ Kubernetes deployment manifests (StatefulSet, Service, Ingress)
- ✅ Health check endpoints (/health, /readiness)
- ✅ Prometheus metrics (request latency, error rates, active users)
- ✅ Centralized logging (stdout → Fluentd → Elasticsearch)
- ✅ Load testing (simulate 1,000 concurrent logins)
- ✅ Security audit (OWASP Top 10 checklist)

**Testing Checkpoint**:
- Service handles 1,000 concurrent login requests (<200ms p95 latency)
- No critical vulnerabilities in security scan
- All endpoints return security headers
- Health checks pass (database, Redis connectivity)

**Dependencies**: Infrastructure team (Kubernetes cluster, monitoring stack)

---

### 9.2 Dependency Graph

```mermaid
graph TD
    Phase1[Phase 1: Email Auth]
    Phase2[Phase 2: Password Reset]
    Phase3[Phase 3: OAuth2]
    Phase4[Phase 4: 2FA]
    Phase5[Phase 5: Production]

    Phase1 --> Phase2
    Phase1 --> Phase3
    Phase1 --> Phase4
    Phase2 --> Phase5
    Phase3 --> Phase5
    Phase4 --> Phase5

    style Phase1 fill:#90EE90
    style Phase2 fill:#87CEEB
    style Phase3 fill:#FFD700
    style Phase4 fill:#FFA07A
    style Phase5 fill:#FF6347
```

**Parallel Development**:
- Phase 2, 3, 4 can be developed in parallel after Phase 1 completes
- Phase 5 waits for all features to be complete

---

### 9.3 Testing Checkpoints

**After Each Phase**:
1. **Run Full Test Suite**: `cargo test --all`
2. **Check Coverage**: Ensure ≥80% coverage (`cargo tarpaulin`)
3. **Manual QA**: Test happy path + edge cases via Postman/curl
4. **Security Review**: Check for exposed secrets, SQL injection, XSS
5. **Performance Benchmark**: Measure API latency (autocannon, wrk)

**Phase 1 Benchmark**:
```bash
# Install autocannon
npm install -g autocannon

# Test login endpoint (100 concurrent connections, 10 seconds)
autocannon -c 100 -d 10 -m POST \
  -H "Content-Type: application/json" \
  -b '{"email":"test@example.com","password":"StrongP@ss1!"}' \
  http://localhost:8080/v1/auth/login
```

**Expected Results**:
- Latency p95: <200ms
- Throughput: >500 req/sec
- Error rate: <1%

---

## 10. Operational Considerations

### 10.1 Deployment Architecture

**Kubernetes Deployment** (3 replicas for HA):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  labels:
    app: auth-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
    spec:
      containers:
      - name: auth-service
        image: nova/auth-service:v1.0.0
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: auth-service-secrets
              key: DATABASE_URL
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: auth-service-secrets
              key: REDIS_URL
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /readiness
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: auth-service
spec:
  selector:
    app: auth-service
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
  type: ClusterIP
```

**Health Check Endpoints**:
```rust
#[get("/health")]
async fn health_check() -> HttpResponse {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "ok",
        "timestamp": Utc::now().to_rfc3339()
    }))
}

#[get("/readiness")]
async fn readiness_check(
    db: web::Data<PgPool>,
    redis: web::Data<RedisClient>,
) -> HttpResponse {
    // Check database connectivity
    if sqlx::query("SELECT 1").fetch_one(db.get_ref()).await.is_err() {
        return HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "not ready",
            "reason": "database unavailable"
        }));
    }

    // Check Redis connectivity
    if redis.ping().await.is_err() {
        return HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "not ready",
            "reason": "redis unavailable"
        }));
    }

    HttpResponse::Ok().json(serde_json::json!({
        "status": "ready"
    }))
}
```

### 10.2 Monitoring & Alerting

**Prometheus Metrics**:
```rust
use prometheus::{IntCounter, Histogram, register_int_counter, register_histogram};

lazy_static! {
    static ref LOGIN_ATTEMPTS: IntCounter = register_int_counter!(
        "auth_login_attempts_total",
        "Total number of login attempts"
    ).unwrap();

    static ref LOGIN_FAILURES: IntCounter = register_int_counter!(
        "auth_login_failures_total",
        "Total number of failed login attempts"
    ).unwrap();

    static ref REQUEST_DURATION: Histogram = register_histogram!(
        "auth_request_duration_seconds",
        "Request duration in seconds"
    ).unwrap();
}

async fn login_handler(...) -> Result<HttpResponse, Error> {
    let timer = REQUEST_DURATION.start_timer();
    LOGIN_ATTEMPTS.inc();

    let result = authenticate_user(...).await;

    if result.is_err() {
        LOGIN_FAILURES.inc();
    }

    timer.observe_duration();
    result
}
```

**Grafana Dashboard** (key metrics):
- **Request Rate**: Login, registration, refresh token requests/sec
- **Error Rate**: 4xx/5xx errors per endpoint
- **Latency**: p50, p95, p99 response times
- **Active Sessions**: Count of valid refresh tokens
- **Rate Limit Hits**: Number of blocked requests

**Alerting Rules** (Prometheus):
```yaml
groups:
- name: auth_service_alerts
  rules:
  - alert: HighLoginFailureRate
    expr: rate(auth_login_failures_total[5m]) > 10
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High login failure rate detected"
      description: "Login failure rate is {{ $value }} per second"

  - alert: ServiceDown
    expr: up{job="auth-service"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Auth service is down"
      description: "Auth service has been down for more than 1 minute"
```

### 10.3 Database Maintenance

**Connection Pooling** (PgBouncer):
```ini
[databases]
nova_auth = host=postgres-master port=5432 dbname=nova_auth

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
```

**Backup Strategy**:
- **Daily Full Backup**: PostgreSQL `pg_dump` to S3
- **Continuous WAL Archiving**: Point-in-time recovery (PITR)
- **Retention**: 30 days (GDPR compliance)

**Index Maintenance**:
```sql
-- Weekly VACUUM (reclaim storage, update statistics)
VACUUM ANALYZE users;
VACUUM ANALYZE auth_tokens;
VACUUM ANALYZE auth_logs;

-- Monitor index bloat
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

**Cleanup Jobs** (cron):
```bash
# Delete expired tokens (runs daily)
0 2 * * * psql -d nova_auth -c "DELETE FROM auth_tokens WHERE expires_at < NOW()"

# Archive old auth logs (runs weekly)
0 3 * * 0 psql -d nova_auth -c "DELETE FROM auth_logs WHERE created_at < NOW() - INTERVAL '90 days'"
```

### 10.4 Disaster Recovery

**Runbook - Database Failure**:
1. Check PostgreSQL master status: `kubectl get pods -l app=postgres`
2. If master down, promote replica to master (automatic with Patroni)
3. Update `DATABASE_URL` in auth-service secrets to point to new master
4. Restart auth-service pods: `kubectl rollout restart deployment/auth-service`

**Runbook - Redis Failure**:
1. Check Redis Sentinel status: `redis-cli -p 26379 SENTINEL masters`
2. If master down, Sentinel auto-promotes replica (30-second failover)
3. Auth service reconnects automatically (connection manager handles failover)
4. Verify rate limiting works: `curl -X POST https://api.nova.example.com/v1/auth/login` (6 attempts should be blocked)

**Runbook - JWT Key Compromise**:
1. Generate new RSA key pair: `openssl genrsa -out new_private.pem 2048`
2. Update `JWT_PRIVATE_KEY` in secrets
3. Rolling restart auth-service pods (zero downtime)
4. Old tokens remain valid until expiry (1 hour max)
5. Force logout all users (optional): `UPDATE auth_tokens SET revoked_at = NOW()`

---

## Conclusion

This technical plan provides a comprehensive blueprint for implementing the User Authentication Service following TDD principles, microservices architecture, and security best practices aligned with the Project Constitution.

**Next Steps**:
1. **Review & Approval**: Stakeholder sign-off on architecture decisions
2. **Environment Setup**: Provision Kubernetes cluster, PostgreSQL, Redis
3. **Kickoff Phase 1**: Begin with failing tests for user registration endpoint
4. **Daily Stand-ups**: Track progress against phase milestones
5. **Weekly Demos**: Show working features to stakeholders

**Key Success Metrics**:
- ✅ All phases completed on schedule (7 weeks)
- ✅ 80%+ test coverage achieved
- ✅ Zero critical security vulnerabilities
- ✅ <200ms p95 latency for login endpoint
- ✅ 99.9% uptime in production

---

**Document Metadata**:
- **Version**: 1.0.0
- **Author**: Backend Architecture Team
- **Last Updated**: 2025-10-17
- **Related Documents**:
  - [Specification](./spec.md)
  - [Project Constitution](../../.specify/memory/constitution.md)
  - [API Reference](./api-reference.md) (to be generated)
