# P1 Fix: Protocol Buffer Versioning & Registry

## Problem

**Issue**: Each service builds its own Proto definitions independently
```
user-service/proto/users.proto
  ↓
content-service/proto/users.proto (COPY)
  ↓
messaging-service/proto/users.proto (COPY)
  ↓
3 different versions of same proto definition
```

**Risks**:
- Proto message incompatibility: version mismatch causes silent failures
- Breaking changes not tracked: no backward compatibility checking
- DRY violation: same proto defined 3+ times
- Difficult migrations: updating shared proto requires coordinating multiple services

**Example**: If user-service adds field `verified_at` to User message:
```protobuf
// user-service/proto/users.proto (NEW)
message User {
  string id = 1;
  string email = 2;
  int64 verified_at = 3;  // NEW FIELD
}

// content-service/proto/users.proto (OLD - out of sync)
message User {
  string id = 1;
  string email = 2;
  // Missing verified_at!
}

// Result: content-service doesn't know about verified_at
```

---

## Solution: Centralized Proto Registry

### Architecture

```
┌──────────────────────────────────┐
│ nova-protos (git submodule)      │
│ Centralized Proto Registry       │
└──────────────────────────────────┘
  ├── protos/auth/
  │   └── auth.proto              (single source of truth)
  ├── protos/user/
  │   └── users.proto
  ├── protos/content/
  │   └── posts.proto
  ├── protos/messaging/
  │   └── messages.proto
  └── protos/notification/
      └── notifications.proto

  ↓ (git submodule)

┌──────────────────────────────────┐
│ Each service's proto dependency  │
└──────────────────────────────────┘
  user-service:
    protos/ → ../nova-protos/protos/

  content-service:
    protos/ → ../nova-protos/protos/

  messaging-service:
    protos/ → ../nova-protos/protos/
```

### Step 1: Create Central Registry Repository

```bash
# Create new repo
mkdir ~/nova-protos
cd ~/nova-protos
git init

# Directory structure
mkdir -p protos/{auth,user,content,messaging,notification}

# Create proto files (move from each service)
touch protos/auth/auth.proto
touch protos/user/users.proto
touch protos/content/posts.proto
touch protos/messaging/messages.proto

# Add version tracking
touch CHANGELOG.md
touch schema.md
```

### Step 2: Add Registry to Each Service

**In user-service/Cargo.toml**:
```toml
[dependencies]
tonic = "0.11"
prost = "0.12"

[build-dependencies]
tonic-build = "0.11"

# Make sure build.rs is configured to use central protos
```

**In user-service/build.rs**:
```rust
use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Point to central proto registry
    let proto_root = PathBuf::from("../nova-protos");

    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .compile(
            &[
                proto_root.join("protos/user/users.proto"),
                proto_root.join("protos/auth/auth.proto"),  // Can import other protos
                proto_root.join("protos/content/posts.proto"),  // Shared types
            ],
            &[&proto_root.join("protos")],  // Import path
        )?;

    Ok(())
}
```

### Step 3: Proto Versioning Strategy

**File**: `/nova-protos/SCHEMA.md`

```markdown
# Nova Proto Schema

## Versioning

Each proto file follows semantic versioning: `MAJOR.MINOR.PATCH`

### Field Numbers
- Reserved fields: 1-99 (internal only)
- Service fields: 100-199
- Client fields: 200-299
- Future: 300+

### Rules
1. Never reuse field numbers (append = 0, remove = nil)
2. New fields: optional or with default
3. Breaking changes: major version bump
4. Non-breaking additions: minor version bump

## Auth Service (auth.proto v1.0.0)

```protobuf
syntax = "proto3";
package auth.v1;

message User {
  string id = 1;
  string email = 2;
  string username = 3;
  int64 created_at = 4;

  // v1.1.0 additions (backward compatible)
  optional string phone = 100;
  optional int64 verified_at = 101;

  // Reserved for future
  reserved 102 to 110;
}

message ValidateTokenRequest {
  string token = 1;
  enum TokenType {
    BEARER = 0;
    REFRESH = 1;
  }
  TokenType type = 2;
}

message ValidateTokenResponse {
  bool valid = 1;
  optional string error = 2;
  optional User user = 3;
}

service AuthService {
  rpc ValidateToken(ValidateTokenRequest) returns (ValidateTokenResponse);
}
```

## User Service (users.proto v1.0.0)

```protobuf
syntax = "proto3";
package user.v1;

import "auth/auth.proto";

message Profile {
  string bio = 1;
  string avatar_url = 2;
  int64 followers = 3;
}

// Extends auth.User concept for user-service
message UserProfile {
  auth.v1.User user = 1;  // Import from auth
  Profile profile = 2;
  int64 created_at = 3;
}

service UserService {
  rpc GetProfile(GetProfileRequest) returns (UserProfile);
}
```
```

### Step 4: Breaking Change Detection

**Tool**: proto-linter (automated checks)

```yaml
# nova-protos/.proto-lint.yaml
rules:
  - id: field-number-reuse
    description: "Field numbers must never be reused"
    severity: ERROR

  - id: wire-type-change
    description: "Don't change field wire types"
    severity: ERROR

  - id: required-to-optional
    description: "Can't make required field optional"
    severity: WARN

  - id: new-required-field
    description: "Can't add required field to message"
    severity: ERROR

  - id: service-method-removal
    description: "Removing service method is breaking"
    severity: ERROR
```

