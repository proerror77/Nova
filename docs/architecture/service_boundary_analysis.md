# Service Boundary Analysis: auth-service vs user-service

> **Created**: 2025-11-07
> **Status**: 🔴 Critical - Service Boundary Confusion
> **Issue**: Duplicate UpdateUserProfile violates Single Writer Pattern

## Executive Summary

### Critical Issues Found

1. **❌ Duplicate UpdateUserProfile RPC**
   - `auth_service.proto:165-192` - UpdateUserProfile
   - `user_service.proto:91-104` - UpdateUserProfile
   - **Violates**: Single Writer Pattern (两个服务都可以写用户 profile)
   - **Impact**: Data consistency risk, race conditions

2. **❌ Public Key Management Misplaced**
   - `auth_service.proto:198-216` - UpsertUserPublicKey, GetUserPublicKey
   - **Should be in**: user-service or messaging-service
   - **Reason**: Public keys are profile metadata, not authentication data

3. **❌ User Query Responsibility Unclear**
   - auth-service: GetUser, GetUsersByIds, ListUsers, GetUserByEmail
   - user-service: GetUserProfile, GetUserProfilesByIds, SearchUsers
   - **Confusion**: Which service should clients call?

---

## Current State

### auth-service (auth_service.proto)

**Correctly Placed RPCs** ✅:
- `Register` - Create new user account
- `Login` - Authenticate user
- `Refresh` - Refresh access token
- `VerifyToken` - Validate JWT token
- `CheckUserExists` - Verify user existence (for FK validation)
- `CheckPermission` - Check user permissions
- `GetUserPermissions` - Get user roles/permissions
- `RecordFailedLogin` - Track failed login attempts
- `GetUser` - Read-only basic user data
- `GetUsersByIds` - Batch read-only user data
- `GetUserByEmail` - Lookup user by email

**Incorrectly Placed RPCs** ❌:
- `UpdateUserProfile` - **Should be in user-service**
- `UpsertUserPublicKey` - **Should be in user-service or messaging-service**
- `GetUserPublicKey` - **Should be in user-service or messaging-service**
- `ListUsers` - **Could move to user-service (overlaps with SearchUsers)**

---

### user-service (user_service.proto)

**Correctly Placed RPCs** ✅:
- `GetUserProfile` - Read user profile
- `GetUserProfilesByIds` - Batch read user profiles
- `UpdateUserProfile` - **✅ Correct owner of profile updates**
- `GetUserSettings` - Read user preferences
- `UpdateUserSettings` - Update user preferences
- `FollowUser` - Create follow relationship
- `UnfollowUser` - Remove follow relationship
- `BlockUser` - Block user
- `UnblockUser` - Unblock user
- `GetUserFollowers` - Get followers list
- `GetUserFollowing` - Get following list
- `CheckUserRelationship` - Check relationship between users
- `SearchUsers` - Search users by name

**Missing RPCs** ⚠️:
- `UpsertUserPublicKey` - Should be added here
- `GetUserPublicKey` - Should be added here

---

## Recommended Service Boundaries

### auth-service: Authentication & Authorization ONLY

**Core Principle**: auth-service owns the `users` table and provides **read-only** access to basic user data for other services.

**Responsibilities**:
```
✅ Authentication:
   - Register (write)
   - Login (write)
   - Refresh (write)
   - VerifyToken (read)

✅ Authorization:
   - CheckPermission (read)
   - GetUserPermissions (read)

✅ Account Security:
   - RecordFailedLogin (write)

✅ User Data Access (READ-ONLY):
   - GetUser (read)
   - GetUsersByIds (read)
   - GetUserByEmail (read)
   - CheckUserExists (read) - for FK validation

❌ Remove:
   - UpdateUserProfile → Move to user-service
   - UpsertUserPublicKey → Move to user-service
   - GetUserPublicKey → Move to user-service
   - ListUsers → Move to user-service (overlaps with SearchUsers)
```

---

### user-service: User Profiles & Social Graph

**Core Principle**: user-service owns **mutable profile data** and **social relationships**.

**Responsibilities**:
```
✅ Profile Management (SINGLE WRITER):
   - GetUserProfile (read)
   - GetUserProfilesByIds (read)
   - UpdateUserProfile (write) ← PRIMARY WRITER
   - SearchUsers (read)

✅ User Settings:
   - GetUserSettings (read)
   - UpdateUserSettings (write)

✅ Social Relationships:
   - FollowUser (write)
   - UnfollowUser (write)
   - BlockUser (write)
   - UnblockUser (write)
   - GetUserFollowers (read)
   - GetUserFollowing (read)
   - CheckUserRelationship (read)

✅ E2EE Key Management (MOVE FROM auth-service):
   - UpsertUserPublicKey (write)
   - GetUserPublicKey (read)
```

