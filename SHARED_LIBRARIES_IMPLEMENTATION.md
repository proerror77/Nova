# Shared Libraries Implementation Guide

**目标**: 为 video-service 迁移创建可复用的共享库
**原则**: DRY (Don't Repeat Yourself) + 单一职责

---

## 📦 共享库架构

```
backend/libs/
├── auth-middleware/          # JWT 认证中间件
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs           # UserId, JwtAuthMiddleware
│   │   └── tests.rs
│   └── README.md
│
├── error-types/              # 统一错误响应格式
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs           # ErrorResponse, error_codes
│   │   └── tests.rs
│   └── README.md
│
├── resilience/               # 熔断器、重试逻辑 (可选)
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs
│   │   ├── circuit_breaker.rs
│   │   ├── retry.rs
│   │   └── timeout.rs
│   └── README.md
│
└── crypto-core/              # 加密工具 (已存在)
    └── ...
```

---

## 🔐 Library 1: auth-middleware

### 目录结构
```
backend/libs/auth-middleware/
├── Cargo.toml
├── README.md
└── src/
    ├── lib.rs
    ├── jwt.rs
    ├── middleware.rs
    └── tests.rs
```

### Cargo.toml
```toml
[package]
name = "auth-middleware"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4.4"
jsonwebtoken = "9.2"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
uuid = { version = "1.6", features = ["v4", "serde"] }
chrono = { version = "0.4", features = ["serde"] }
thiserror = "1.0"
tracing = "0.1"

[dev-dependencies]
tokio = { version = "1.35", features = ["full"] }
actix-rt = "2.9"
```

### src/lib.rs
```rust
//! Authentication middleware for Nova services
//!
//! Provides JWT token validation and user ID extraction for Actix Web services.
//!
//! # Usage
//!
//! ```rust
//! use actix_web::{web, App, HttpServer};
//! use auth_middleware::{JwtAuthMiddleware, UserId};
//!
//! async fn protected_handler(user_id: UserId) -> String {
//!     format!("Hello user: {}", user_id.0)
//! }
//!
//! #[actix_web::main]
//! async fn main() -> std::io::Result<()> {
//!     HttpServer::new(|| {
//!         App::new()
//!             .wrap(JwtAuthMiddleware::new("your-secret-key"))
//!             .route("/protected", web::get().to(protected_handler))
//!     })
//!     .bind("127.0.0.1:8080")?
//!     .run()
//!     .await
//! }
//! ```

mod jwt;
mod middleware;

pub use jwt::{Claims, JwtService};
pub use middleware::{JwtAuthMiddleware, UserId};

use thiserror::Error;

#[derive(Debug, Error)]
pub enum AuthError {
    #[error("Invalid token: {0}")]
    InvalidToken(String),

    #[error("Token expired")]
    TokenExpired,

    #[error("Missing authorization header")]
    MissingAuth,

    #[error("Invalid authorization header format")]
    InvalidAuthFormat,

    #[error("User not found")]
    UserNotFound,
}
```

### src/jwt.rs
```rust
use chrono::{Duration, Utc};
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::AuthError;

/// JWT claims structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Claims {
    /// Subject (user ID)
    pub sub: String,
    /// Issued at (Unix timestamp)
    pub iat: i64,
    /// Expiration time (Unix timestamp)
    pub exp: i64,
    /// User ID (redundant with sub, but convenient)
    pub user_id: Uuid,
}

impl Claims {
    /// Create new claims for a user
    pub fn new(user_id: Uuid, ttl_seconds: i64) -> Self {
        let now = Utc::now();
        Self {
            sub: user_id.to_string(),
            iat: now.timestamp(),
            exp: (now + Duration::seconds(ttl_seconds)).timestamp(),
            user_id,
        }
    }

    /// Check if token is expired
    pub fn is_expired(&self) -> bool {
        Utc::now().timestamp() > self.exp
    }
}

