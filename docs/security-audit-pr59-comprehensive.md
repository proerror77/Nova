# Security Audit Report: PR #59 (feat/consolidate-pending-changes)

**Date**: 2025-11-10
**Auditor**: Linus Torvalds (Security Review)
**Scope**: OWASP Top 10 (2021) Analysis + Comprehensive Security Assessment
**Severity Classification**: CVE-style with CVSS v3.1 scoring

---

## Executive Summary

**Status**: 🔴 **CRITICAL - DO NOT MERGE**

这个 PR 包含了多个 **P0 级别的安全漏洞**,足以让整个系统在生产环境中被直接攻破。这不是"可以改进"的问题,而是"必须立即修复"的致命缺陷。

**Critical Findings**:
- ✅ JWT 中间件存在但 **完全未启用** (GraphQL Gateway 无任何认证保护)
- ✅ iOS 应用将敏感 Token 存储在 **UserDefaults** 而非 Keychain
- ✅ CORS 配置为 `*` (允许任意源)
- ⚠️ GraphQL API 暴露所有 mutations 无权限校验
- ⚠️ Crypto FFI 缺少输入验证 (潜在内存安全问题)

**OWASP Top 10 Violations**: 5 of 10 (A01, A02, A05, A07, A08)

**Blocker Count**: 3
**High Priority Count**: 7
**Medium Priority Count**: 5

---

## OWASP Top 10 (2021) Analysis

### 🔴 A01:2021 - Broken Access Control

#### NOVA-SEC-2025-001: GraphQL Gateway Missing Authentication Layer
**CVSS Score**: 9.8 (Critical)
**CVSS Vector**: CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H

**Location**: `backend/graphql-gateway/src/main.rs`

**Evidence**:
```rust
// File: backend/graphql-gateway/src/main.rs:44-49
HttpServer::new(move || {
    App::new()
        .app_data(web::Data::new(schema.clone()))
        .route("/graphql", web::post().to(graphql_handler))  // ❌ NO AUTH
        .route("/health", web::get().to(|| async { "ok" }))
})
```

**Vulnerability**:
GraphQL Gateway 完全未启用 JWT 认证中间件。虽然代码库中存在 `actix-middleware/src/jwt_auth.rs` (Line 1-317),但在 `main.rs` 中 **完全未使用**。

**Attack Scenario**:
```bash
# 攻击者可以直接调用任意 mutation
curl -X POST https://api-staging.nova.social/graphql \
  -H "Content-Type: application/json" \
  -d '{
    "query": "mutation { deletePost(postId: \"any-id\") }"
  }'
# 无需任何认证,直接成功
```

**Impact**:
- 任意用户数据读取 (完全的数据泄露)
- 任意用户数据修改/删除 (完全的数据完整性破坏)
- 冒充任何用户身份执行操作
- 绕过所有业务逻辑限制

**Recommended Fix**:
```rust
// backend/graphql-gateway/src/main.rs
use actix_middleware::jwt_auth::JwtAuthMiddleware;

HttpServer::new(move || {
    App::new()
        .wrap(JwtAuthMiddleware::new())  // ✅ 启用 JWT 认证
        .app_data(web::Data::new(schema.clone()))
        .route("/graphql", web::post().to(graphql_handler))
        .route("/health", web::get().to(|| async { "ok" }))
})
```

**Blocker Rationale**:
这是 Linus 所说的 "Never break userspace" 的反面 —— 这是 "Never ship without authentication"。在生产环境中部署无认证的 GraphQL API 等同于把数据库直接暴露在公网上。

---

#### NOVA-SEC-2025-002: GraphQL Mutations Missing Authorization Checks
**CVSS Score**: 8.1 (High)
**CVSS Vector**: CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:N

**Location**:
- `backend/graphql-gateway/src/schema/user.rs:138-174`
- `backend/graphql-gateway/src/schema/content.rs:217-269`

**Evidence**:
```rust
// File: backend/graphql-gateway/src/schema/user.rs:138-158
async fn update_profile(
    &self,
    ctx: &Context<'_>,
    input: UpdateProfileInput,
) -> Result<User> {
    // Line 147: 从 context 提取 user_id (但没有验证是否有权修改)
    let user_id = ctx.data_opt::<String>()
        .ok_or_else(|| Error::new("User not authenticated"))?;

    // ❌ 没有检查: user_id == input.target_user_id
    // 攻击者可以修改任意用户的 profile
    let request = tonic::Request::new(UpdateUserProfileRequest {
        user_id: user_id.clone(),  // 使用提取的 user_id 直接修改
        display_name: input.display_name.unwrap_or_default(),
        // ...
    });
}
```

**Vulnerability**:
1. `update_profile` 使用 context 中的 `user_id`,但没有验证输入中是否包含目标用户 ID
2. 如果攻击者可以控制 context 数据 (例如通过未启用的认证层),可以修改任意用户资料
3. `delete_post`, `like_post` 等操作同样缺少所有权验证

**Attack Scenario**:
```graphql
# 假设攻击者通过某种方式注入了 user_id 到 context
mutation {
  updateProfile(input: {
    displayName: "Hacked by Attacker"
    bio: "All your base are belong to us"
  }) {
    id
    displayName
  }
}

# 或者更糟: 删除其他用户的帖子
mutation {
  deletePost(postId: "victim-post-id")
}
```

**Impact**:
- 横向权限提升 (Insecure Direct Object Reference)
- 任意用户资料篡改
- 删除其他用户的内容
- 社交工程攻击 (冒充身份发布内容)

**Recommended Fix**:
```rust
// backend/graphql-gateway/src/schema/user.rs
async fn update_profile(
    &self,
    ctx: &Context<'_>,
    target_user_id: String,  // ✅ 明确指定目标用户
    input: UpdateProfileInput,
) -> Result<User> {
    // ✅ 提取当前认证用户
    let current_user_id = ctx.data_opt::<String>()
        .ok_or_else(|| Error::new("User not authenticated"))?;

    // ✅ 验证权限: 只能修改自己的资料
    if current_user_id != &target_user_id {
        return Err(Error::new("Forbidden: Cannot modify other user's profile"));
    }

    // 继续执行更新逻辑...
}
```

**Priority**: P0 - 这是经典的 IDOR (Insecure Direct Object Reference) 漏洞,必须在所有 mutations 中添加权限校验。

---

#### NOVA-SEC-2025-003: Content Feed Query Bypasses Privacy Controls
**CVSS Score**: 7.5 (High)
**CVSS Vector**: CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N

**Location**: `backend/graphql-gateway/src/schema/content.rs:106-208`

**Evidence**:
```rust
// File: backend/graphql-gateway/src/schema/content.rs:117-121
async fn feed(
    &self,
    ctx: &Context<'_>,
    limit: Option<i32>,
    cursor: Option<String>,
) -> Result<FeedResponse> {
    // Line 118-121: 使用 "anonymous" 作为 fallback
    let user_id = ctx.data_opt::<String>()
        .unwrap_or(&"anonymous".to_string())  // ❌ 允许匿名访问
        .clone();
```

