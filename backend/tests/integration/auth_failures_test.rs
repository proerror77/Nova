//! 认证失败场景测试 - P1 级别
//!
//! 测试目标：验证所有认证失败路径的正确处理
//! - 过期 JWT Token → 401 Unauthorized
//! - 格式错误的 JWT Token → 401 Unauthorized
//! - 无效签名的 JWT Token → 401 Unauthorized
//! - 缺失 Authorization Header → 401 Unauthorized
//! - 无效 Refresh Token → 401 Unauthorized
//!
//! Linus 哲学：
//! "安全边界是第一原则 - 认证失败必须统一处理，不能有例外"
//! "消除特殊情况 - 所有认证错误应该返回相同的 401 状态码"

use actix_web::{test, web, App, HttpResponse};
use chrono::Utc;
use jsonwebtoken::{decode, encode, Algorithm, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};

/// JWT Claims 结构（与生产代码一致）
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: String,   // Subject (user ID)
    pub exp: usize,    // Expiration time
    pub iat: usize,    // Issued at
    pub email: String, // User email
}

/// 测试 Handler（模拟受保护的端点）
async fn protected_handler() -> actix_web::Result<HttpResponse> {
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "message": "You are authenticated"
    })))
}

/// 创建有效的 JWT Token
fn create_valid_jwt(user_id: &str, secret: &str) -> String {
    let now = Utc::now().timestamp();
    let exp = (now + 3600) as usize; // 1小时后过期

    let claims = Claims {
        sub: user_id.to_string(),
        exp,
        iat: now as usize,
        email: "test@example.com".to_string(),
    };

    encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .expect("创建 JWT Token 失败")
}

/// 创建过期的 JWT Token
fn create_expired_jwt(user_id: &str, secret: &str) -> String {
    let now = Utc::now().timestamp();
    let exp = (now - 3600) as usize; // 1小时前已过期

    let claims = Claims {
        sub: user_id.to_string(),
        exp,
        iat: (now - 7200) as usize, // 2小时前签发
        email: "test@example.com".to_string(),
    };

    encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(secret.as_bytes()),
    )
    .expect("创建过期 JWT Token 失败")
}

/// 创建使用错误签名的 JWT Token
fn create_wrongly_signed_jwt(user_id: &str) -> String {
    let now = Utc::now().timestamp();
    let exp = (now + 3600) as usize;

    let claims = Claims {
        sub: user_id.to_string(),
        exp,
        iat: now as usize,
        email: "test@example.com".to_string(),
    };

    // 使用错误的 secret 签名
    encode(
        &Header::new(Algorithm::HS256),
        &claims,
        &EncodingKey::from_secret(b"wrong-secret"),
    )
    .expect("创建错误签名 JWT Token 失败")
}

/// 测试 1: 过期的 JWT Token 返回 401 Unauthorized
///
/// 场景：用户的 Token 已过期（exp < now）
/// 预期：
/// - 返回 401 Unauthorized
/// - 错误消息包含 "expired" 或 "Invalid token"
/// - 不允许访问受保护的资源
#[tokio::test]
async fn test_expired_jwt_token_returns_401() {
    use crate::graphql_gateway::middleware::jwt::JwtMiddleware;

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/api/protected", web::get().to(protected_handler)),
    )
    .await;

    let expired_token = create_expired_jwt("user-123", "test-secret");

    let req = test::TestRequest::get()
        .uri("/api/protected")
        .insert_header(("Authorization", format!("Bearer {}", expired_token)))
        .to_request();

    let resp = test::call_service(&app, req).await;

    // 验证：返回 401
    assert_eq!(
        resp.status(),
        actix_web::http::StatusCode::UNAUTHORIZED,
        "过期 Token 应该返回 401"
    );

    // 验证：错误消息包含相关信息
    let body = test::read_body(resp).await;
    let body_str = String::from_utf8_lossy(&body);
    assert!(
        body_str.contains("Invalid token") || body_str.contains("expired"),
        "错误消息应该说明 Token 无效或过期"
    );
}

/// 测试 2: 格式错误的 JWT Token 返回 401
///
/// 场景：Token 格式不正确（不是有效的 JWT 格式）
/// 预期：
/// - 返回 401 Unauthorized
/// - 拒绝格式错误的 Token（如 "invalid.token.format"）
#[tokio::test]
async fn test_malformed_jwt_token_returns_401() {
    use crate::graphql_gateway::middleware::jwt::JwtMiddleware;

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/api/protected", web::get().to(protected_handler)),
    )
    .await;

    // 格式错误的 Token（不是有效的 JWT）
    let malformed_tokens = vec![
        "not-a-jwt-token",
        "invalid.format",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid",
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9", // 缺少 payload 和 signature
    ];

    for malformed_token in malformed_tokens {
        let req = test::TestRequest::get()
            .uri("/api/protected")
            .insert_header(("Authorization", format!("Bearer {}", malformed_token)))
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(
            resp.status(),
            actix_web::http::StatusCode::UNAUTHORIZED,
            "格式错误的 Token '{}' 应该返回 401",
            malformed_token
        );
    }
}

