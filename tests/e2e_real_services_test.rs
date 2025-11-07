//! Real End-to-End Integration Tests
//!
//! Tests that interact with actual running services (not mocks).
//! Requires services to be deployed and seed data to be loaded.
//!
//! ## Prerequisites
//! 1. Services deployed in staging environment
//! 2. Seed data loaded (run seed-data-init job)
//! 3. Environment variables configured
//!
//! ## Running Tests
//! ```bash
//! # Against staging environment
//! E2E_ENV=staging cargo test --test e2e_real_services_test -- --nocapture --test-threads=1
//!
//! # Against local environment (port-forwarded)
//! kubectl port-forward -n nova svc/auth-service 8080:8080 &
//! kubectl port-forward -n nova svc/user-service 8081:8080 &
//! kubectl port-forward -n nova svc/content-service 8082:8080 &
//! kubectl port-forward -n nova svc/messaging-service 8085:8080 &
//! E2E_ENV=local cargo test --test e2e_real_services_test -- --nocapture --test-threads=1
//! ```

use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use uuid::Uuid;

/// Test environment configuration
struct E2EConfig {
    auth_service_url: String,
    user_service_url: String,
    content_service_url: String,
    messaging_service_url: String,
}

impl E2EConfig {
    fn from_env() -> Self {
        let env = std::env::var("E2E_ENV").unwrap_or_else(|_| "local".to_string());

        match env.as_str() {
            "staging" => Self {
                auth_service_url: "http://auth-service.nova.svc.cluster.local:8080".to_string(),
                user_service_url: "http://user-service.nova.svc.cluster.local:8080".to_string(),
                content_service_url: "http://content-service.nova.svc.cluster.local:8080"
                    .to_string(),
                messaging_service_url: "http://messaging-service.nova.svc.cluster.local:8080"
                    .to_string(),
            },
            "local" => Self {
                auth_service_url: "http://127.0.0.1:8080".to_string(),
                user_service_url: "http://127.0.0.1:8081".to_string(),
                content_service_url: "http://127.0.0.1:8082".to_string(),
                messaging_service_url: "http://127.0.0.1:8085".to_string(),
            },
            _ => panic!("Invalid E2E_ENV: {}", env),
        }
    }
}

/// Test user credentials (from seed data)
const TEST_USER_ALICE: &str = "alice@test.nova.com";
const TEST_USER_BOB: &str = "bob@test.nova.com";
const TEST_PASSWORD: &str = "TestPass123!";

// Known test user IDs from seed data
const ALICE_ID: &str = "00000000-0000-0000-0000-000000000001";
const BOB_ID: &str = "00000000-0000-0000-0000-000000000002";