**Vulnerability**:
Feed 查询允许匿名用户访问,且没有检查帖子的隐私设置 (`is_private` 字段在 `User` 类型中存在但未使用)。

**Attack Scenario**:
```graphql
# 攻击者无需认证即可爬取所有公开和私有帖子
query {
  feed(limit: 100, cursor: null) {
    posts {
      id
      caption
      imageUrl
      author {
        id
        username
        email  # ❌ 暴露邮箱
        isPrivate  # 即使是私有账号也能看到
      }
    }
  }
}
```

**Impact**:
- 隐私账号的内容泄露
- 用户邮箱地址批量爬取
- 违反 GDPR/CCPA 数据保护要求

**Recommended Fix**:
```rust
// backend/graphql-gateway/src/schema/content.rs
async fn feed(
    &self,
    ctx: &Context<'_>,
    limit: Option<i32>,
    cursor: Option<String>,
) -> Result<FeedResponse> {
    // ✅ 强制要求认证
    let user_id = ctx.data::<String>()
        .map_err(|_| Error::new("Authentication required"))?;

    // ... 获取 feed 后,过滤私有账号的内容
    let filtered_posts: Vec<Post> = posts.into_iter()
        .filter(|post| {
            // 检查作者的 is_private 设置
            if let Some(author) = &post.author {
                if author.is_private {
                    // 只有关注者才能看到
                    return check_is_following(user_id, &author.id).await;
                }
            }
            true
        })
        .collect();
}
```

---

### 🔴 A02:2021 - Cryptographic Failures

#### NOVA-SEC-2025-004: iOS Tokens Stored in UserDefaults (Plaintext)
**CVSS Score**: 8.6 (High)
**CVSS Vector**: CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H

**Location**: `ios/NovaSocial/APIClient.swift:34-52`

**Evidence**:
```swift
// File: ios/NovaSocial/APIClient.swift:34-46
private var accessToken: String? {
    get { UserDefaults.standard.string(forKey: AuthKeys.accessToken) }  // ❌ PLAINTEXT
    set { UserDefaults.standard.set(newValue, forKey: AuthKeys.accessToken) }
}

func saveAuthTokens(accessToken: String, refreshToken: String) {
    UserDefaults.standard.set(accessToken, forKey: AuthKeys.accessToken)      // ❌ PLAINTEXT
    UserDefaults.standard.set(refreshToken, forKey: AuthKeys.refreshToken)    // ❌ PLAINTEXT
}
```

**Vulnerability**:
JWT tokens (包括 refresh token) 以 **明文** 形式存储在 `UserDefaults`,这是 iOS 安全的基本错误:

1. **UserDefaults 存储在未加密的 plist 文件**:
   - 路径: `/var/mobile/Containers/Data/Application/<UUID>/Library/Preferences/<bundle-id>.plist`
   - 任何能访问文件系统的程序都能读取 (越狱设备、恶意应用、iTunes 备份)

2. **Refresh Token 泄露 = 永久账户接管**:
   - Refresh token 有效期 30 天 (crypto-core/jwt.rs:48)
   - 一旦泄露,攻击者可以持续生成 access token

3. **违反 Apple Security Guidelines**:
   - Apple 明确要求敏感数据必须存储在 Keychain
   - App Store Review Guideline 2.5.3: Data Storage and Privacy

**Attack Scenario**:
```bash
# 攻击者场景 1: 越狱设备上的恶意应用
$ plutil -p /var/mobile/Containers/Data/Application/<UUID>/Library/Preferences/com.nova.social.plist
{
  "nova.auth.accessToken" => "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
  "nova.auth.refreshToken" => "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}

# 攻击者场景 2: iTunes 备份提取 (即使设备未越狱)
$ idevicebackup2 backup --full backup_dir/
$ grep -r "nova.auth" backup_dir/
# 直接获取所有用户的 token
```

**Impact**:
- 完全的账户接管 (Account Takeover)
- 长期持久化访问 (30 天内无需重新登录)
- 符合 OWASP A02 的"敏感数据暴露"定义

**Recommended Fix**:
```swift
// ios/NovaSocial/KeychainHelper.swift (新文件)
import Security
import Foundation

class KeychainHelper {
    enum KeychainError: Error {
        case duplicateEntry
        case unknown(OSStatus)
    }

    static func save(key: String, data: String) throws {
        let data = data.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock  // ✅ 设备锁定时不可访问
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unknown(status) }
    }

    static func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let result = String(data: data, encoding: .utf8) else {
            return nil
        }

        return result
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// ios/NovaSocial/APIClient.swift (修改)
private var accessToken: String? {
    get { KeychainHelper.retrieve(key: AuthKeys.accessToken) }  // ✅ 从 Keychain 读取
    set {
        if let value = newValue {
            try? KeychainHelper.save(key: AuthKeys.accessToken, data: value)
        } else {
            KeychainHelper.delete(key: AuthKeys.accessToken)
        }
    }
}

func saveAuthTokens(accessToken: String, refreshToken: String) {
    try? KeychainHelper.save(key: AuthKeys.accessToken, data: accessToken)      // ✅ 存储到 Keychain
    try? KeychainHelper.save(key: AuthKeys.refreshToken, data: refreshToken)    // ✅ 存储到 Keychain
}
```

**Priority**: P0 - 这是 iOS 安全的基本要求,Apple 在审核时可能会因此拒绝应用。

---

#### NOVA-SEC-2025-005: Crypto FFI Missing Input Validation
**CVSS Score**: 7.3 (High)
**CVSS Vector**: CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:L

**Location**: `backend/libs/crypto-core/src/lib.rs:148-176`

**Evidence**:
```rust
// File: backend/libs/crypto-core/src/lib.rs:148-176
#[no_mangle]
pub unsafe extern "C" fn cryptocore_encrypt(
    plaintext_ptr: *const c_uchar,
    plaintext_len: c_ulong,
    recipient_pk_ptr: *const c_uchar,
    recipient_pk_len: c_ulong,  // ❌ 没有验证是否 == 32
    sender_sk_ptr: *const c_uchar,
    sender_sk_len: c_ulong,     // ❌ 没有验证是否 == 32
    nonce_ptr: *const c_uchar,
    nonce_len: c_ulong,         // ❌ 没有验证是否 == 24
    out_len_ptr: *mut c_ulong,
) -> *mut c_uchar {
    // Line 159-162: 直接使用 slice::from_raw_parts,没有长度验证
    let pt = slice::from_raw_parts(plaintext_ptr, plaintext_len as usize);
    let rpk = slice::from_raw_parts(recipient_pk_ptr, recipient_pk_len as usize);  // ❌
    let ssk = slice::from_raw_parts(sender_sk_ptr, sender_sk_len as usize);        // ❌
    let nonce = slice::from_raw_parts(nonce_ptr, nonce_len as usize);              // ❌

    // Line 163: 调用内部 encrypt 函数 (期望 32/32/24 字节)
    match encrypt(pt, rpk, ssk, nonce) {
        Ok(ct) => { /* ... */ }
        Err(_) => ptr::null_mut(),  // ❌ 错误时返回 null,但没有记录日志
    }
}
```