/// JWT service for token generation and validation
pub struct JwtService {
    encoding_key: EncodingKey,
    decoding_key: DecodingKey,
    validation: Validation,
}

impl JwtService {
    /// Create new JWT service with HS256 algorithm
    pub fn new(secret: &str) -> Self {
        let mut validation = Validation::new(Algorithm::HS256);
        validation.leeway = 60; // 60 seconds leeway for clock skew

        Self {
            encoding_key: EncodingKey::from_secret(secret.as_bytes()),
            decoding_key: DecodingKey::from_secret(secret.as_bytes()),
            validation,
        }
    }

    /// Create JWT service with RS256 algorithm (recommended for production)
    pub fn new_rs256(
        private_key_pem: &str,
        public_key_pem: &str,
    ) -> Result<Self, AuthError> {
        let encoding_key = EncodingKey::from_rsa_pem(private_key_pem.as_bytes())
            .map_err(|e| AuthError::InvalidToken(format!("Invalid private key: {}", e)))?;

        let decoding_key = DecodingKey::from_rsa_pem(public_key_pem.as_bytes())
            .map_err(|e| AuthError::InvalidToken(format!("Invalid public key: {}", e)))?;

        let mut validation = Validation::new(Algorithm::RS256);
        validation.leeway = 60;

        Ok(Self {
            encoding_key,
            decoding_key,
            validation,
        })
    }

    /// Generate JWT token for a user
    pub fn generate_token(&self, user_id: Uuid, ttl_seconds: i64) -> Result<String, AuthError> {
        let claims = Claims::new(user_id, ttl_seconds);
        let header = Header::new(Algorithm::HS256);

        encode(&header, &claims, &self.encoding_key)
            .map_err(|e| AuthError::InvalidToken(format!("Failed to encode token: {}", e)))
    }

    /// Validate JWT token and extract claims
    pub fn validate_token(&self, token: &str) -> Result<Claims, AuthError> {
        let token_data = decode::<Claims>(token, &self.decoding_key, &self.validation)
            .map_err(|e| match e.kind() {
                jsonwebtoken::errors::ErrorKind::ExpiredSignature => AuthError::TokenExpired,
                _ => AuthError::InvalidToken(format!("Token validation failed: {}", e)),
            })?;

        Ok(token_data.claims)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_jwt_generation_and_validation() {
        let jwt_service = JwtService::new("test-secret-key");
        let user_id = Uuid::new_v4();

        // Generate token
        let token = jwt_service.generate_token(user_id, 3600).unwrap();
        assert!(!token.is_empty());

        // Validate token
        let claims = jwt_service.validate_token(&token).unwrap();
        assert_eq!(claims.user_id, user_id);
        assert!(!claims.is_expired());
    }

    #[test]
    fn test_expired_token() {
        let jwt_service = JwtService::new("test-secret-key");
        let user_id = Uuid::new_v4();

        // Generate token with -1 second TTL (already expired)
        let token = jwt_service.generate_token(user_id, -1).unwrap();

        // Validation should fail with TokenExpired
        let result = jwt_service.validate_token(&token);
        assert!(matches!(result, Err(AuthError::TokenExpired)));
    }
}
```

### src/middleware.rs
```rust
use actix_web::{
    dev::{Service, ServiceRequest, ServiceResponse, Transform},
    error::ErrorUnauthorized,
    Error, FromRequest, HttpMessage, HttpRequest,
};
use futures_util::future::{ready, LocalBoxFuture, Ready};
use std::{
    ops::Deref,
    rc::Rc,
    task::{Context, Poll},
};
use uuid::Uuid;

use crate::{jwt::JwtService, AuthError};

/// Wrapper for authenticated user ID
///
/// Extract in handlers using `UserId` extractor:
/// ```rust
/// async fn handler(user_id: UserId) -> String {
///     format!("User: {}", user_id.0)
/// }
/// ```
#[derive(Debug, Clone, Copy)]
pub struct UserId(pub Uuid);

impl Deref for UserId {
    type Target = Uuid;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl FromRequest for UserId {
    type Error = Error;
    type Future = Ready<Result<Self, Self::Error>>;

    fn from_request(req: &HttpRequest, _: &mut actix_web::dev::Payload) -> Self::Future {
        ready(
            req.extensions()
                .get::<UserId>()
                .copied()
                .ok_or_else(|| ErrorUnauthorized("User ID not found in request"))
        )
    }
}

/// JWT Authentication Middleware
///
/// Validates JWT tokens from Authorization header and injects UserId into request extensions.
pub struct JwtAuthMiddleware {
    jwt_service: Rc<JwtService>,
}

impl JwtAuthMiddleware {
    pub fn new(secret: &str) -> Self {
        Self {
            jwt_service: Rc::new(JwtService::new(secret)),
        }
    }