#[derive(Debug, Serialize, Deserialize)]
struct LoginRequest {
    email: String,
    password: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct LoginResponse {
    access_token: String,
    refresh_token: String,
    user_id: String,
    expires_in: u64,
}

#[derive(Debug, Serialize, Deserialize)]
struct UserProfile {
    id: String,
    username: String,
    display_name: String,
    bio: Option<String>,
    avatar_url: Option<String>,
    is_verified: bool,
    follower_count: i32,
    following_count: i32,
}

#[derive(Debug, Serialize, Deserialize)]
struct CreatePostRequest {
    content: String,
    media_urls: Vec<String>,
    visibility: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct Post {
    id: String,
    author_id: String,
    content: String,
    created_at: String,
    like_count: i32,
    comment_count: i32,
}

#[derive(Debug, Serialize, Deserialize)]
struct Conversation {
    id: String,
    participant_ids: Vec<String>,
    last_message: Option<String>,
    updated_at: String,
}

/// Helper: Create HTTP client with timeout
fn create_client() -> Client {
    Client::builder()
        .timeout(Duration::from_secs(10))
        .build()
        .expect("Failed to create HTTP client")
}

/// Helper: Login and get access token
async fn login(config: &E2EConfig, email: &str, password: &str) -> LoginResponse {
    let client = create_client();

    let response = client
        .post(&format!("{}/api/v1/auth/login", config.auth_service_url))
        .json(&LoginRequest {
            email: email.to_string(),
            password: password.to_string(),
        })
        .send()
        .await
        .expect("Failed to send login request");

    assert!(
        response.status().is_success(),
        "Login failed: {}",
        response.status()
    );

    response
        .json::<LoginResponse>()
        .await
        .expect("Failed to parse login response")
}

/// Helper: Get user profile
async fn get_user_profile(config: &E2EConfig, user_id: &str, access_token: &str) -> UserProfile {
    let client = create_client();

    let response = client
        .get(&format!(
            "{}/api/v1/users/{}",
            config.user_service_url, user_id
        ))
        .bearer_auth(access_token)
        .send()
        .await
        .expect("Failed to get user profile");

    assert!(
        response.status().is_success(),
        "Get user profile failed: {}",
        response.status()
    );

    response
        .json::<UserProfile>()
        .await
        .expect("Failed to parse user profile")
}

/// Test 1: Authentication flow with real auth-service
#[tokio::test]
#[ignore]
async fn test_e2e_01_authentication_flow() {
    let config = E2EConfig::from_env();

    println!("=== E2E Test: Authentication Flow ===");

    // Step 1: Login with Alice
    println!("Step 1: Login as Alice");
    let alice_login = login(&config, TEST_USER_ALICE, TEST_PASSWORD).await;

    assert!(!alice_login.access_token.is_empty());
    assert_eq!(alice_login.user_id, ALICE_ID);
    println!("✓ Alice logged in successfully");
    println!("  Access token: {}...", &alice_login.access_token[..20]);

    // Step 2: Login with Bob
    println!("Step 2: Login as Bob");
    let bob_login = login(&config, TEST_USER_BOB, TEST_PASSWORD).await;

    assert!(!bob_login.access_token.is_empty());
    assert_eq!(bob_login.user_id, BOB_ID);
    println!("✓ Bob logged in successfully");

    // Step 3: Verify tokens are different
    assert_ne!(alice_login.access_token, bob_login.access_token);
    println!("✓ Tokens are unique");

    println!("=== Test Passed ===\n");
}

/// Test 2: User profile retrieval via user-service
#[tokio::test]
#[ignore]
async fn test_e2e_02_user_profile_retrieval() {
    let config = E2EConfig::from_env();

    println!("=== E2E Test: User Profile Retrieval ===");

    // Login as Alice
    let alice_login = login(&config, TEST_USER_ALICE, TEST_PASSWORD).await;

    // Get Alice's profile
    println!("Fetching Alice's profile...");
    let alice_profile = get_user_profile(&config, ALICE_ID, &alice_login.access_token).await;

    assert_eq!(alice_profile.id, ALICE_ID);
    assert_eq!(alice_profile.username, "alice_test");
    assert_eq!(alice_profile.display_name, "Alice Smith");
    assert!(alice_profile.is_verified);
    println!("✓ Alice's profile retrieved:");
    println!("  Username: {}", alice_profile.username);
    println!("  Display name: {}", alice_profile.display_name);
    println!("  Followers: {}", alice_profile.follower_count);

    // Get Bob's profile (via Alice's token)
    println!("Fetching Bob's profile (via Alice's token)...");
    let bob_profile = get_user_profile(&config, BOB_ID, &alice_login.access_token).await;

    assert_eq!(bob_profile.id, BOB_ID);
    assert_eq!(bob_profile.username, "bob_test");
    println!("✓ Bob's profile retrieved:");
    println!("  Username: {}", bob_profile.username);
    println!("  Followers: {}", bob_profile.follower_count);

    println!("=== Test Passed ===\n");
}

/// Test 3: Cross-service data consistency (follow relationship)
#[tokio::test]
#[ignore]
async fn test_e2e_03_follow_relationship_consistency() {
    let config = E2EConfig::from_env();

    println!("=== E2E Test: Follow Relationship Consistency ===");

    let alice_login = login(&config, TEST_USER_ALICE, TEST_PASSWORD).await;

    // Get Alice's profile (should show she's following 2 users from seed data)
    let alice_profile = get_user_profile(&config, ALICE_ID, &alice_login.access_token).await;
    println!("Alice's following count: {}", alice_profile.following_count);
    assert!(
        alice_profile.following_count >= 2,
        "Alice should be following at least 2 users from seed data"
    );

    // Get Bob's profile (Alice follows Bob, so Bob's follower count should include Alice)
    let bob_profile = get_user_profile(&config, BOB_ID, &alice_login.access_token).await;
    println!("Bob's follower count: {}", bob_profile.follower_count);
    assert!(
        bob_profile.follower_count >= 1,
        "Bob should have at least 1 follower (Alice)"
    );

    println!("✓ Follow relationships are consistent");
    println!("=== Test Passed ===\n");
}

/// Test 4: Create post via content-service
#[tokio::test]
#[ignore]
async fn test_e2e_04_create_and_retrieve_post() {
    let config = E2EConfig::from_env();

    println!("=== E2E Test: Create and Retrieve Post ===");

    let alice_login = login(&config, TEST_USER_ALICE, TEST_PASSWORD).await;
    let client = create_client();

    // Create a new post
    let post_content = format!(
        "E2E Test Post - Created at {}",
        chrono::Utc::now().to_rfc3339()
    );

    println!("Creating post: {}", post_content);
    let create_response = client
        .post(&format!("{}/api/v1/posts", config.content_service_url))
        .bearer_auth(&alice_login.access_token)
        .json(&CreatePostRequest {
            content: post_content.clone(),
            media_urls: vec![],
            visibility: "public".to_string(),
        })
        .send()
        .await
        .expect("Failed to create post");

    assert!(
        create_response.status().is_success(),
        "Create post failed: {}",
        create_response.status()
    );

    let created_post: Post = create_response
        .json()
        .await
        .expect("Failed to parse created post");

    println!("✓ Post created with ID: {}", created_post.id);
    assert_eq!(created_post.author_id, ALICE_ID);
    assert_eq!(created_post.content, post_content);

    // Retrieve the post to verify it's accessible
    println!("Retrieving post by ID...");
    let get_response = client
        .get(&format!(
            "{}/api/v1/posts/{}",
            config.content_service_url, created_post.id
        ))
        .bearer_auth(&alice_login.access_token)
        .send()
        .await
        .expect("Failed to retrieve post");

    assert!(
        get_response.status().is_success(),
        "Retrieve post failed: {}",
        get_response.status()
    );

    let retrieved_post: Post = get_response
        .json()
        .await
        .expect("Failed to parse retrieved post");

    assert_eq!(retrieved_post.id, created_post.id);
    assert_eq!(retrieved_post.content, post_content);
    println!("✓ Post retrieved successfully");

    println!("=== Test Passed ===\n");
}

/// Test 5: Messaging flow - Get conversations from seed data
#[tokio::test]
#[ignore]
async fn test_e2e_05_messaging_conversations() {
    let config = E2EConfig::from_env();

    println!("=== E2E Test: Messaging Conversations ===");

    let alice_login = login(&config, TEST_USER_ALICE, TEST_PASSWORD).await;
    let client = create_client();

    // Get Alice's conversations (should have 2 from seed data)
    println!("Fetching Alice's conversations...");
    let conversations_response = client
        .get(&format!(
            "{}/api/v1/conversations",
            config.messaging_service_url
        ))
        .bearer_auth(&alice_login.access_token)
        .send()
        .await
        .expect("Failed to get conversations");

    assert!(
        conversations_response.status().is_success(),
        "Get conversations failed: {}",
        conversations_response.status()
    );

    let conversations: Vec<Conversation> = conversations_response
        .json()
        .await
        .expect("Failed to parse conversations");

    println!("Alice has {} conversation(s)", conversations.len());
    assert!(
        !conversations.is_empty(),
        "Alice should have at least 1 conversation from seed data"
    );

    // Verify conversation structure
    let first_conv = &conversations[0];
    println!("First conversation:");
    println!("  ID: {}", first_conv.id);
    println!("  Participants: {:?}", first_conv.participant_ids);
    println!(
        "  Last message: {}",
        first_conv.last_message.as_deref().unwrap_or("(none)")
    );

    assert!(
        first_conv.participant_ids.contains(&ALICE_ID.to_string()),
        "Alice should be a participant"
    );

    println!("✓ Conversations retrieved successfully");
    println!("=== Test Passed ===\n");
}

/// Test 6: Full E2E scenario - Post creation appears in user's feed
#[tokio::test]
#[ignore]
async fn test_e2e_06_post_to_feed_flow() {
    let config = E2EConfig::from_env();

    println!("=== E2E Test: Post Creation → Feed Appearance ===");

    // Login as Alice and Bob
    let alice_login = login(&config, TEST_USER_ALICE, TEST_PASSWORD).await;
    let bob_login = login(&config, TEST_USER_BOB, TEST_PASSWORD).await;
    let client = create_client();

    // Alice creates a post
    let post_content = format!("E2E Feed Test - {}", Uuid::new_v4());
    println!("Alice creates post: {}", post_content);

    let create_response = client
        .post(&format!("{}/api/v1/posts", config.content_service_url))
        .bearer_auth(&alice_login.access_token)
        .json(&CreatePostRequest {
            content: post_content.clone(),
            media_urls: vec![],
            visibility: "public".to_string(),
        })
        .send()
        .await
        .expect("Failed to create post");

    assert!(create_response.status().is_success());
    let created_post: Post = create_response.json().await.expect("Parse error");
    println!("✓ Post created: {}", created_post.id);

    // Wait a moment for feed propagation
    tokio::time::sleep(Duration::from_secs(2)).await;

    // Bob checks his feed (should see Alice's post because he follows Alice)
    println!("Bob checks his feed...");
    let feed_response = client
        .get(&format!("{}/api/v1/feed", config.content_service_url))
        .bearer_auth(&bob_login.access_token)
        .query(&[("limit", "20")])
        .send()
        .await
        .expect("Failed to get feed");

    assert!(feed_response.status().is_success());
    let feed_posts: Vec<Post> = feed_response.json().await.expect("Parse error");

    println!("Bob's feed has {} posts", feed_posts.len());

    // Verify Alice's post appears in Bob's feed
    let found = feed_posts.iter().any(|p| p.id == created_post.id);
    assert!(
        found,
        "Alice's post should appear in Bob's feed (Bob follows Alice)"
    );

    println!("✓ Post appeared in follower's feed");
    println!("=== Test Passed ===\n");
}

/// Test 7: Service health checks
#[tokio::test]
#[ignore]
async fn test_e2e_00_health_checks() {
    let config = E2EConfig::from_env();
    let client = create_client();

    println!("=== E2E Test: Health Checks ===");

    let services = vec![
        ("auth-service", &config.auth_service_url),
        ("user-service", &config.user_service_url),
        ("content-service", &config.content_service_url),
        ("messaging-service", &config.messaging_service_url),
    ];

    for (name, url) in services {
        println!("Checking {}: {}", name, url);
        let response = client
            .get(&format!("{}/health", url))
            .timeout(Duration::from_secs(5))
            .send()
            .await
            .expect(&format!("Failed to connect to {}", name));

        assert!(
            response.status().is_success(),
            "{} health check failed: {}",
            name,
            response.status()
        );
        println!("✓ {} is healthy", name);
    }

    println!("=== All Services Healthy ===\n");
}