**Vulnerability**:
1. **缺少长度验证**: FFI 函数接受任意长度的 key/nonce,但 Curve25519 要求:
   - Public key: 32 bytes
   - Secret key: 32 bytes
   - Nonce: 24 bytes

2. **潜在的内存安全问题**: 如果调用者传递了错误的长度,`slice::from_raw_parts` 可能导致:
   - Buffer over-read (读取未分配的内存)
   - 触发 sodiumoxide 的 panic (Rust panic 跨越 FFI 边界是 UB)

3. **错误处理不足**: 失败时仅返回 `null`,iOS 端无法区分失败原因

**Attack Scenario**:
```swift
// iOS 攻击代码: 传递错误长度的 key
let publicKey = Data(count: 16)  // ❌ 只有 16 字节,应该是 32
let secretKey = Data(count: 32)
let nonce = Data(count: 24)
let plaintext = "sensitive data".data(using: .utf8)!

var outLen: UInt = 0
let ciphertext = cryptocore_encrypt(
    plaintext.bytes, UInt(plaintext.count),
    publicKey.bytes, UInt(publicKey.count),  // 传递 16 字节
    secretKey.bytes, UInt(secretKey.count),
    nonce.bytes, UInt(nonce.count),
    &outLen
)

// 结果: null (但不知道是因为长度错误还是其他原因)
// 更糟: 可能触发 Rust panic,导致 iOS 应用崩溃
```

**Impact**:
- 内存安全漏洞 (Buffer over-read)
- 应用崩溃 (Denial of Service)
- 加密操作失败但无错误提示 (数据完整性风险)

**Recommended Fix**:
```rust
// backend/libs/crypto-core/src/lib.rs
#[no_mangle]
pub unsafe extern "C" fn cryptocore_encrypt(
    plaintext_ptr: *const c_uchar,
    plaintext_len: c_ulong,
    recipient_pk_ptr: *const c_uchar,
    recipient_pk_len: c_ulong,
    sender_sk_ptr: *const c_uchar,
    sender_sk_len: c_ulong,
    nonce_ptr: *const c_uchar,
    nonce_len: c_ulong,
    out_len_ptr: *mut c_ulong,
) -> *mut c_uchar {
    // ✅ 验证输入长度
    if recipient_pk_len != 32 {
        tracing::error!("Invalid recipient public key length: expected 32, got {}", recipient_pk_len);
        return ptr::null_mut();
    }
    if sender_sk_len != 32 {
        tracing::error!("Invalid sender secret key length: expected 32, got {}", sender_sk_len);
        return ptr::null_mut();
    }
    if nonce_len != 24 {
        tracing::error!("Invalid nonce length: expected 24, got {}", nonce_len);
        return ptr::null_mut();
    }

    // ✅ 验证指针非空
    if plaintext_ptr.is_null() || recipient_pk_ptr.is_null()
        || sender_sk_ptr.is_null() || nonce_ptr.is_null() {
        tracing::error!("Null pointer passed to cryptocore_encrypt");
        return ptr::null_mut();
    }

    // ✅ 安全地创建 slices
    let pt = slice::from_raw_parts(plaintext_ptr, plaintext_len as usize);
    let rpk = slice::from_raw_parts(recipient_pk_ptr, 32);  // 固定 32 字节
    let ssk = slice::from_raw_parts(sender_sk_ptr, 32);     // 固定 32 字节
    let nonce = slice::from_raw_parts(nonce_ptr, 24);       // 固定 24 字节

    match encrypt(pt, rpk, ssk, nonce) {
        Ok(ct) => {
            let mut v = ct;
            let len = v.len() as c_ulong;
            if !out_len_ptr.is_null() {
                *out_len_ptr = len;
            }
            let ptr = v.as_mut_ptr();
            std::mem::forget(v);
            ptr
        }
        Err(e) => {
            tracing::error!("Encryption failed: {:?}", e);  // ✅ 记录错误
            ptr::null_mut()
        }
    }
}
```

**同样需要修复的函数**: `cryptocore_decrypt`, `cryptocore_generate_nonce`

**Priority**: P1 - 影响加密功能的可靠性和安全性,需要在生产环境前修复。

---

### 🔴 A05:2021 - Security Misconfiguration

#### NOVA-SEC-2025-006: CORS Allows All Origins (*)
**CVSS Score**: 6.5 (Medium)
**CVSS Vector**: CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:H/A:N

**Location**: `k8s/graphql-gateway/ingress-staging.yaml:14-20`

**Evidence**:
```yaml
# File: k8s/graphql-gateway/ingress-staging.yaml:14-20
annotations:
  # CORS configuration
  nginx.ingress.kubernetes.io/enable-cors: "true"
  nginx.ingress.kubernetes.io/cors-allow-origin: "*"  # ❌ 允许任意源
  nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, PUT, PATCH, DELETE, OPTIONS"
  nginx.ingress.kubernetes.io/cors-allow-headers: "DNT,X-CustomHeader,Keep-Alive,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Authorization"
  nginx.ingress.kubernetes.io/cors-max-age: "3600"
  nginx.ingress.kubernetes.io/cors-allow-credentials: "true"  # ❌ 与 * 组合是危险的
```

**Vulnerability**:
CORS 配置同时启用了:
1. `cors-allow-origin: "*"` - 允许任意源
2. `cors-allow-credentials: "true"` - 允许携带凭证

这种组合是 **明确禁止的** (根据 CORS 规范,浏览器会拒绝这种请求),但如果 Nginx 配置错误或浏览器实现有漏洞,可能导致 CSRF 攻击。

**Attack Scenario**:
```html
<!-- 攻击者在 evil.com 上的页面 -->
<script>
fetch('https://api-staging.nova.social/graphql', {
  method: 'POST',
  credentials: 'include',  // 携带 Cookie (如果有)
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    query: `mutation { deletePost(postId: "victim-post-id") }`
  })
})
</script>
```

如果用户在访问 evil.com 的同时已经登录了 Nova,攻击者可以利用用户的凭证执行操作。

**Impact**:
- Cross-Site Request Forgery (CSRF)
- 跨域数据泄露 (如果浏览器/Nginx 实现有漏洞)
- 违反同源策略 (Same-Origin Policy)

