# OAuth Token Verification

本文档说明如何使用新实现的 OAuth token 验证功能。

## 概述

我们实现了三个 OAuth 提供商的 token 验证功能：
- **Apple Sign In**: 使用 JWT 公钥验证 ID token
- **Google OAuth**: 使用 tokeninfo 端点验证 ID token
- **Facebook OAuth**: 使用 debug_token 端点验证 access token

## 功能实现

### 2.1.1 Apple Sign In

**实现文件**: `backend/user-service/src/services/oauth/apple.rs`

**核心函数**: `verify_apple_token()`

**工作原理**:
1. 从 `https://appleid.apple.com/auth/keys` 获取 Apple 的公钥（JWKS）
2. 解析 JWT header，提取 `kid` (key ID)
3. 在 JWKS 中查找匹配的公钥
4. 使用 `jsonwebtoken` 库验证 JWT 签名
5. 验证 `aud` (audience) 和 `iss` (issuer) claims
6. 返回用户信息（sub, email, email_verified）

**使用示例**:
```rust
use user_service::services::oauth::apple::AppleOAuthProvider;

let provider = AppleOAuthProvider::new()?;
let id_token = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...";

match provider.verify_apple_token(id_token).await {
    Ok(user_info) => {
        println!("User ID: {}", user_info.sub);
        println!("Email: {}", user_info.email);
    }
    Err(e) => eprintln!("Verification failed: {}", e),
}
```

**环境变量**:
- `APPLE_CLIENT_ID`: Apple 应用的 client ID（用于验证 audience）
- `APPLE_TEAM_ID`: Apple 开发者团队 ID
- `APPLE_KEY_ID`: Apple 私钥 ID
- `APPLE_PRIVATE_KEY`: Apple 私钥（PEM 格式）
- `APPLE_REDIRECT_URI`: 重定向 URI

### 2.1.2 Google OAuth

**实现文件**: `backend/user-service/src/services/oauth/google.rs`

**核心函数**: `verify_google_token()`

**工作原理**:
1. 调用 `https://oauth2.googleapis.com/tokeninfo?id_token=<token>` 验证 token
2. 检查 HTTP 响应状态码
3. 验证 `aud` (audience) 是否匹配 client ID
4. 使用 access token 从 `https://openidconnect.googleapis.com/v1/userinfo` 获取用户信息
5. 返回用户信息（sub, email, name, picture）

**使用示例**:
```rust
use user_service::services::oauth::google::GoogleOAuthProvider;

let provider = GoogleOAuthProvider::new()?;
let id_token = "ya29.a0AfH6SMBx...";

match provider.verify_google_token(id_token).await {
    Ok(user_info) => {
        println!("User ID: {}", user_info.sub);
        println!("Email: {}", user_info.email);
        println!("Name: {:?}", user_info.name);
        println!("Picture: {:?}", user_info.picture);
    }
    Err(e) => eprintln!("Verification failed: {}", e),
}
```

**环境变量**:
- `GOOGLE_CLIENT_ID`: Google 应用的 client ID
- `GOOGLE_CLIENT_SECRET`: Google 应用的 client secret
- `GOOGLE_REDIRECT_URI`: 重定向 URI

### 2.1.3 Facebook OAuth

**实现文件**: `backend/user-service/src/services/oauth/facebook.rs`

**核心函数**: `verify_facebook_token()`

**工作原理**:
1. 使用 app access token (`{client_id}|{client_secret}`) 作为验证凭证
2. 调用 `https://graph.facebook.com/v18.0/debug_token` 验证 access token
3. 检查 token 是否有效 (`is_valid`)
4. 验证 `app_id` 是否匹配
5. 使用验证过的 token 从 `https://graph.facebook.com/v18.0/me` 获取用户信息
6. 返回用户信息（id, email, name, picture）

**使用示例**:
```rust
use user_service::services::oauth::facebook::FacebookOAuthProvider;

let provider = FacebookOAuthProvider::new()?;
let access_token = "EAABwzLixnjYBO...";

match provider.verify_facebook_token(access_token).await {
    Ok(user_info) => {
        println!("User ID: {}", user_info.id);
        println!("Email: {}", user_info.email);
        println!("Name: {:?}", user_info.name);
        if let Some(picture) = user_info.picture {
            if let Some(data) = picture.data {
                println!("Picture URL: {:?}", data.url);
            }
        }
    }
    Err(e) => eprintln!("Verification failed: {}", e),
}
```