    pub fn new_rs256(private_key_pem: &str, public_key_pem: &str) -> Result<Self, AuthError> {
        Ok(Self {
            jwt_service: Rc::new(JwtService::new_rs256(private_key_pem, public_key_pem)?),
        })
    }
}

impl<S, B> Transform<S, ServiceRequest> for JwtAuthMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = JwtAuthMiddlewareService<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(JwtAuthMiddlewareService {
            service: Rc::new(service),
            jwt_service: self.jwt_service.clone(),
        }))
    }
}

pub struct JwtAuthMiddlewareService<S> {
    service: Rc<S>,
    jwt_service: Rc<JwtService>,
}

impl<S, B> Service<ServiceRequest> for JwtAuthMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error> + 'static,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    fn poll_ready(&self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.service.poll_ready(cx)
    }

    fn call(&self, req: ServiceRequest) -> Self::Future {
        let jwt_service = self.jwt_service.clone();
        let service = self.service.clone();

        Box::pin(async move {
            // Extract Authorization header
            let auth_header = req
                .headers()
                .get("Authorization")
                .and_then(|h| h.to_str().ok())
                .ok_or_else(|| ErrorUnauthorized("Missing Authorization header"))?;

            // Parse Bearer token
            let token = auth_header
                .strip_prefix("Bearer ")
                .ok_or_else(|| ErrorUnauthorized("Invalid Authorization header format"))?;

            // Validate token
            let claims = jwt_service
                .validate_token(token)
                .map_err(|e| ErrorUnauthorized(e.to_string()))?;

            // Insert UserId into request extensions
            req.extensions_mut().insert(UserId(claims.user_id));

            // Continue to next middleware/handler
            service.call(req).await
        })
    }
}
```

### src/tests.rs
```rust
#[cfg(test)]
mod integration_tests {
    use super::*;
    use actix_web::{test, web, App, HttpResponse};

    async fn protected_handler(user_id: UserId) -> HttpResponse {
        HttpResponse::Ok().body(format!("User: {}", user_id.0))
    }

    #[actix_web::test]
    async fn test_auth_middleware_valid_token() {
        let jwt_service = JwtService::new("test-secret");
        let user_id = Uuid::new_v4();
        let token = jwt_service.generate_token(user_id, 3600).unwrap();

        let app = test::init_service(
            App::new()
                .wrap(JwtAuthMiddleware::new("test-secret"))
                .route("/protected", web::get().to(protected_handler))
        ).await;

        let req = test::TestRequest::get()
            .uri("/protected")
            .insert_header(("Authorization", format!("Bearer {}", token)))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 200);
    }

    #[actix_web::test]
    async fn test_auth_middleware_missing_token() {
        let app = test::init_service(
            App::new()
                .wrap(JwtAuthMiddleware::new("test-secret"))
                .route("/protected", web::get().to(protected_handler))
        ).await;

        let req = test::TestRequest::get()
            .uri("/protected")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 401);
    }

    #[actix_web::test]
    async fn test_auth_middleware_invalid_token() {
        let app = test::init_service(
            App::new()
                .wrap(JwtAuthMiddleware::new("test-secret"))
                .route("/protected", web::get().to(protected_handler))
        ).await;

        let req = test::TestRequest::get()
            .uri("/protected")
            .insert_header(("Authorization", "Bearer invalid-token"))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 401);
    }
}
```

### README.md
```markdown
# auth-middleware