**Recommended Fix**:
```yaml
# k8s/graphql-gateway/ingress-staging.yaml
annotations:
  nginx.ingress.kubernetes.io/enable-cors: "true"
  # ✅ 只允许特定的可信源
  nginx.ingress.kubernetes.io/cors-allow-origin: "https://nova.social,https://app-staging.nova.social"
  nginx.ingress.kubernetes.io/cors-allow-methods: "GET, POST, OPTIONS"  # ✅ 移除 PUT/PATCH/DELETE
  nginx.ingress.kubernetes.io/cors-allow-headers: "Content-Type,Authorization"  # ✅ 最小化允许的 headers
  nginx.ingress.kubernetes.io/cors-max-age: "3600"
  nginx.ingress.kubernetes.io/cors-allow-credentials: "true"

  # ✅ 添加 CSRF 保护
  nginx.ingress.kubernetes.io/configuration-snippet: |
    # 验证 Origin/Referer header
    set $cors_origin "";
    if ($http_origin ~* ^https://nova\.social$) {
      set $cors_origin $http_origin;
    }
    if ($http_origin ~* ^https://app-staging\.nova\.social$) {
      set $cors_origin $http_origin;
    }
    add_header 'Access-Control-Allow-Origin' $cors_origin always;
```

**Priority**: P1 - staging 环境可以暂时接受,但生产环境 **必须** 修复。

---

#### NOVA-SEC-2025-007: GraphQL Playground Enabled in Production
**CVSS Score**: 5.3 (Medium)
**CVSS Vector**: CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N

**Location**: `ios/NovaSocial/Config.swift:71-84`

**Evidence**:
```swift
// File: ios/NovaSocial/Config.swift:71-84
static let playgroundURL: String = {
    switch Environment.current {
    case .development:
        return "http://localhost:8080/playground"
    case .staging:
        return "https://api-staging.nova.social/playground"  // ⚠️ staging 可访问
    case .production:
        return ""  // ✅ production 已禁用
    }
}()
```

同时检查 Ingress 配置:
```yaml
# k8s/graphql-gateway/ingress-staging.yaml:58-65
- path: /playground
  pathType: Prefix
  backend:
    service:
      name: graphql-gateway
      port:
        number: 8080
```

**Vulnerability**:
GraphQL Playground 在 staging 环境中完全开放,允许任何人:
1. 查看完整的 GraphQL schema (包括所有 queries/mutations)
2. 执行任意 GraphQL 操作 (如果认证未启用)
3. 进行 introspection 查询 (暴露 API 结构)

**Attack Scenario**:
```bash
# 攻击者访问 playground
curl https://api-staging.nova.social/playground

# 执行 introspection 查询获取完整 schema
query IntrospectionQuery {
  __schema {
    types {
      name
      fields {
        name
        args { name type { name } }
      }
    }
  }
}

# 发现所有可用的 mutations 和 queries
# 然后利用这些信息进行针对性攻击
```

**Impact**:
- API 结构完全暴露 (帮助攻击者理解系统)
- 可能被用于自动化扫描和漏洞发现
- 违反"最小暴露"原则

**Recommended Fix**:
```yaml
# k8s/graphql-gateway/ingress-staging.yaml
# ✅ 移除 /playground 路由,或添加 IP 白名单
- path: /playground
  pathType: Prefix
  backend:
    service:
      name: graphql-gateway
      port:
        number: 8080
  # ✅ 添加 IP 白名单注解 (仅允许内部网络)
  annotations:
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,172.16.0.0/12"
```

或者更好的方案:
```rust
// backend/graphql-gateway/src/main.rs
let schema = Schema::build(QueryRoot::default(), MutationRoot, SubscriptionRoot)
    .enable_introspection(cfg!(debug_assertions))  // ✅ 只在 debug 模式下启用
    .finish();
```

**Priority**: P2 - staging 环境可以接受,但建议添加 IP 白名单。

---

### 🔴 A07:2021 - Identification and Authentication Failures

#### NOVA-SEC-2025-008: Missing JWT Key Rotation Mechanism
**CVSS Score**: 5.9 (Medium)
**CVSS Vector**: CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N

**Location**: `backend/libs/crypto-core/src/jwt.rs:98-99`

**Evidence**:
```rust
// File: backend/libs/crypto-core/src/jwt.rs:98-99
static JWT_ENCODING_KEY: OnceCell<EncodingKey> = OnceCell::new();
static JWT_DECODING_KEY: OnceCell<DecodingKey> = OnceCell::new();
```

**Vulnerability**:
JWT keys 使用 `OnceCell` 存储,意味着:
1. **在应用生命周期内无法更换 key** (只能重启服务)
2. **没有 key rotation 机制** (无法定期轮换密钥)
3. **一旦 private key 泄露,只能停机更换**

这违反了 NIST SP 800-57 对密钥管理的要求:
- 密钥应该有生命周期管理
- 支持密钥轮换 (Key Rotation)
- 密钥泄露时能够快速响应

**Attack Scenario**:
```bash
# 假设攻击者通过某种方式获取了 JWT private key
# (例如: 配置文件泄露、内存转储、供应链攻击)

# 攻击者可以生成任意有效的 JWT token
$ openssl genrsa -out stolen_key.pem 2048
$ # 使用泄露的 key 生成 token
$ jwt encode --secret @stolen_key.pem --alg RS256 \
  '{"sub":"admin-user-id","email":"admin@nova.social","username":"admin","exp":9999999999}'

# 使用伪造的 token 访问系统
$ curl -H "Authorization: Bearer <forged-token>" \
  https://api.nova.social/graphql \
  -d '{"query":"{ users { id email } }"}'

# 结果: 完全的系统访问权限,且无法通过 key rotation 来阻止
```

**Impact**:
- Key 泄露后无法热更新 (需要停机)
- 长期使用同一 key 增加被破解的风险
- 违反密钥管理最佳实践

**Recommended Fix**:
```rust
// backend/libs/crypto-core/src/jwt.rs
use std::sync::RwLock;

/// Key rotation support with multiple active keys
struct JwtKeyStore {
    /// Current active key for signing new tokens (kid = "current")
    encoding_key: EncodingKey,
    current_kid: String,

    /// Multiple decoding keys for validation (supports rotation)
    /// Map: kid -> DecodingKey
    decoding_keys: HashMap<String, DecodingKey>,
}

static JWT_KEY_STORE: OnceCell<RwLock<JwtKeyStore>> = OnceCell::new();

/// Add a new key for rotation (without downtime)
pub fn rotate_jwt_keys(
    new_encoding_key: &str,
    new_decoding_key: &str,
    new_kid: &str,
) -> Result<()> {
    let store = JWT_KEY_STORE.get()
        .ok_or_else(|| anyhow!("JWT keys not initialized"))?;

    let mut store = store.write()
        .map_err(|_| anyhow!("Failed to acquire write lock"))?;

    // Parse new keys
    let encoding_key = EncodingKey::from_rsa_pem(new_encoding_key.as_bytes())?;
    let decoding_key = DecodingKey::from_rsa_pem(new_decoding_key.as_bytes())?;

    // Add new decoding key (keep old ones for validation)
    store.decoding_keys.insert(new_kid.to_string(), decoding_key);

    // Switch to new encoding key
    store.encoding_key = encoding_key;
    store.current_kid = new_kid.to_string();

    tracing::info!("JWT keys rotated to kid={}", new_kid);
    Ok(())
}

/// Generate token with kid in header
pub fn generate_access_token(user_id: Uuid, email: &str, username: &str) -> Result<String> {
    let store = JWT_KEY_STORE.get()
        .ok_or_else(|| anyhow!("JWT keys not initialized"))?;

    let store = store.read()
        .map_err(|_| anyhow!("Failed to acquire read lock"))?;

    let mut header = Header::new(JWT_ALGORITHM);
    header.kid = Some(store.current_kid.clone());  // ✅ 包含 kid

    let claims = Claims { /* ... */ };
    encode(&header, &claims, &store.encoding_key)
}

/// Validate token with kid-based key selection
pub fn validate_token(token: &str) -> Result<TokenData<Claims>> {
    let store = JWT_KEY_STORE.get()
        .ok_or_else(|| anyhow!("JWT keys not initialized"))?;

    let store = store.read()
        .map_err(|_| anyhow!("Failed to acquire read lock"))?;

    // Decode header to get kid
    let header = decode_header(token)?;
    let kid = header.kid
        .ok_or_else(|| anyhow!("Token missing kid"))?;

    // Select appropriate decoding key
    let decoding_key = store.decoding_keys.get(&kid)
        .ok_or_else(|| anyhow!("Unknown kid: {}", kid))?;

    // Validate
    let mut validation = Validation::new(JWT_ALGORITHM);
    decode::<Claims>(token, decoding_key, &validation)
}
```

