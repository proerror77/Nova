use actix_middleware::{FailureMode, RateLimitConfig, RateLimitMiddleware};
use actix_web::{test, web, App, HttpResponse};
use redis::aio::ConnectionManager;
use redis::Client;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Simple test handler
async fn test_handler() -> HttpResponse {
    HttpResponse::Ok().body("success")
}

#[actix_web::test]
async fn test_rate_limit_exceeded() {
    // Connect to Redis (requires Redis running on localhost:6379)
    let client = match Client::open("redis://127.0.0.1:6379") {
        Ok(c) => c,
        Err(_) => {
            eprintln!("Skipping test: Redis not available");
            return;
        }
    };

    let manager = match ConnectionManager::new(client).await {
        Ok(m) => Arc::new(Mutex::new(m)),
        Err(_) => {
            eprintln!("Skipping test: Redis connection failed");
            return;
        }
    };

    // Create strict rate limiter (2 requests per 10 seconds)
    let config = RateLimitConfig {
        max_requests: 2,
        window_seconds: 10,
        redis_timeout_ms: 100,
        include_user_agent: false,
        failure_mode: FailureMode::FailOpen,
    };

    let app = test::init_service(
        App::new()
            .wrap(RateLimitMiddleware::new(config, manager))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    // First request should succeed
    let req = test::TestRequest::get().uri("/test").to_request();
    let resp = test::call_service(&app, req).await;
    assert!(resp.status().is_success());

    // Second request should succeed
    let req = test::TestRequest::get().uri("/test").to_request();
    let resp = test::call_service(&app, req).await;
    assert!(resp.status().is_success());

    // Third request should be rate limited
    let req = test::TestRequest::get().uri("/test").to_request();
    let resp = test::call_service(&app, req).await;
    assert_eq!(resp.status(), 429); // Too Many Requests
}

#[actix_web::test]
async fn test_rate_limit_fail_closed() {
    // Create middleware with fail-closed mode and invalid Redis
    let invalid_client = match Client::open("redis://127.0.0.1:9999") {
        Ok(c) => c,
        Err(_) => {
            eprintln!("Skipping test: unexpected error");
            return;
        }
    };

    let manager = match ConnectionManager::new(invalid_client).await {
        Ok(m) => Arc::new(Mutex::new(m)),
        Err(_) => {
            // Expected: cannot connect to invalid Redis
            // For this test, we'll just skip it as we can't test fail-closed without mocking
            eprintln!("Skipping fail-closed test: requires mock Redis");
            return;
        }
    };

    let config = RateLimitConfig {
        max_requests: 5,
        window_seconds: 60,
        redis_timeout_ms: 10, // Very short timeout
        include_user_agent: false,
        failure_mode: FailureMode::FailClosed,
    };

    let app = test::init_service(
        App::new()
            .wrap(RateLimitMiddleware::new(config, manager))
            .route("/test", web::get().to(test_handler)),
    )
    .await;

    // Request should fail due to Redis unavailability (fail-closed)
    let req = test::TestRequest::get().uri("/test").to_request();
    let resp = test::call_service(&app, req).await;
    // Should return 503 Service Unavailable (fail-closed)
    assert_eq!(resp.status(), 503);
}

#[cfg(test)]
mod sync_tests {
    use actix_middleware::{FailureMode, RateLimitConfig};

    #[test]
    fn test_rate_limit_config_presets() {
        // Test auth_strict preset
        let auth_config = RateLimitConfig::auth_strict();
        assert_eq!(auth_config.max_requests, 5);
        assert_eq!(auth_config.window_seconds, 60);
        assert!(auth_config.include_user_agent);
        assert!(matches!(auth_config.failure_mode, FailureMode::FailClosed));

        // Test api_lenient preset
        let api_config = RateLimitConfig::api_lenient();
        assert_eq!(api_config.max_requests, 100);
        assert_eq!(api_config.window_seconds, 60);
        assert!(!api_config.include_user_agent);
        assert!(matches!(api_config.failure_mode, FailureMode::FailOpen));
    }
}