JWT authentication middleware for Nova microservices.

## Features

- JWT token validation (HS256 and RS256)
- User ID extraction and injection
- Actix Web middleware integration
- Comprehensive error handling

## Usage

### Add to Cargo.toml

```toml
[dependencies]
auth-middleware = { path = "../libs/auth-middleware" }
```

### Basic Setup

```rust
use actix_web::{web, App, HttpServer};
use auth_middleware::{JwtAuthMiddleware, UserId};

async fn protected_handler(user_id: UserId) -> String {
    format!("Hello user: {}", user_id.0)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .wrap(JwtAuthMiddleware::new("your-secret-key"))
            .route("/protected", web::get().to(protected_handler))
    })
    .bind("127.0.0.1:8080")?
    .run()
    .await
}
```

### RS256 (Production)

```rust
let private_key = std::fs::read_to_string("private.pem")?;
let public_key = std::fs::read_to_string("public.pem")?;

let middleware = JwtAuthMiddleware::new_rs256(&private_key, &public_key)?;

HttpServer::new(move || {
    App::new()
        .wrap(middleware.clone())
        // ... routes
})
```

## Testing

```bash
cargo test
```
```

---

## 📋 Library 2: error-types

### 目录结构
```
backend/libs/error-types/
├── Cargo.toml
├── README.md
└── src/
    ├── lib.rs
    └── tests.rs
```

### Cargo.toml
```toml
[package]
name = "error-types"
version = "0.1.0"
edition = "2021"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
```

### src/lib.rs
```rust
//! Standardized error response types for Nova services
//!
//! Provides consistent error format across all microservices:
//! ```json
//! {
//!   "error": "Not Found",
//!   "message": "Video with ID 123 not found",
//!   "status": 404,
//!   "type": "not_found_error",
//!   "code": "VIDEO_NOT_FOUND",
//!   "details": null,
//!   "timestamp": "2025-10-30T12:34:56Z"
//! }
//! ```

use serde::{Deserialize, Serialize};

/// Standardized error response
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorResponse {
    /// HTTP error title (e.g., "Not Found", "Bad Request")
    pub error: String,

    /// Human-readable error message
    pub message: String,

    /// HTTP status code
    pub status: u16,

    /// Error type category (e.g., "validation_error", "database_error")
    #[serde(rename = "type")]
    pub error_type: String,

    /// Machine-readable error code (e.g., "VIDEO_NOT_FOUND")
    pub code: String,

    /// Optional additional details (e.g., SQL error message)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,

    /// ISO8601 timestamp when error occurred
    pub timestamp: String,
}

impl ErrorResponse {
    pub fn new(
        error: &str,
        message: &str,
        status: u16,
        error_type: &str,
        code: &str,
    ) -> Self {
        Self {
            error: error.to_string(),
            message: message.to_string(),
            status,
            error_type: error_type.to_string(),
            code: code.to_string(),
            details: None,
            timestamp: chrono::Utc::now().to_rfc3339(),
        }
    }

    pub fn with_details(mut self, details: String) -> Self {
        self.details = Some(details);
        self
    }
}

/// Standard error codes used across services
pub mod error_codes {
    // Authentication errors (1xxx)
    pub const TOKEN_INVALID: &str = "TOKEN_INVALID";
    pub const TOKEN_EXPIRED: &str = "TOKEN_EXPIRED";
    pub const INVALID_CREDENTIALS: &str = "INVALID_CREDENTIALS";

    // Database errors (2xxx)
    pub const DATABASE_ERROR: &str = "DATABASE_ERROR";
    pub const CACHE_ERROR: &str = "CACHE_ERROR";

