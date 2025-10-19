/// Load and performance testing for Nova Authentication Service
/// Tests concurrent logins, registrations, email verifications, and OAuth operations
use actix_web::{test, web, App};
use futures::future::join_all;
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Semaphore;
use uuid::Uuid;

// Import common test fixtures
#[path = "../common/fixtures.rs"]
mod fixtures;
use fixtures::*;

// Import application modules
use user_service::handlers::auth::{login, register, verify_email};
use user_service::security::hash_password;
use user_service::Config;

// Performance thresholds from spec SC-010
const LOGIN_P50_MS: u64 = 200;
const LOGIN_P95_MS: u64 = 500;
const LOGIN_P99_MS: u64 = 1500;

const REGISTER_P50_MS: u64 = 300;
const REGISTER_P95_MS: u64 = 800;
const REGISTER_P99_MS: u64 = 2000;

const VERIFY_P99_MS: u64 = 200;

// ============================================
// Concurrent Login Load Test
// ============================================

#[tokio::test]
#[ignore] // Run with: cargo test --test load_test -- --ignored --nocapture
async fn load_test_concurrent_logins() {
    let pool = create_test_pool().await;

    // Create test users
    println!("Setting up test users...");
    let num_users = 100;
    let mut users = Vec::new();

    for i in 0..num_users {
        let email = format!("loadtest{}@example.com", i);
        let user = create_test_user_with_email(&pool, &email).await;
        users.push(user);
    }

    let config = Config::from_env();

    // Run concurrent login requests
    println!("Running {} concurrent login requests...", num_users * 10);

    let mut durations = Vec::new();
    let mut failed_count = 0;

    let semaphore = Arc::new(Semaphore::new(50)); // Limit to 50 concurrent requests

    let mut tasks = Vec::new();

    for _ in 0..(num_users * 10) {
        let pool_clone = pool.clone();
        let config_clone = config.clone();
        let user = users[rand::random::<usize>() % users.len()].clone();
        let sem_clone = Arc::clone(&semaphore);

        let task = tokio::spawn(async move {
            let _permit = sem_clone.acquire().await.unwrap();

            let app = test::init_service(
                App::new()
                    .app_data(web::Data::new(pool_clone))
                    .app_data(web::Data::new(config_clone))
                    .route("/auth/login", web::post().to(login)),
            )
            .await;

            let start = Instant::now();

            let req = test::TestRequest::post()
                .uri("/auth/login")
                .set_json(&json!({
                    "email": user.email,
                    "password": "password" // fixtures use this
                }))
                .to_request();

            let resp = test::call_service(&app, req).await;
            let duration = start.elapsed();

            (resp.status().is_success(), duration)
        });

        tasks.push(task);
    }

    // Collect results
    let results = join_all(tasks).await;

    for result in results {
        match result {
            Ok((success, duration)) => {
                if success {
                    durations.push(duration);
                } else {
                    failed_count += 1;
                }
            }
            Err(_) => {
                failed_count += 1;
            }
        }
    }

    // Calculate statistics
    let stats = PerformanceStats::from_durations(durations, failed_count);
    stats.print_report();

    // Verify performance thresholds
    assert!(
        stats.p50 <= Duration::from_millis(LOGIN_P50_MS),
        "P50 latency {}ms exceeds threshold {}ms",
        stats.p50.as_millis(),
        LOGIN_P50_MS
    );

    assert!(
        stats.p95 <= Duration::from_millis(LOGIN_P95_MS),
        "P95 latency {}ms exceeds threshold {}ms",
        stats.p95.as_millis(),
        LOGIN_P95_MS
    );

    assert!(
        stats.p99 <= Duration::from_millis(LOGIN_P99_MS),
        "P99 latency {}ms exceeds threshold {}ms",
        stats.p99.as_millis(),
        LOGIN_P99_MS
    );

    assert_eq!(stats.failed, 0, "No login requests should fail");

    cleanup_test_data(&pool).await;
}

// ============================================
// Concurrent Registration Load Test
// ============================================