**CI/CD Integration**:
```yaml
# .github/workflows/proto-lint.yml
name: Proto Lint

on: [pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: bufbuild/buf-action@v1
        with:
          buf_token: ${{ secrets.BUF_TOKEN }}
```

### Step 5: Import Management

**Example**: messaging-service needs User type from user-service

```protobuf
// messaging-service/src/generated/messages.proto
syntax = "proto3";
package messaging.v1;

import "user/users.proto";

message Message {
  string id = 1;
  user.v1.UserProfile sender = 2;    // Import User type
  string content = 3;
  int64 created_at = 4;
}

service MessagingService {
  rpc SendMessage(Message) returns (MessageResponse);
}
```

---

## Implementation Checklist

### Phase 1: Setup Central Registry (Week 1)

- [ ] Create nova-protos repository
- [ ] Move all proto files to central location
- [ ] Remove local proto copies from services
- [ ] Add as git submodule to main repository
- [ ] Update build.rs in each service
- [ ] Verify builds still work

### Phase 2: Proto Documentation (Week 1-2)

- [ ] Create SCHEMA.md with all message definitions
- [ ] Document field numbering strategy
- [ ] Add backward compatibility guidelines
- [ ] Document import paths and dependencies

### Phase 3: CI/CD Integration (Week 2)

- [ ] Set up proto-lint in CI
- [ ] Enable automatic breaking change detection
- [ ] Create PR check that validates proto changes
- [ ] Document proto update process for team

### Phase 4: Version Tracking (Week 2)

- [ ] Create CHANGELOG.md
- [ ] Add version number to each proto package
- [ ] Document upgrade path for services
- [ ] Create automated version bump script

---

## Example: Proto Update Workflow

### Scenario: Add `verified_at` field to User

**Step 1**: Modify proto in central registry

```protobuf
// nova-protos/protos/user/users.proto
message User {
  string id = 1;
  string email = 2;
  string username = 3;
  int64 created_at = 4;

  // v1.1.0: Added verified_at
  optional int64 verified_at = 100;
}
```

**Step 2**: Update CHANGELOG.md

```markdown
## [1.1.0] - 2025-11-04

### Added
- User.verified_at field in user.proto
- Backward compatible with v1.0.0 clients

### Migration
- Services can safely upgrade; field optional
- No breaking changes
```

**Step 3**: PR check automatically validates

- ✅ No field number reuse
- ✅ Field is optional (backward compatible)
- ✅ Version bumped to 1.1.0
- ✅ CHANGELOG updated

**Step 4**: Services update independently

```rust
// Each service that needs verified_at updates
fn process_user(user: &user::v1::User) {
    if let Some(verified_at) = user.verified_at {
        println!("User verified at: {}", verified_at);
    }
}
```

---

## Dependency Diagram

```
nova-protos (main repo)
├── protos/
│   ├── auth/auth.proto
│   ├── user/users.proto
│   ├── content/posts.proto
│   └── messaging/messages.proto
└── CHANGELOG.md

↓ git submodule

auth-service/
├── src/
├── protos/ → nova-protos/protos/
└── build.rs

user-service/
├── src/
├── protos/ → nova-protos/protos/
└── build.rs

content-service/
├── src/
├── protos/ → nova-protos/protos/
└── build.rs

messaging-service/
├── src/
├── protos/ → nova-protos/protos/
└── build.rs
```

---

## Best Practices

### Proto File Organization

```
protos/
├── auth/
│   ├── auth.proto         (main service protos)
│   ├── auth_common.proto  (shared types)
│   └── CHANGELOG.md
├── user/
│   ├── users.proto
│   ├── profile.proto
│   └── CHANGELOG.md
└── shared/
    ├── common.proto       (global types: error, pagination)
    └── CHANGELOG.md
```

### Backward Compatibility Checklist

Before merging a proto change:

- [ ] No field numbers reused or removed
- [ ] New required fields? (NO - add as optional)
- [ ] Service method removed? (NO)
- [ ] Enum value removed? (NO)
- [ ] Field type changed? (NO - incompatible)
- [ ] Optional → required? (NO)
- [ ] Version number bumped? (for tracking)
- [ ] CHANGELOG updated? (YES)

### Testing

```rust
#[test]
fn test_proto_compatibility() {
    // Serialize with v1.0.0 reader
    let v1_user = user::v1::User {
        id: "123".to_string(),
        email: "test@example.com".to_string(),
        username: "testuser".to_string(),
        created_at: 0,
        verified_at: None,  // v1.1.0 field
    };

    let bytes = v1_user.encode_to_vec();

    // Deserialize with v1.1.0 reader
    let v11_user = user::v1::User::decode(&bytes[..]).expect("Should decode");
    assert_eq!(v11_user.id, "123");
    assert!(v11_user.verified_at.is_none());
}
```

---

## Tools & Resources

- **buf**: [Protocol Buffer lint/format tool](https://buf.build/)
- **protolock**: [Proto file versioning tool](https://github.com/nilslice/protolock)
- **protoc**: Official compiler
- **tonic-build**: Rust gRPC code generation

---

## Status

- **Created**: 2025-11-04
- **Priority**: P1 (High)
- **Estimated Effort**: 2 weeks
- **Impact**: Prevents proto version incompatibility, enables safe schema evolution
- **Blocks**: Microservice development speed