    // Resource errors (3xxx)
    pub const USER_NOT_FOUND: &str = "USER_NOT_FOUND";
    pub const VIDEO_NOT_FOUND: &str = "VIDEO_NOT_FOUND";
    pub const POST_NOT_FOUND: &str = "POST_NOT_FOUND";

    // Validation errors (4xxx)
    pub const VALIDATION_ERROR: &str = "VALIDATION_ERROR";
    pub const INVALID_FILE_FORMAT: &str = "INVALID_FILE_FORMAT";
    pub const FILE_SIZE_EXCEEDED: &str = "FILE_SIZE_EXCEEDED";

    // Service errors (5xxx)
    pub const INTERNAL_SERVER_ERROR: &str = "INTERNAL_SERVER_ERROR";
    pub const SERVICE_UNAVAILABLE: &str = "SERVICE_UNAVAILABLE";
    pub const RATE_LIMIT_ERROR: &str = "RATE_LIMIT_EXCEEDED";
    pub const VERSION_CONFLICT: &str = "VERSION_CONFLICT";
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_response_creation() {
        let error = ErrorResponse::new(
            "Not Found",
            "Video not found",
            404,
            "not_found_error",
            error_codes::VIDEO_NOT_FOUND,
        );

        assert_eq!(error.status, 404);
        assert_eq!(error.code, error_codes::VIDEO_NOT_FOUND);
        assert!(error.details.is_none());
    }

    #[test]
    fn test_error_response_with_details() {
        let error = ErrorResponse::new(
            "Database Error",
            "Query failed",
            500,
            "database_error",
            error_codes::DATABASE_ERROR,
        ).with_details("Connection timeout".to_string());

        assert!(error.details.is_some());
        assert_eq!(error.details.unwrap(), "Connection timeout");
    }

    #[test]
    fn test_error_response_serialization() {
        let error = ErrorResponse::new(
            "Bad Request",
            "Invalid input",
            400,
            "validation_error",
            error_codes::VALIDATION_ERROR,
        );

        let json = serde_json::to_string(&error).unwrap();
        assert!(json.contains("Bad Request"));
        assert!(json.contains("VALIDATION_ERROR"));
    }
}
```

---

## 🔄 Library 3: resilience (可选)

### Cargo.toml
```toml
[package]
name = "resilience"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.35", features = ["time", "sync"] }
thiserror = "1.0"
tracing = "0.1"

[dev-dependencies]
tokio = { version = "1.35", features = ["full"] }
```

### src/circuit_breaker.rs
```rust
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CircuitState {
    Closed,
    Open,
    HalfOpen,
}

pub struct CircuitBreakerConfig {
    pub failure_threshold: u32,
    pub success_threshold: u32,
    pub timeout: Duration,
}

impl Default for CircuitBreakerConfig {
    fn default() -> Self {
        Self {
            failure_threshold: 5,
            success_threshold: 2,
            timeout: Duration::from_secs(60),
        }
    }
}

pub struct CircuitBreaker {
    state: Arc<RwLock<CircuitBreakerState>>,
    config: CircuitBreakerConfig,
}

struct CircuitBreakerState {
    state: CircuitState,
    failure_count: u32,
    success_count: u32,
    last_failure_time: Option<Instant>,
}

impl CircuitBreaker {
    pub fn new(config: CircuitBreakerConfig) -> Self {
        Self {
            state: Arc::new(RwLock::new(CircuitBreakerState {
                state: CircuitState::Closed,
                failure_count: 0,
                success_count: 0,
                last_failure_time: None,
            })),
            config,
        }
    }