同时添加 Admin API 用于热更新:
```rust
// backend/auth-service/src/admin.rs
#[post("/admin/rotate-jwt-keys")]
async fn rotate_keys(
    req: HttpRequest,
    body: web::Json<RotateKeysRequest>,
) -> Result<HttpResponse> {
    // ✅ 验证管理员权限 (通过 mTLS 或 internal-only endpoint)
    verify_admin_access(&req)?;

    // ✅ 执行 key rotation
    crypto_core::jwt::rotate_jwt_keys(
        &body.new_private_key,
        &body.new_public_key,
        &body.new_kid,
    )?;

    Ok(HttpResponse::Ok().json(json!({
        "status": "success",
        "message": "JWT keys rotated",
        "kid": body.new_kid
    })))
}
```

**Priority**: P2 - 不是立即阻塞的问题,但应该在 V1.0 之前实现。

---

#### NOVA-SEC-2025-009: Token Revocation Not Implemented in GraphQL Gateway
**CVSS Score**: 6.5 (Medium)
**CVSS Vector**: CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N

**Location**: `backend/graphql-gateway/src/schema/auth.rs:190-193`

**Evidence**:
```rust
// File: backend/graphql-gateway/src/schema/auth.rs:190-193
async fn logout(&self, ctx: &Context<'_>) -> Result<bool> {
    // TODO: Call auth-service to revoke token
    Ok(true)  // ❌ 直接返回 true,没有实际 revoke
}
```

**Vulnerability**:
Logout mutation 没有实际吊销 token,意味着:
1. **已注销的 token 仍然有效** (直到 1 小时后过期)
2. **攻击者可以继续使用被盗的 token**
3. **用户注销后账户仍然可被访问**

虽然 `actix-middleware/src/jwt_auth.rs` 中存在 `is_token_revoked` 函数 (Line 291-316),但 GraphQL Gateway 未调用它。

**Attack Scenario**:
```bash
# 1. 用户正常登录
$ curl -X POST https://api.nova.social/graphql \
  -d '{"query":"mutation { login(email:\"user@example.com\", password:\"pass\") { accessToken } }"}'
# 返回: {"accessToken": "eyJhbGc..."}

# 2. 攻击者窃取了 access token (通过 XSS/中间人攻击/恶意浏览器扩展)

# 3. 用户发现异常,立即注销
$ curl -X POST https://api.nova.social/graphql \
  -H "Authorization: Bearer eyJhbGc..." \
  -d '{"query":"mutation { logout }"}'
# 返回: {"logout": true}

# 4. 但攻击者仍然可以使用窃取的 token (1小时内有效)
$ curl -X POST https://api.nova.social/graphql \
  -H "Authorization: Bearer eyJhbGc..." \
  -d '{"query":"{ me { id email } }"}'
# 返回: 用户数据 (因为 token 未被真正吊销)
```

**Impact**:
- 注销后账户仍可被访问 (1 小时窗口)
- 无法应对 token 泄露事件
- 违反用户期望 (注销应该立即生效)

**Recommended Fix**:
```rust
// backend/graphql-gateway/src/schema/auth.rs
async fn logout(&self, ctx: &Context<'_>) -> Result<bool> {
    use crate::clients::proto::auth::RevokeTokenRequest;

    // ✅ 提取当前 token
    let token = extract_token(ctx)?;

    let clients = ctx.data::<ServiceClients>()?;
    let mut client = clients.auth_client().await?;

    // ✅ 调用 auth-service 吊销 token
    let request = tonic::Request::new(RevokeTokenRequest {
        token: token.clone(),
        revoke_refresh_token: true,  // 同时吊销 refresh token
    });

    client.revoke_token(request)
        .await
        .map_err(|e| Error::new(format!("Failed to revoke token: {}", e)))?;

    Ok(true)
}
```

同时确保 auth-service 的 revoke 实现正确:
```rust
// backend/auth-service/src/services/token_revocation.rs
pub async fn revoke_token(
    redis: &mut ConnectionManager,
    token: &str,
) -> Result<()> {
    // 计算 token hash
    let token_hash = crypto_core::hash::sha256(token.as_bytes());
    let hash_hex = hex::encode(token_hash);

    // 提取 jti 和 exp
    let token_data = crypto_core::jwt::validate_token(token)?;
    let jti = token_data.claims.jti
        .ok_or_else(|| anyhow!("Token missing jti"))?;
    let exp = token_data.claims.exp;
    let now = chrono::Utc::now().timestamp();
    let ttl = (exp - now).max(0) as u64;

    // ✅ 存储到 Redis (双重检查: hash + jti)
    redis.set_ex(&format!("nova:revoked:token:{}", hash_hex), "1", ttl).await?;
    redis.set_ex(&format!("nova:revoked:jti:{}", jti), "1", ttl).await?;

    tracing::info!("Token revoked: jti={}", jti);
    Ok(())
}
```

**Priority**: P1 - 这是注销功能的基本要求,必须在生产环境前修复。

---

### 🔴 A08:2021 - Software and Data Integrity Failures

#### NOVA-SEC-2025-010: GraphQL Mutations Missing CSRF Protection
**CVSS Score**: 6.5 (Medium)
**CVSS Vector**: CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:H/A:N

**Location**: `backend/graphql-gateway/src/main.rs:47`

**Evidence**:
```rust
// File: backend/graphql-gateway/src/main.rs:44-49
HttpServer::new(move || {
    App::new()
        .app_data(web::Data::new(schema.clone()))
        .route("/graphql", web::post().to(graphql_handler))  // ❌ 无 CSRF 保护
        .route("/health", web::get().to(|| async { "ok" }))
})
```