#[tokio::test]
#[ignore]
async fn load_test_concurrent_registrations() {
    let pool = create_test_pool().await;
    let redis = create_test_redis().await;

    let num_registrations = 100;

    println!(
        "Running {} concurrent registration requests...",
        num_registrations
    );

    let mut durations = Vec::new();
    let mut failed_count = 0;

    let semaphore = Arc::new(Semaphore::new(20)); // Lower concurrency for writes

    let mut tasks = Vec::new();

    for i in 0..num_registrations {
        let pool_clone = pool.clone();
        let redis_clone = redis.clone();
        let sem_clone = Arc::clone(&semaphore);

        let task = tokio::spawn(async move {
            let _permit = sem_clone.acquire().await.unwrap();

            let app = test::init_service(
                App::new()
                    .app_data(web::Data::new(pool_clone))
                    .app_data(web::Data::new(redis_clone))
                    .route("/auth/register", web::post().to(register)),
            )
            .await;

            let start = Instant::now();

            let email = format!("loadtest-register-{}@example.com", i);
            let username = format!("loaduser{}", i);

            let req = test::TestRequest::post()
                .uri("/auth/register")
                .set_json(&json!({
                    "email": email,
                    "username": username,
                    "password": "ValidP@ssw0rd123"
                }))
                .to_request();

            let resp = test::call_service(&app, req).await;
            let duration = start.elapsed();

            (resp.status().is_success(), duration)
        });

        tasks.push(task);
    }

    // Collect results
    let results = join_all(tasks).await;

    for result in results {
        match result {
            Ok((success, duration)) => {
                if success {
                    durations.push(duration);
                } else {
                    failed_count += 1;
                }
            }
            Err(_) => {
                failed_count += 1;
            }
        }
    }

    // Calculate statistics
    let stats = PerformanceStats::from_durations(durations, failed_count);
    stats.print_report();

    // Verify performance thresholds
    assert!(
        stats.p50 <= Duration::from_millis(REGISTER_P50_MS),
        "P50 latency {}ms exceeds threshold {}ms",
        stats.p50.as_millis(),
        REGISTER_P50_MS
    );

    assert!(
        stats.p95 <= Duration::from_millis(REGISTER_P95_MS),
        "P95 latency {}ms exceeds threshold {}ms",
        stats.p95.as_millis(),
        REGISTER_P95_MS
    );

    assert!(
        stats.p99 <= Duration::from_millis(REGISTER_P99_MS),
        "P99 latency {}ms exceeds threshold {}ms",
        stats.p99.as_millis(),
        REGISTER_P99_MS
    );

    assert_eq!(stats.failed, 0, "All registrations should succeed");

    // Verify no duplicate users were created
    let user_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM users WHERE email LIKE 'loadtest-register-%'")
            .fetch_one(&pool)
            .await
            .unwrap();

    assert_eq!(
        user_count, num_registrations as i64,
        "Should create exactly {} users without duplicates",
        num_registrations
    );

    cleanup_test_data(&pool).await;
}

// ============================================
// Concurrent Email Verification Load Test
// ============================================

#[tokio::test]
#[ignore]
async fn load_test_concurrent_email_verifications() {
    let pool = create_test_pool().await;
    let mut redis = create_test_redis().await;

    // Setup test users with verification tokens
    println!("Setting up test users with verification tokens...");
    let num_users = 500;
    let mut verification_tokens = Vec::new();

    for i in 0..num_users {
        let email = format!("verify{}@example.com", i);
        let password_hash = hash_password("TestP@ssw0rd").unwrap();
        let user = create_unverified_user(&pool, &email, &password_hash).await;

        // Generate a fake verification token for testing
        let token = hex::encode(rand::random::<[u8; 32]>());

        // Store token in Redis manually for testing
        use redis::AsyncCommands;
        let key = format!("email_verification:{}", token);
        let value = format!("{}:{}", user.id, email);
        let _: Result<(), redis::RedisError> = redis.set_ex(&key, value, 86400).await;

        verification_tokens.push(token);
    }

    println!("Running {} concurrent verification requests...", num_users);

    let mut durations = Vec::new();
    let mut failed_count = 0;

    let semaphore = Arc::new(Semaphore::new(100)); // High concurrency for reads

    let mut tasks = Vec::new();

    for token in verification_tokens {
        let pool_clone = pool.clone();
        let redis_clone = redis.clone();
        let sem_clone = Arc::clone(&semaphore);

        let task = tokio::spawn(async move {
            let _permit = sem_clone.acquire().await.unwrap();

            let app = test::init_service(
                App::new()
                    .app_data(web::Data::new(pool_clone))
                    .app_data(web::Data::new(redis_clone))
                    .route("/auth/verify-email", web::post().to(verify_email)),
            )
            .await;

            let start = Instant::now();

            let req = test::TestRequest::post()
                .uri("/auth/verify-email")
                .set_json(&json!({
                    "token": token
                }))
                .to_request();

            let resp = test::call_service(&app, req).await;
            let duration = start.elapsed();

            (resp.status().is_success(), duration)
        });

        tasks.push(task);
    }

    // Collect results
    let results = join_all(tasks).await;

    for result in results {
        match result {
            Ok((success, duration)) => {
                if success {
                    durations.push(duration);
                } else {
                    failed_count += 1;
                }
            }
            Err(_) => {
                failed_count += 1;
            }
        }
    }

    // Calculate statistics
    let stats = PerformanceStats::from_durations(durations, failed_count);
    stats.print_report();

    // Verify P99 latency
    assert!(
        stats.p99 <= Duration::from_millis(VERIFY_P99_MS),
        "P99 latency {}ms exceeds threshold {}ms",
        stats.p99.as_millis(),
        VERIFY_P99_MS
    );

    assert_eq!(stats.failed, 0, "All verifications should succeed");

    clear_redis(&mut redis).await;
    cleanup_test_data(&pool).await;
}