---

## Migration Plan

### Phase 1: Add Missing RPCs to user-service

```protobuf
// Add to user_service.proto
message UpsertUserPublicKeyRequest {
  string user_id = 1;
  string public_key = 2;
}

message UpsertUserPublicKeyResponse {
  bool success = 1;
}

message GetUserPublicKeyRequest {
  string user_id = 1;
}

message GetUserPublicKeyResponse {
  bool found = 1;
  optional string public_key = 2;
}

service UserService {
  // ... existing RPCs ...

  // E2EE key management (migrated from auth-service)
  rpc UpsertUserPublicKey(UpsertUserPublicKeyRequest) returns (UpsertUserPublicKeyResponse);
  rpc GetUserPublicKey(GetUserPublicKeyRequest) returns (GetUserPublicKeyResponse);
}
```

### Phase 2: Deprecate auth-service Profile Management

```protobuf
// Mark as deprecated in auth_service.proto
service AuthService {
  // ... existing auth RPCs ...

  // DEPRECATED: Use user-service.UpdateUserProfile instead
  rpc UpdateUserProfile(UpdateUserProfileRequest) returns (UpdateUserProfileResponse) {
    option deprecated = true;
  };

  // DEPRECATED: Use user-service.UpsertUserPublicKey instead
  rpc UpsertUserPublicKey(UpsertUserPublicKeyRequest) returns (UpsertUserPublicKeyResponse) {
    option deprecated = true;
  };

  // DEPRECATED: Use user-service.GetUserPublicKey instead
  rpc GetUserPublicKey(GetUserPublicKeyRequest) returns (GetUserPublicKeyResponse) {
    option deprecated = true;
  };
}
```

### Phase 3: Migrate Clients

**Update all services that currently call**:
- `auth_client.update_user_profile()` → `user_client.update_user_profile()`
- `auth_client.upsert_user_public_key()` → `user_client.upsert_user_public_key()`
- `auth_client.get_user_public_key()` → `user_client.get_user_public_key()`

**Services to update**:
- content-service
- messaging-service
- feed-service
- media-service

### Phase 4: Remove Deprecated RPCs

After all clients migrated (verified by monitoring):
```bash
# Remove from auth_service.proto
- UpdateUserProfile
- UpsertUserPublicKey
- GetUserPublicKey
```

---

## Service Communication Matrix

### Who calls whom (AFTER migration)

```
┌─────────────────┐
│  API Gateway    │
└────────┬────────┘
         │
    ┌────┴────┬──────────────────┐
    │         │                  │
┌───▼───┐  ┌──▼──────┐  ┌───────▼────────┐
│ auth  │  │  user   │  │   content      │
│service│  │ service │  │   service      │
└───┬───┘  └──┬──────┘  └────────────────┘
    │         │
    │    ┌────▼───────────────────┐
    │    │ GetUserProfile         │
    │    │ UpdateUserProfile      │ ← SINGLE WRITER
    │    │ UpsertUserPublicKey    │
    │    └────────────────────────┘
    │
    └──► CheckUserExists (for FK validation)
```

### Read vs Write Paths

**User Profile Writes** (SINGLE PATH):
```
Client → user-service.UpdateUserProfile → users table (via auth-service gRPC)
```

**User Profile Reads** (MULTIPLE PATHS):
```
Option 1: Client → user-service.GetUserProfile → users table
Option 2: Client → auth-service.GetUser → users table
```

---

## Benefits After Boundary Clarification

✅ **Single Writer for Profiles**: No race conditions, clear ownership
✅ **Clear Responsibility**: auth = authn/authz, user = profiles/social
✅ **Easier Testing**: Each service has well-defined scope
✅ **Simpler Client Logic**: One canonical RPC per operation
✅ **Reduced Coupling**: auth-service no longer knows about E2EE keys

---

## Action Items

- [ ] Task 2.1: Add UpsertUserPublicKey/GetUserPublicKey to user-service proto
- [ ] Task 2.2: Implement public key RPCs in user-service
- [ ] Task 2.3: Mark auth-service profile RPCs as deprecated
- [ ] Task 2.4: Update all clients to use user-service for profile updates
- [ ] Task 2.5: Remove deprecated RPCs from auth-service
- [ ] Task 2.6: Update architecture documentation