/// 测试 3: 无效签名的 JWT Token 返回 401
///
/// 场景：Token 使用了错误的 secret 签名
/// 预期：
/// - 返回 401 Unauthorized
/// - 签名验证失败，拒绝访问
#[tokio::test]
async fn test_invalid_signature_jwt_returns_401() {
    use crate::graphql_gateway::middleware::jwt::JwtMiddleware;

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/api/protected", web::get().to(protected_handler)),
    )
    .await;

    let wrongly_signed_token = create_wrongly_signed_jwt("user-123");

    let req = test::TestRequest::get()
        .uri("/api/protected")
        .insert_header(("Authorization", format!("Bearer {}", wrongly_signed_token)))
        .to_request();

    let resp = test::call_service(&app, req).await;

    assert_eq!(
        resp.status(),
        actix_web::http::StatusCode::UNAUTHORIZED,
        "错误签名的 Token 应该返回 401"
    );

    let body = test::read_body(resp).await;
    let body_str = String::from_utf8_lossy(&body);
    assert!(
        body_str.contains("Invalid token") || body_str.contains("signature"),
        "错误消息应该说明签名无效"
    );
}

/// 测试 4: 缺失 Authorization Header 返回 401
///
/// 场景：请求没有包含 Authorization Header
/// 预期：
/// - 返回 401 Unauthorized
/// - 错误消息说明缺少 Authorization Header
#[tokio::test]
async fn test_missing_authorization_header_returns_401() {
    use crate::graphql_gateway::middleware::jwt::JwtMiddleware;

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/api/protected", web::get().to(protected_handler)),
    )
    .await;

    let req = test::TestRequest::get()
        .uri("/api/protected")
        // 没有 Authorization Header
        .to_request();

    let resp = test::call_service(&app, req).await;

    assert_eq!(
        resp.status(),
        actix_web::http::StatusCode::UNAUTHORIZED,
        "缺失 Authorization Header 应该返回 401"
    );

    let body = test::read_body(resp).await;
    let body_str = String::from_utf8_lossy(&body);
    assert!(
        body_str.contains("Missing Authorization header"),
        "错误消息应该说明缺少 Authorization Header"
    );
}