**Vulnerability**:
GraphQL endpoint 没有 CSRF 保护机制,结合 CORS 配置 `*`,可能导致 CSRF 攻击:

1. **GraphQL 使用 POST 请求** (本应防御 CSRF,但 CORS * 破坏了这一防御)
2. **没有 CSRF token 验证**
3. **没有 Origin/Referer 检查**

**Attack Scenario**:
```html
<!-- 攻击者在 evil.com 上的页面 -->
<script>
// 假设用户已在 nova.social 登录 (有 JWT token 在 localStorage)
// 攻击者诱导用户访问 evil.com

// 读取 localStorage 中的 token (如果 CORS 配置错误)
const stolenToken = localStorage.getItem('nova.auth.accessToken');

// 或者利用 CSRF 执行操作 (如果使用 Cookie 存储认证)
fetch('https://api-staging.nova.social/graphql', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${stolenToken}`  // 如果能读取
  },
  body: JSON.stringify({
    query: `
      mutation {
        deletePost(postId: "victim-post-id")
        unfollowUser(userId: "victim-friend-id")
      }
    `
  })
});
</script>
```

**Impact**:
- 跨站请求伪造 (CSRF)
- 未经授权的操作执行
- 结合 CORS * 的复合攻击

**Recommended Fix**:

方案 1: 使用 GraphQL 特定的 CSRF 防护 (推荐)
```rust
// backend/graphql-gateway/src/middleware/csrf.rs
use actix_web::{dev::ServiceRequest, Error, HttpMessage};

pub async fn verify_graphql_csrf(req: &ServiceRequest) -> Result<(), Error> {
    // ✅ 验证 GraphQL 特定的 header (防止简单的 POST CSRF)
    let custom_header = req.headers()
        .get("X-Apollo-Operation-Name")
        .or_else(|| req.headers().get("X-GraphQL-Operation"))
        .ok_or_else(|| actix_web::error::ErrorForbidden("Missing GraphQL header"))?;

    // ✅ 验证 Origin/Referer
    let origin = req.headers()
        .get("Origin")
        .or_else(|| req.headers().get("Referer"))
        .and_then(|h| h.to_str().ok())
        .ok_or_else(|| actix_web::error::ErrorForbidden("Missing Origin/Referer"))?;

    // ✅ 检查是否来自可信源
    if !origin.starts_with("https://nova.social")
        && !origin.starts_with("https://app-staging.nova.social") {
        return Err(actix_web::error::ErrorForbidden("Invalid origin"));
    }

    Ok(())
}

// backend/graphql-gateway/src/main.rs
use actix_web::middleware::from_fn;

HttpServer::new(move || {
    App::new()
        .wrap(from_fn(verify_graphql_csrf))  // ✅ 添加 CSRF 检查
        .app_data(web::Data::new(schema.clone()))
        .route("/graphql", web::post().to(graphql_handler))
        .route("/health", web::get().to(|| async { "ok" }))
})
```

方案 2: 使用 Double Submit Cookie Pattern
```rust
// backend/graphql-gateway/src/middleware/csrf_token.rs
use actix_web::cookie::Cookie;
use actix_web::{HttpRequest, HttpResponse};

/// Generate and set CSRF token cookie
pub fn set_csrf_token(res: &mut HttpResponse) {
    let csrf_token = generate_random_token();  // 生成随机 token
    let cookie = Cookie::build("XSRF-TOKEN", csrf_token.clone())
        .path("/")
        .secure(true)
        .http_only(false)  // 允许 JS 读取
        .same_site(actix_web::cookie::SameSite::Strict)
        .finish();
    res.add_cookie(&cookie).ok();
}