**环境变量**:
- `FACEBOOK_CLIENT_ID`: Facebook 应用的 app ID
- `FACEBOOK_CLIENT_SECRET`: Facebook 应用的 app secret
- `FACEBOOK_REDIRECT_URI`: 重定向 URI

## 错误处理

所有验证函数都返回 `Result<UserInfo, OAuthError>`，其中 `OAuthError` 包含以下变体：

```rust
pub enum OAuthError {
    InvalidAuthCode(String),    // JWT 无效或解析失败
    TokenExchange(String),      // Token 交换失败
    UserInfoFetch(String),      // 获取用户信息失败
    NetworkError(String),       // 网络请求失败
    ConfigError(String),        // 配置错误（环境变量缺失）
    InvalidState,               // State 参数验证失败
    ProviderError(String),      // OAuth 提供商返回错误
}
```

**错误处理示例**:
```rust
match provider.verify_google_token(token).await {
    Ok(user_info) => {
        // 处理成功情况
    }
    Err(OAuthError::InvalidAuthCode(msg)) => {
        // Token 无效 - 返回 401 Unauthorized
        eprintln!("Invalid token: {}", msg);
    }
    Err(OAuthError::NetworkError(msg)) => {
        // 网络问题 - 返回 503 Service Unavailable
        eprintln!("Network error: {}", msg);
    }
    Err(OAuthError::ConfigError(msg)) => {
        // 配置问题 - 返回 500 Internal Server Error
        eprintln!("Configuration error: {}", msg);
    }
    Err(e) => {
        // 其他错误
        eprintln!("Unexpected error: {}", e);
    }
}
```

## 安全考虑

1. **Token 存储**: OAuth tokens 在数据库中以 SHA256 hash 存储，而不是明文
2. **HTTPS**: 所有 OAuth API 调用都使用 HTTPS
3. **Token 过期**: 验证 token 时会检查过期时间
4. **Audience 验证**: Apple 和 Google token 验证都会检查 audience 是否匹配
5. **App ID 验证**: Facebook token 验证会检查 app_id 是否匹配

## 测试

### 单元测试

运行 token 验证测试：
```bash
cd backend/user-service
cargo test --test oauth_token_verification_test
```

### 集成测试

运行完整 OAuth 流程测试：
```bash
cargo test --test oauth_test
```

## 性能优化

1. **HTTP 连接池**: 使用 `reqwest::Client` 的连接池复用 HTTP 连接
2. **异步操作**: 所有网络请求都是异步的，避免阻塞
3. **缓存公钥**: 可以考虑缓存 Apple 的 JWKS 公钥（当前每次验证都会获取）

## 未来改进

1. **公钥缓存**: Apple JWKS 公钥应该缓存到 Redis，避免每次验证都请求
2. **重试机制**: 网络请求失败时应该有重试逻辑
3. **监控指标**: 添加 Prometheus 指标跟踪验证成功率和延迟
4. **Token 刷新**: 实现自动刷新过期 token 的逻辑

## API 端点集成

这些验证函数应该在以下 API 端点中使用：

1. **POST /api/auth/oauth/apple** - Apple Sign In
2. **POST /api/auth/oauth/google** - Google OAuth
3. **POST /api/auth/oauth/facebook** - Facebook OAuth

每个端点应该：
1. 接收前端传来的 token
2. 使用相应的 `verify_*_token()` 函数验证
3. 查找或创建用户账户
4. 创建或更新 OAuth 连接
5. 返回 JWT access token 给前端

## 参考资料

- [Apple Sign In REST API](https://developer.apple.com/documentation/sign_in_with_apple/sign_in_with_apple_rest_api)
- [Google OAuth 2.0 API](https://developers.google.com/identity/protocols/oauth2)
- [Facebook Login API](https://developers.facebook.com/docs/facebook-login/web)
- [jsonwebtoken 库文档](https://docs.rs/jsonwebtoken/)
- [reqwest 库文档](https://docs.rs/reqwest/)