    pub async fn call<F, Fut, T, E>(&self, f: F) -> Result<T, E>
    where
        F: FnOnce() -> Fut,
        Fut: std::future::Future<Output = Result<T, E>>,
    {
        // 检查熔断器状态
        let should_attempt = {
            let mut state = self.state.write().await;
            match state.state {
                CircuitState::Open => {
                    if let Some(last_failure) = state.last_failure_time {
                        if last_failure.elapsed() > self.config.timeout {
                            state.state = CircuitState::HalfOpen;
                            state.success_count = 0;
                            true
                        } else {
                            false
                        }
                    } else {
                        false
                    }
                }
                _ => true,
            }
        };

        if !should_attempt {
            return Err(/* Return circuit open error */);
        }

        // 执行函数
        match f().await {
            Ok(result) => {
                self.on_success().await;
                Ok(result)
            }
            Err(error) => {
                self.on_failure().await;
                Err(error)
            }
        }
    }

    async fn on_success(&self) {
        let mut state = self.state.write().await;
        match state.state {
            CircuitState::HalfOpen => {
                state.success_count += 1;
                if state.success_count >= self.config.success_threshold {
                    state.state = CircuitState::Closed;
                    state.failure_count = 0;
                    state.success_count = 0;
                }
            }
            _ => {
                state.failure_count = 0;
            }
        }
    }

    async fn on_failure(&self) {
        let mut state = self.state.write().await;
        state.failure_count += 1;
        state.last_failure_time = Some(Instant::now());

        if state.failure_count >= self.config.failure_threshold {
            state.state = CircuitState::Open;
        }
    }
}
```

---

## 📘 使用示例

### 在 video-service 中使用

**Cargo.toml**:
```toml
[dependencies]
auth-middleware = { path = "../libs/auth-middleware" }
error-types = { path = "../libs/error-types" }
resilience = { path = "../libs/resilience" }
```

**main.rs**:
```rust
use actix_web::{web, App, HttpServer};
use auth_middleware::JwtAuthMiddleware;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // 加载配置
    let config = Config::from_env().expect("Failed to load config");

    // 创建 JWT middleware
    let jwt_middleware = JwtAuthMiddleware::new(&config.jwt.secret);

    HttpServer::new(move || {
        App::new()
            .wrap(jwt_middleware.clone())
            .configure(routes::configure)
    })
    .bind(("0.0.0.0", 8081))?
    .run()
    .await
}
```

**handlers/videos.rs**:
```rust
use auth_middleware::UserId;
use error_types::{ErrorResponse, error_codes};

pub async fn get_video(
    user_id: UserId,  // 自动从 JWT 提取
    path: web::Path<Uuid>,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse, VideoServiceError> {
    let video_id = path.into_inner();

    let video = video_repo::get_video(pool.get_ref(), video_id)
        .await?
        .ok_or_else(|| {
            VideoServiceError::NotFound(format!("Video {} not found", video_id))
        })?;

    Ok(HttpResponse::Ok().json(video))
}
```

---

## ✅ 验收标准

### auth-middleware
- [ ] HS256 JWT 验证通过
- [ ] RS256 JWT 验证通过
- [ ] UserId 提取器工作正常
- [ ] 单元测试覆盖率 > 90%
- [ ] 集成测试通过

### error-types
- [ ] ErrorResponse 序列化正确
- [ ] 所有 error_codes 定义完整
- [ ] 文档清晰

### resilience (可选)
- [ ] CircuitBreaker 状态机正常
- [ ] 超时重试逻辑正确
- [ ] 并发安全

---

## 🚀 部署步骤

### 1. 创建共享库
```bash
mkdir -p backend/libs/auth-middleware
mkdir -p backend/libs/error-types
mkdir -p backend/libs/resilience
```

### 2. 复制代码到对应目录

### 3. 测试每个库
```bash
cd backend/libs/auth-middleware
cargo test

cd backend/libs/error-types
cargo test

cd backend/libs/resilience
cargo test
```

### 4. 在 video-service 中引用
```toml
[dependencies]
auth-middleware = { path = "../libs/auth-middleware" }
error-types = { path = "../libs/error-types" }
```

### 5. 验证编译
```bash
cd backend/video-service
cargo build
```

---

**生成日期**: 2025-10-30
**工具**: Linus Shared Libraries Guide