/// Verify CSRF token
pub fn verify_csrf_token(req: &HttpRequest) -> Result<(), Error> {
    // 从 cookie 读取 token
    let cookie_token = req.cookie("XSRF-TOKEN")
        .map(|c| c.value().to_string())
        .ok_or_else(|| actix_web::error::ErrorForbidden("Missing CSRF cookie"))?;

    // 从 header 读取 token
    let header_token = req.headers()
        .get("X-XSRF-TOKEN")
        .and_then(|h| h.to_str().ok())
        .ok_or_else(|| actix_web::error::ErrorForbidden("Missing CSRF header"))?;

    // 验证两者相同
    if cookie_token != header_token {
        return Err(actix_web::error::ErrorForbidden("CSRF token mismatch"));
    }

    Ok(())
}
```

**iOS 端配置**:
```swift
// ios/NovaSocial/APIClient.swift
func query<T: Codable>(
    _ query: String,
    variables: [String: Any]? = nil,
    responseType: T.Type
) async throws -> T {
    var request = URLRequest(url: baseURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("NovaGraphQL", forHTTPHeaderField: "X-GraphQL-Operation")  // ✅ 添加自定义 header

    if let token = accessToken {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // ... 继续执行请求
}
```

**Priority**: P1 - 结合 CORS * 配置,这是一个实际的安全风险。

---

## Additional Findings (Medium/Low Priority)

### NOVA-SEC-2025-011: Missing Rate Limiting on Authentication Endpoints
**CVSS Score**: 5.3 (Medium)
**Location**: `backend/graphql-gateway/src/schema/auth.rs:98-145`

**Issue**: Login 和 Register mutations 没有 rate limiting,允许:
- 暴力破解密码
- 账号枚举攻击
- 资源耗尽攻击

虽然 Ingress 配置了 rate limiting (100 RPS),但这对于单个用户的登录尝试来说太宽松了。

**Fix**: 在 auth-service 中实现基于 IP + email 的 rate limiting:
```rust
// backend/auth-service/src/middleware/rate_limit.rs
pub async fn check_login_rate_limit(
    redis: &mut ConnectionManager,
    ip: &str,
    email: &str,
) -> Result<(), Error> {
    let key_ip = format!("rate_limit:login:ip:{}", ip);
    let key_email = format!("rate_limit:login:email:{}", email);

    // 检查 IP 限制: 5次/分钟
    let ip_count: i32 = redis.incr(&key_ip, 1).await?;
    if ip_count == 1 {
        redis.expire(&key_ip, 60).await?;
    }
    if ip_count > 5 {
        return Err(Error::new("Too many login attempts from this IP"));
    }

    // 检查 email 限制: 3次/5分钟
    let email_count: i32 = redis.incr(&key_email, 1).await?;
    if email_count == 1 {
        redis.expire(&key_email, 300).await?;
    }
    if email_count > 3 {
        return Err(Error::new("Too many login attempts for this account"));
    }

    Ok(())
}
```

---

### NOVA-SEC-2025-012: GraphQL Query Depth/Complexity Not Limited
**CVSS Score**: 4.3 (Medium)
**Location**: `backend/graphql-gateway/src/main.rs:38-39`

**Issue**: GraphQL schema 没有配置查询深度和复杂度限制,允许攻击者构造恶意查询:

```graphql
# 嵌套查询攻击 (深度 > 100)
query {
  user(id: "1") {
    followers {
      followers {
        followers {
          # ... 嵌套 100 层
        }
      }
    }
  }
}
```

**Fix**:
```rust
// backend/graphql-gateway/src/main.rs
use async_graphql::extensions::{QueryDepth, QueryComplexity};

let schema = Schema::build(QueryRoot::default(), MutationRoot, SubscriptionRoot)
    .extension(QueryDepth::new(10))              // ✅ 最大深度 10
    .extension(QueryComplexity::new(1000))       // ✅ 最大复杂度 1000
    .limit_depth(10)
    .limit_complexity(1000)
    .finish();
```

---

### NOVA-SEC-2025-013: Missing Input Validation on User-Provided Data
**CVSS Score**: 4.3 (Medium)
**Location**: Multiple locations

**Issue**: 多个 GraphQL mutations 缺少输入验证:

1. `register` mutation 没有验证 email 格式
2. `updateProfile` mutation 没有验证 URL 格式
3. `createPost` mutation 没有验证 caption 长度

**Example**:
```rust
// backend/graphql-gateway/src/schema/auth.rs:148-187
async fn register(
    &self,
    ctx: &Context<'_>,
    email: String,      // ❌ 没有验证格式
    username: String,   // ❌ 没有验证长度/字符
    password: String,   // ❌ 没有验证强度
) -> Result<AuthResponse> {
    // 直接传递给 auth-service,没有前置验证
}
```

**Fix**:
```rust
// backend/graphql-gateway/src/validation.rs
pub fn validate_email(email: &str) -> Result<()> {
    let email_regex = regex::Regex::new(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$")?;
    if !email_regex.is_match(email) {
        return Err(Error::new("Invalid email format"));
    }
    if email.len() > 255 {
        return Err(Error::new("Email too long"));
    }
    Ok(())
}

pub fn validate_username(username: &str) -> Result<()> {
    if username.len() < 3 || username.len() > 30 {
        return Err(Error::new("Username must be 3-30 characters"));
    }
    let username_regex = regex::Regex::new(r"^[a-zA-Z0-9_-]+$")?;
    if !username_regex.is_match(username) {
        return Err(Error::new("Username can only contain letters, numbers, _ and -"));
    }
    Ok(())
}

pub fn validate_password(password: &str) -> Result<()> {
    if password.len() < 8 {
        return Err(Error::new("Password must be at least 8 characters"));
    }
    // 检查密码强度 (至少包含: 大写、小写、数字)
    let has_upper = password.chars().any(|c| c.is_uppercase());
    let has_lower = password.chars().any(|c| c.is_lowercase());
    let has_digit = password.chars().any(|c| c.is_digit(10));
    if !has_upper || !has_lower || !has_digit {
        return Err(Error::new("Password must contain uppercase, lowercase, and digit"));
    }
    Ok(())
}

// 在 mutation 中使用:
async fn register(
    &self,
    ctx: &Context<'_>,
    email: String,
    username: String,
    password: String,
) -> Result<AuthResponse> {
    // ✅ 验证输入
    validate_email(&email)?;
    validate_username(&username)?;
    validate_password(&password)?;

    // 继续处理...
}
```

---

### NOVA-SEC-2025-014: Missing Security Headers
**CVSS Score**: 3.7 (Low)
**Location**: `k8s/graphql-gateway/ingress-staging.yaml`

**Issue**: Ingress 配置缺少关键的安全 headers:
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Content-Security-Policy`
- `Strict-Transport-Security`

**Fix**:
```yaml
# k8s/graphql-gateway/ingress-staging.yaml
annotations:
  # ✅ 添加安全 headers
  nginx.ingress.kubernetes.io/configuration-snippet: |
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://api-staging.nova.social;" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
```

---

### NOVA-SEC-2025-015: Sensitive Data in GraphQL Responses
**CVSS Score**: 3.7 (Low)
**Location**: `backend/graphql-gateway/src/schema/user.rs:30-56`

**Issue**: User type 包含 `email` 字段,在某些查询中可能暴露给其他用户:

```rust
// File: backend/graphql-gateway/src/schema/user.rs:30-56
#[derive(SimpleObject, Clone)]
pub struct User {
    pub id: String,
    pub username: String,
    pub email: Option<String>,  // ⚠️ 敏感数据
    // ...
}
```

在 `feed` 查询中,`author` 字段返回完整的 User 对象,可能包含 email。

**Fix**:
```rust
// backend/graphql-gateway/src/schema/user.rs
#[derive(SimpleObject, Clone)]
pub struct User {
    pub id: String,
    pub username: String,

    #[graphql(skip)]  // ✅ 默认不暴露
    pub email_internal: Option<String>,

    // ... 其他字段
}

impl User {
    /// 只有查询自己的资料时才返回 email
    pub fn with_email(mut self, current_user_id: &str) -> Self {
        if self.id == current_user_id {
            // 只有本人才能看到自己的 email
            self.email_internal = self.email_internal.clone();
        } else {
            self.email_internal = None;
        }
        self
    }
}

// 在 resolver 中使用:
async fn user(&self, ctx: &Context<'_>, id: String) -> Result<User> {
    let current_user_id = ctx.data_opt::<String>()
        .map(|s| s.as_str())
        .unwrap_or("");

    let user = fetch_user_from_service(&id).await?;
    Ok(user.with_email(current_user_id))
}
```

---

## Compliance & Regulatory Impact

### GDPR (General Data Protection Regulation)

**Violations**:
1. **Article 32 (Security of Processing)**:
   - iOS tokens 存储在 UserDefaults 不符合"适当的技术措施"要求
   - GraphQL API 无认证违反"数据保护by design"

2. **Article 5 (Data Protection Principles)**:
   - Feed 查询暴露 email 违反"最小化原则"
   - CORS * 配置可能导致未经授权的跨域访问

**Potential Fines**: 最高 €20,000,000 或全球年营业额的 4%

### CCPA (California Consumer Privacy Act)

**Violations**:
- Lack of access controls → 无法确保"合理的安全措施"
- Missing data minimization → 返回过多的个人信息

### PCI-DSS (如果处理支付信息)

**Violations**:
- Requirement 6.5.10: Broken Authentication and Session Management
- Requirement 6.6: Web application firewall (未实现 rate limiting)

---

## Remediation Roadmap

### Phase 1: Critical Blockers (P0) - MUST FIX BEFORE MERGE

**Timeline**: Immediate (1-2 days)

1. ✅ **Enable JWT Authentication Middleware** (NOVA-SEC-2025-001)
   - File: `backend/graphql-gateway/src/main.rs`
   - Effort: 30 minutes
   - Testing: Integration tests for all GraphQL endpoints

2. ✅ **Migrate iOS Tokens to Keychain** (NOVA-SEC-2025-004)
   - File: `ios/NovaSocial/APIClient.swift`
   - Effort: 2 hours
   - Testing: Manual testing on physical device + simulator

3. ✅ **Add Authorization Checks to Mutations** (NOVA-SEC-2025-002)
   - Files: All `schema/*.rs` files
   - Effort: 4 hours
   - Testing: Unit tests for each mutation

**Success Criteria**: All P0 issues resolved, tests passing

---

### Phase 2: High Priority (P1) - MUST FIX BEFORE PRODUCTION

**Timeline**: 1 week

4. ✅ **Fix CORS Configuration** (NOVA-SEC-2025-006)
   - File: `k8s/graphql-gateway/ingress-staging.yaml`
   - Effort: 1 hour

5. ✅ **Implement Token Revocation** (NOVA-SEC-2025-009)
   - Files: `auth.rs`, `auth-service`
   - Effort: 3 hours

6. ✅ **Add Input Validation to FFI** (NOVA-SEC-2025-005)
   - File: `backend/libs/crypto-core/src/lib.rs`
   - Effort: 2 hours

7. ✅ **Implement CSRF Protection** (NOVA-SEC-2025-010)
   - File: `backend/graphql-gateway/src/middleware/`
   - Effort: 3 hours

8. ✅ **Add Rate Limiting to Auth Endpoints** (NOVA-SEC-2025-011)
   - File: `backend/auth-service/src/middleware/`
   - Effort: 2 hours

**Success Criteria**: All P1 issues resolved, security review passed

---

### Phase 3: Medium Priority (P2) - Before V1.0 Release

**Timeline**: 2-4 weeks

9. ⚠️ **Implement JWT Key Rotation** (NOVA-SEC-2025-008)
   - File: `backend/libs/crypto-core/src/jwt.rs`
   - Effort: 1 day

10. ⚠️ **Add GraphQL Query Limits** (NOVA-SEC-2025-012)
    - File: `backend/graphql-gateway/src/main.rs`
    - Effort: 2 hours

11. ⚠️ **Disable Playground in Production** (NOVA-SEC-2025-007)
    - Files: Ingress configs
    - Effort: 30 minutes

12. ⚠️ **Add Security Headers** (NOVA-SEC-2025-014)
    - File: `k8s/graphql-gateway/ingress-staging.yaml`
    - Effort: 1 hour

13. ⚠️ **Implement Field-Level Access Control** (NOVA-SEC-2025-015)
    - Files: All schema files
    - Effort: 1 day

**Success Criteria**: All P2 issues resolved, penetration testing passed

---

## Testing & Verification

### Security Test Cases

#### Test Case 1: Unauthenticated Access
```bash
# 应该失败 (401 Unauthorized)
curl -X POST https://api-staging.nova.social/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ feed { posts { id } } }"}'

# Expected: {"errors":[{"message":"Unauthorized"}]}
```

#### Test Case 2: Invalid Token
```bash
# 应该失败 (401 Unauthorized)
curl -X POST https://api-staging.nova.social/graphql \
  -H "Authorization: Bearer invalid.token.here" \
  -d '{"query":"{ feed { posts { id } } }"}'

# Expected: {"errors":[{"message":"Invalid token"}]}
```

#### Test Case 3: IDOR Attack
```bash
# 应该失败 (403 Forbidden)
curl -X POST https://api-staging.nova.social/graphql \
  -H "Authorization: Bearer <valid-token-for-user-A>" \
  -d '{"query":"mutation { updateProfile(targetUserId: \"user-B-id\", input: {displayName: \"Hacked\"}) { id } }"}'

# Expected: {"errors":[{"message":"Forbidden: Cannot modify other user's profile"}]}
```

#### Test Case 4: iOS Keychain Storage
```swift
// 在 iOS 设备上验证
let token = "test-token-value"
try KeychainHelper.save(key: "test.token", data: token)

// 验证无法从 UserDefaults 读取
let fromUserDefaults = UserDefaults.standard.string(forKey: "test.token")
XCTAssertNil(fromUserDefaults)

// 验证可以从 Keychain 读取
let fromKeychain = KeychainHelper.retrieve(key: "test.token")
XCTAssertEqual(fromKeychain, token)
```

#### Test Case 5: Token Revocation
```bash
# 1. 登录获取 token
TOKEN=$(curl -X POST https://api-staging.nova.social/graphql \
  -d '{"query":"mutation { login(email:\"test@example.com\", password:\"password\") { accessToken } }"}' \
  | jq -r '.data.login.accessToken')

# 2. 使用 token 访问 (应该成功)
curl -X POST https://api-staging.nova.social/graphql \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"query":"{ me { id } }"}'

# 3. 注销
curl -X POST https://api-staging.nova.social/graphql \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"query":"mutation { logout }"}'

# 4. 再次使用 token (应该失败)
curl -X POST https://api-staging.nova.social/graphql \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"query":"{ me { id } }"}'

# Expected: {"errors":[{"message":"Token revoked"}]}
```

---

## Linus 的最终评价

这个 PR 展示了一个经典的问题: **"有好的组件,但没有正确地组装它们"**。

```
好的部分:
✅ JWT 中间件实现得很扎实 (jwt_auth.rs)
✅ 加密库使用了安全的算法 (RS256, Curve25519)
✅ 有完善的 tracing 和监控

垃圾的部分:
❌ JWT 中间件根本没启用 (main.rs 只有 3 行代码)
❌ iOS 把敏感数据存在 plist 里 (这是 2008 年的做法)
❌ CORS 配置成 * (这不是配置,这是投降)
❌ GraphQL mutations 没有权限检查 (这不是 API,这是数据库的 root 访问)
```

**如果我是 code reviewer,我会说:**

> "This is like building a vault with reinforced steel walls and then leaving the door wide open. We have excellent crypto primitives, solid JWT implementation, and good observability - but then we don't actually USE any of it. The authentication middleware exists but isn't enabled. The iOS app stores tokens in plaintext. CORS is set to '*' defeating all our security measures.
>
> Fix the P0 issues (enable auth, migrate to Keychain, add authorization checks) and we can talk about merging. Until then, this is a data breach waiting to happen."

**用中文说就是:**

> "这就像是造了一个保险库,钢筋混凝土的墙,然后把门大开着。我们有很好的密码学原语,扎实的 JWT 实现,良好的可观测性 — 但我们根本没用它们。认证中间件存在但没启用。iOS 应用把 token 明文存储。CORS 设置成 '*' 把所有安全措施都废了。
>
> 修复 P0 问题 (启用认证、迁移到 Keychain、添加权限检查),然后我们再谈合并。在那之前,这就是一个等待发生的数据泄露。"

---

## References

1. OWASP Top 10 (2021): https://owasp.org/Top10/
2. OWASP GraphQL Security Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/GraphQL_Cheat_Sheet.html
3. Apple Keychain Services: https://developer.apple.com/documentation/security/keychain_services
4. NIST SP 800-57: Key Management Guidelines
5. RFC 7519: JSON Web Token (JWT)
6. CVSS v3.1 Calculator: https://www.first.org/cvss/calculator/3.1

---

**Report Generated**: 2025-11-10 02:30:00 UTC
**Auditor**: Linus Torvalds (as Security Expert)
**Version**: 1.0
**Classification**: CONFIDENTIAL - Internal Security Review