// ============================================
// Concurrent OAuth Callback Load Test
// ============================================

#[tokio::test]
#[ignore]
async fn load_test_concurrent_oauth_callbacks() {
    let pool = create_test_pool().await;
    let mut redis = create_test_redis().await;

    println!("Running concurrent OAuth callback simulation...");

    // Setup OAuth state tokens
    let num_requests = 200;
    let mut state_tokens = Vec::new();

    // Generate fake state tokens for testing
    for _ in 0..num_requests {
        let state = hex::encode(rand::random::<[u8; 32]>());

        // Store state in Redis manually for testing
        use redis::AsyncCommands;
        let key = format!("oauth_state:{}", state);
        let _: Result<(), redis::RedisError> = redis.set_ex(&key, "google", 600).await;

        state_tokens.push(state);
    }

    let mut durations = Vec::new();
    let mut failed_count = 0;

    let semaphore = Arc::new(Semaphore::new(50));

    let mut tasks = Vec::new();

    for (idx, state_token) in state_tokens.into_iter().enumerate() {
        let pool_clone = pool.clone();
        let mut redis_clone = redis.clone();
        let sem_clone = Arc::clone(&semaphore);

        let task = tokio::spawn(async move {
            let _permit = sem_clone.acquire().await.unwrap();

            let start = Instant::now();

            // Simulate OAuth callback processing:
            // 1. Verify state token
            // 2. Create/find user
            // 3. Create OAuth connection

            // Verify state token manually
            use redis::AsyncCommands;
            let key = format!("oauth_state:{}", state_token);
            let state_value: Result<String, redis::RedisError> = redis_clone.get(&key).await;
            let _: Result<(), redis::RedisError> = redis_clone.del(&key).await;

            if state_value.is_ok() {
                // Create a new user for this OAuth login
                let email = format!("oauth-{}@google.com", idx);
                let provider_user_id = format!("google_{}", idx);

                // Check if user exists
                let existing_conn =
                    find_oauth_connection(&pool_clone, "google", &provider_user_id).await;

                let user = if existing_conn.is_none() {
                    // Create new user
                    let password_hash = hash_password("RandomP@ssw0rd").unwrap();
                    let user = create_test_user_with_email(&pool_clone, &email).await;

                    // Create OAuth connection
                    let _conn = create_test_oauth_connection(
                        &pool_clone,
                        user.id,
                        "google",
                        &provider_user_id,
                    )
                    .await;

                    Some(user)
                } else {
                    // User already exists
                    existing_conn.map(|conn| {
                        // In real code, we'd fetch user by conn.user_id
                        // For this test, we just verify the connection exists
                        conn.user_id
                    });
                    None
                };

                let duration = start.elapsed();
                (user.is_some(), duration)
            } else {
                let duration = start.elapsed();
                (false, duration)
            }
        });

        tasks.push(task);
    }

    // Collect results
    let results = join_all(tasks).await;

    for result in results {
        match result {
            Ok((success, duration)) => {
                if success {
                    durations.push(duration);
                } else {
                    failed_count += 1;
                }
            }
            Err(_) => {
                failed_count += 1;
            }
        }
    }

    // Calculate statistics
    let stats = PerformanceStats::from_durations(durations, failed_count);
    stats.print_report();

    // Verify no race conditions (no duplicate OAuth connections)
    let oauth_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM oauth_connections WHERE provider = 'google' AND provider_user_id LIKE 'google_%'"
    )
    .fetch_one(&pool)
    .await
    .unwrap();

    assert_eq!(
        oauth_count, stats.successful as i64,
        "Should create exactly {} OAuth connections without duplicates",
        stats.successful
    );

    clear_redis(&mut redis).await;
    cleanup_test_data(&pool).await;
}