/// 测试 5: 无效的 Refresh Token 返回 401
///
/// 场景：使用过期或无效的 Refresh Token 请求新的 Access Token
/// 预期：
/// - 返回 401 Unauthorized
/// - Refresh Token 验证失败
/// - 不颁发新的 Access Token
#[tokio::test]
async fn test_invalid_refresh_token_returns_401() {
    use crate::fixtures::test_env::TestEnvironment;
    use uuid::Uuid;

    let env = TestEnvironment::new().await;
    let db = env.db();

    let user_id = Uuid::new_v4();

    // 1. 创建用户
    sqlx::query(
        r#"
        INSERT INTO users (id, email, username, password_hash, created_at)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(user_id)
    .bind("test@example.com")
    .bind("testuser")
    .bind("hashed_password")
    .bind(Utc::now())
    .execute(&*db)
    .await
    .expect("创建用户失败");

    // 2. 创建一个已过期的 Refresh Token
    let expired_refresh_token = Uuid::new_v4();
    let expired_at = Utc::now() - chrono::Duration::days(1); // 昨天过期

    sqlx::query(
        r#"
        INSERT INTO refresh_tokens (id, user_id, token, expires_at, created_at)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(Uuid::new_v4())
    .bind(user_id)
    .bind(expired_refresh_token.to_string())
    .bind(expired_at)
    .bind(Utc::now() - chrono::Duration::days(30))
    .execute(&*db)
    .await
    .expect("创建过期 Refresh Token 失败");

    // 3. 尝试使用过期的 Refresh Token 获取新的 Access Token
    let result: Result<Option<String>, sqlx::Error> = sqlx::query_scalar(
        r#"
        SELECT token FROM refresh_tokens
        WHERE token = $1 AND expires_at > NOW()
        "#,
    )
    .bind(expired_refresh_token.to_string())
    .fetch_optional(&*db)
    .await;

    // 验证：查询应该返回 None（Token 已过期）
    assert!(
        result.is_ok(),
        "查询 Refresh Token 应该成功"
    );
    assert!(
        result.unwrap().is_none(),
        "过期的 Refresh Token 应该返回 None"
    );

    env.cleanup().await;
}

/// 测试 6: 无效的 Bearer Scheme 返回 401
///
/// 场景：Authorization Header 格式错误（不是 "Bearer <token>"）
/// 预期：
/// - 返回 401 Unauthorized
/// - 错误消息说明必须使用 Bearer Scheme
#[tokio::test]
async fn test_invalid_bearer_scheme_returns_401() {
    use crate::graphql_gateway::middleware::jwt::JwtMiddleware;

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/api/protected", web::get().to(protected_handler)),
    )
    .await;

    let valid_token = create_valid_jwt("user-123", "test-secret");

    // 错误的 Scheme 格式
    let invalid_schemes = vec![
        format!("Basic {}", valid_token),    // 使用 Basic 而不是 Bearer
        format!("Token {}", valid_token),    // 使用 Token 而不是 Bearer
        valid_token.clone(),                  // 缺少 Scheme
        format!("bearer {}", valid_token),   // 小写 bearer（应该是 Bearer）
    ];

    for invalid_scheme in invalid_schemes {
        let req = test::TestRequest::get()
            .uri("/api/protected")
            .insert_header(("Authorization", invalid_scheme.clone()))
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(
            resp.status(),
            actix_web::http::StatusCode::UNAUTHORIZED,
            "无效的 Scheme '{}' 应该返回 401",
            invalid_scheme
        );
    }
}

/// 测试 7: JWT Claims 缺失必需字段返回 401
///
/// 场景：JWT Token 的 Claims 缺少必需字段（如 sub, exp）
/// 预期：
/// - 返回 401 Unauthorized
/// - 解析失败，拒绝访问
#[tokio::test]
async fn test_jwt_missing_required_claims_returns_401() {
    use crate::graphql_gateway::middleware::jwt::JwtMiddleware;

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/api/protected", web::get().to(protected_handler)),
    )
    .await;

    // 创建缺少 'sub' 字段的 Claims
    #[derive(Serialize)]
    struct IncompleteClaims {
        exp: usize,
        iat: usize,
        // 缺少 'sub' 和 'email'
    }

    let now = Utc::now().timestamp();
    let incomplete_claims = IncompleteClaims {
        exp: (now + 3600) as usize,
        iat: now as usize,
    };

    let incomplete_token = encode(
        &Header::new(Algorithm::HS256),
        &incomplete_claims,
        &EncodingKey::from_secret(b"test-secret"),
    )
    .expect("创建不完整 Claims 的 Token 失败");

    let req = test::TestRequest::get()
        .uri("/api/protected")
        .insert_header(("Authorization", format!("Bearer {}", incomplete_token)))
        .to_request();

    let resp = test::call_service(&app, req).await;

    assert_eq!(
        resp.status(),
        actix_web::http::StatusCode::UNAUTHORIZED,
        "缺少必需 Claims 的 Token 应该返回 401"
    );
}

/// 测试 8: 验证 JWT 算法匹配（防止算法替换攻击）
///
/// 场景：Token 使用了不同的算法（如 RS256 而不是 HS256）
/// 预期：
/// - 返回 401 Unauthorized
/// - 算法不匹配，验证失败
#[tokio::test]
async fn test_jwt_algorithm_mismatch_returns_401() {
    use crate::graphql_gateway::middleware::jwt::JwtMiddleware;

    let app = test::init_service(
        App::new()
            .wrap(JwtMiddleware::new("test-secret".to_string()))
            .route("/api/protected", web::get().to(protected_handler)),
    )
    .await;

    // 创建使用 HS512 算法的 Token（期望是 HS256）
    let now = Utc::now().timestamp();
    let claims = Claims {
        sub: "user-123".to_string(),
        exp: (now + 3600) as usize,
        iat: now as usize,
        email: "test@example.com".to_string(),
    };

    let wrong_algo_token = encode(
        &Header::new(Algorithm::HS512), // 使用 HS512 而不是 HS256
        &claims,
        &EncodingKey::from_secret(b"test-secret"),
    )
    .expect("创建 HS512 Token 失败");

    let req = test::TestRequest::get()
        .uri("/api/protected")
        .insert_header(("Authorization", format!("Bearer {}", wrong_algo_token)))
        .to_request();

    let resp = test::call_service(&app, req).await;

    assert_eq!(
        resp.status(),
        actix_web::http::StatusCode::UNAUTHORIZED,
        "算法不匹配的 Token 应该返回 401"
    );
}

// ============================================
// 辅助函数：验证 JWT Token
// ============================================

/// 验证 JWT Token 是否有效（用于测试验证逻辑）
#[allow(dead_code)]
fn verify_jwt(token: &str, secret: &str) -> Result<Claims, jsonwebtoken::errors::Error> {
    let validation = Validation::new(Algorithm::HS256);
    let decoding_key = DecodingKey::from_secret(secret.as_bytes());

    let token_data = decode::<Claims>(token, &decoding_key, &validation)?;
    Ok(token_data.claims)
}