// ============================================
// Stress Test: Mixed Workload
// ============================================

#[tokio::test]
#[ignore]
async fn stress_test_mixed_workload() {
    let pool = create_test_pool().await;
    let mut redis = create_test_redis().await;

    println!("Running mixed workload stress test...");

    // Create some existing users for login tests
    let num_existing_users = 50;
    let mut existing_users = Vec::new();

    for i in 0..num_existing_users {
        let email = format!("existing{}@example.com", i);
        let user = create_test_user_with_email(&pool, &email).await;
        existing_users.push(user);
    }

    let total_requests = 500;
    let mut durations = Vec::new();
    let mut failed_count = 0;

    let semaphore = Arc::new(Semaphore::new(50));

    let mut tasks = Vec::new();

    for i in 0..total_requests {
        let pool_clone = pool.clone();
        let redis_clone = redis.clone();
        let config = Config::from_env();
        let sem_clone = Arc::clone(&semaphore);
        let user = existing_users[i % existing_users.len()].clone();

        let task = tokio::spawn(async move {
            let _permit = sem_clone.acquire().await.unwrap();

            let start = Instant::now();

            // Randomly choose operation type
            let operation = i % 3;

            let success = match operation {
                0 => {
                    // Login
                    let app = test::init_service(
                        App::new()
                            .app_data(web::Data::new(pool_clone))
                            .app_data(web::Data::new(config))
                            .route("/auth/login", web::post().to(login)),
                    )
                    .await;

                    let req = test::TestRequest::post()
                        .uri("/auth/login")
                        .set_json(&json!({
                            "email": user.email,
                            "password": "password"
                        }))
                        .to_request();

                    let resp = test::call_service(&app, req).await;
                    resp.status().is_success()
                }
                1 => {
                    // Registration
                    let app = test::init_service(
                        App::new()
                            .app_data(web::Data::new(pool_clone))
                            .app_data(web::Data::new(redis_clone))
                            .route("/auth/register", web::post().to(register)),
                    )
                    .await;

                    let email = format!("mixed-{}@example.com", i);
                    let username = format!("mixed{}", i);

                    let req = test::TestRequest::post()
                        .uri("/auth/register")
                        .set_json(&json!({
                            "email": email,
                            "username": username,
                            "password": "ValidP@ssw0rd123"
                        }))
                        .to_request();

                    let resp = test::call_service(&app, req).await;
                    resp.status().is_success()
                }
                _ => {
                    // Token validation (simulated)
                    use user_service::security::jwt;
                    jwt::initialize_keys(
                        &std::env::var("JWT_PRIVATE_KEY").unwrap(),
                        &std::env::var("JWT_PUBLIC_KEY").unwrap(),
                    )
                    .ok();

                    let token = jwt::generate_access_token(user.id, &user.email, &user.username);
                    token.is_ok()
                }
            };

            let duration = start.elapsed();
            (success, duration)
        });

        tasks.push(task);
    }

    // Collect results
    let results = join_all(tasks).await;

    for result in results {
        match result {
            Ok((success, duration)) => {
                if success {
                    durations.push(duration);
                } else {
                    failed_count += 1;
                }
            }
            Err(_) => {
                failed_count += 1;
            }
        }
    }

    // Calculate statistics
    let stats = PerformanceStats::from_durations(durations, failed_count);
    stats.print_report();

    // Allow up to 5% failure rate under stress
    let failure_rate = (stats.failed as f64 / stats.total_requests as f64) * 100.0;
    assert!(
        failure_rate < 5.0,
        "Failure rate {:.2}% exceeds 5% threshold",
        failure_rate
    );

    clear_redis(&mut redis).await;
    cleanup_test_data(&pool).await;
}
