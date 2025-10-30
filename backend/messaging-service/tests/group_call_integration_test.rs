//! Integration test for group video calls
//!
//! Tests the complete group call flow:
//! - Initiate group call with explicit parameters
//! - Multiple users joining
//! - Participant list management
//! - User leaving and rejoining
//! - Call termination
//!
//! Run with: cargo test --test group_call_integration_test -- --nocapture

use axum::Router;
use messaging_service::{
    config::Config, db, routes, state::AppState, websocket::ConnectionRegistry,
};
use redis::Client as RedisClient;
use serde_json::json;
use sqlx::{Pool, Postgres};
use std::sync::Arc;
use testcontainers::{
    clients::Cli, images::generic::GenericImage, images::postgres::Postgres as TcPostgres,
    RunnableImage,
};
use uuid::Uuid;

// Test fixtures
const USER_A_ID: &str = "11111111-1111-1111-1111-111111111111";
const USER_B_ID: &str = "22222222-2222-2222-2222-222222222222";
const USER_C_ID: &str = "33333333-3333-3333-3333-333333333333";

const MOCK_JWT_A: &str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMTExMTExMS0xMTExLTExMTEtMTExMS0xMTExMTExMTExMTEiLCJpYXQiOjE2OTk4MDAwMDB9.mock_token_a";
const MOCK_JWT_B: &str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIyMjIyMjIyMi0yMjIyLTIyMjItMjIyMi0yMjIyMjIyMjIyMjIiLCJpYXQiOjE2OTk4MDAwMDB9.mock_token_b";
const MOCK_JWT_C: &str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIzMzMzMzMzMy0zMzMzLTMzMzMtMzMzMy0zMzMzMzMzMzMzMzMiLCJpYXQiOjE2OTk4MDAwMDB9.mock_token_c";

const SDP_A: &str = "v=0\r\no=- 1234567890 1234567890 IN IP4 127.0.0.1\r\ns=User A\r\n";
const SDP_B: &str = "v=0\r\no=- 9876543210 9876543210 IN IP4 127.0.0.1\r\ns=User B\r\n";
const SDP_C: &str = "v=0\r\no=- 1111111111 1111111111 IN IP4 127.0.0.1\r\ns=User C\r\n";

struct TestSetup {
    _docker: Cli,
    db: Pool<Postgres>,
    app_url: String,
}

async fn setup() -> TestSetup {
    // Start Postgres in Docker
    let docker = Cli::default();
    let postgres_image =
        RunnableImage::from(TcPostgres::default()).with_env_var(("POSTGRES_PASSWORD", "postgres"));
    let container = docker.run(postgres_image);
    let host = "127.0.0.1";
    let port = container.get_host_port_ipv4(5432);

    // Connect to default postgres and create test database
    let admin_url = format!("postgres://postgres:postgres@{}:{}/postgres", host, port);
    let pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(5)
        .connect(&admin_url)
        .await
        .unwrap();

    let dbname = format!(
        "test_group_call_{}",
        Uuid::new_v4().to_string().replace('-', "")
    );
    sqlx::query(&format!("CREATE DATABASE {}", dbname))
        .execute(&pool)
        .await
        .unwrap();

    // Connect to test database
    let test_url = format!("postgres://postgres:postgres@{}:{}/{}", host, port, dbname);
    let test_pool = sqlx::postgres::PgPoolOptions::new()
        .max_connections(10)
        .connect(&test_url)
        .await
        .unwrap();

    // Run migrations
    db::MIGRATOR.run(&test_pool).await.unwrap();

    // Setup Redis
    let redis = RedisClient::open("redis://127.0.0.1:6379").unwrap();

    // Build app
    let registry = ConnectionRegistry::new();
    let state = AppState {
        db: test_pool.clone(),
        registry: registry.clone(),
        redis: redis.clone(),
        config: Arc::new(Config::test_defaults()),
        apns: None,
    };

    let app: Router = routes::build_router().with_state(state);

    // Start server
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let addr = listener.local_addr().unwrap();
    let app_url = format!("http://{}", addr);

    // Start streams listener
    tokio::spawn({
        let registry = registry.clone();
        let redis = redis.clone();
        async move {
            let config = messaging_service::websocket::streams::StreamsConfig::default();
            let _ = messaging_service::websocket::streams::start_streams_listener(
                redis, registry, config,
            )
            .await;
        }
    });

    // Start server
    tokio::spawn(async move {
        let make_svc = app.into_make_service();
        axum::serve(listener, make_svc).await.ok();
    });

    // Wait for server to start
    tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

    TestSetup {
        _docker: docker,
        db: test_pool,
        app_url,
    }
}

async fn create_test_users(db: &Pool<Postgres>) {
    let users = vec![
        (USER_A_ID, "User A"),
        (USER_B_ID, "User B"),
        (USER_C_ID, "User C"),
    ];

    for (id, name) in users {
        sqlx::query(
            "INSERT INTO users (id, username, email) VALUES ($1, $2, $2) ON CONFLICT DO NOTHING",
        )
        .bind(Uuid::parse_str(id).unwrap())
        .bind(name)
        .execute(db)
        .await
        .ok();
    }
}

async fn create_test_conversation(
    _db: &Pool<Postgres>,
    app_url: &str,
    _initiator_id: &str,
    jwt_token: &str,
) -> String {
    let client = reqwest::Client::new();

    let response = client
        .post(format!("{}/api/v1/conversations/groups", app_url))
        .header("Authorization", format!("Bearer {}", jwt_token))
        .json(&json!({
            "name": "Test Group Call",
            "member_ids": [USER_B_ID, USER_C_ID]
        }))
        .send()
        .await
        .expect("Failed to create conversation");

    let body: serde_json::Value = response.json().await.expect("Failed to parse response");
    body["id"]
        .as_str()
        .expect("No conversation ID in response")
        .to_string()
}

#[tokio::test]
#[ignore] // Run with: cargo test --test group_call_integration_test -- --nocapture --ignored
async fn test_group_call_flow() {
    println!("\n🧪 Starting Group Call Integration Test\n");

    let setup = setup().await;
    create_test_users(&setup.db).await;

    let client = reqwest::Client::new();
    let app_url = &setup.app_url;

    // Create conversation
    println!("📝 Creating test conversation...");
    let conv_id = create_test_conversation(&setup.db, app_url, USER_A_ID, MOCK_JWT_A).await;
    println!("✓ Conversation created: {}", conv_id);

    // Test 1: Initiate group call
    println!("\n📞 Test 1: Initiating group call...");
    let response = client
        .post(format!(
            "{}/api/v1/conversations/{}/calls",
            app_url, conv_id
        ))
        .header("Authorization", format!("Bearer {}", MOCK_JWT_A))
        .json(&json!({
            "initiator_sdp": SDP_A,
            "call_type": "group",
            "max_participants": 8
        }))
        .send()
        .await
        .expect("Failed to initiate call");

    let body: serde_json::Value = response.json().await.expect("Failed to parse response");
    let call_id = body["id"].as_str().expect("No call ID in response");
    let call_type = body["call_type"].as_str().expect("No call_type");
    let max_participants = body["max_participants"]
        .as_u64()
        .expect("No max_participants");

    assert_eq!(call_type, "group", "Call type should be 'group'");
    assert_eq!(max_participants, 8, "Max participants should be 8");
    println!(
        "✓ Call initiated: {} (type: {}, max: {})",
        call_id, call_type, max_participants
    );

    // Test 2: User B joins
    println!("\n👥 Test 2: User B joins call...");
    let response = client
        .post(format!("{}/api/v1/calls/{}/join", app_url, call_id))
        .header("Authorization", format!("Bearer {}", MOCK_JWT_B))
        .json(&json!({ "sdp": SDP_B }))
        .send()
        .await
        .expect("Failed to join call");

    let body: serde_json::Value = response.json().await.expect("Failed to parse response");
    let participant_count = body["current_participant_count"]
        .as_u64()
        .expect("No participant count");
    let existing_participants = body["participants"]
        .as_array()
        .expect("No participants array");

    assert_eq!(
        participant_count, 2,
        "Should have 2 participants after B joins"
    );
    assert_eq!(
        existing_participants.len(),
        1,
        "B should receive 1 existing participant (A)"
    );
    println!(
        "✓ User B joined (total participants: {})",
        participant_count
    );

    // Test 3: User C joins
    println!("\n👥 Test 3: User C joins call...");
    let response = client
        .post(format!("{}/api/v1/calls/{}/join", app_url, call_id))
        .header("Authorization", format!("Bearer {}", MOCK_JWT_C))
        .json(&json!({ "sdp": SDP_C }))
        .send()
        .await
        .expect("Failed to join call");

    let body: serde_json::Value = response.json().await.expect("Failed to parse response");
    let participant_count = body["current_participant_count"]
        .as_u64()
        .expect("No participant count");
    let existing_participants = body["participants"]
        .as_array()
        .expect("No participants array");

    assert_eq!(
        participant_count, 3,
        "Should have 3 participants after C joins"
    );
    assert_eq!(
        existing_participants.len(),
        2,
        "C should receive 2 existing participants (A, B)"
    );
    println!(
        "✓ User C joined (total participants: {})",
        participant_count
    );

    // Test 4: Get participants list
    println!("\n📋 Test 4: Getting participants list...");
    let response = client
        .get(format!("{}/api/v1/calls/{}/participants", app_url, call_id))
        .header("Authorization", format!("Bearer {}", MOCK_JWT_A))
        .send()
        .await
        .expect("Failed to get participants");

    let body: serde_json::Value = response.json().await.expect("Failed to parse response");
    let participants = body["participants"]
        .as_array()
        .expect("No participants array");

    assert_eq!(participants.len(), 3, "Should have 3 participants");
    println!(
        "✓ Participants list retrieved: {} users",
        participants.len()
    );

    // Test 5: User B leaves
    println!("\n👋 Test 5: User B leaves call...");
    let response = client
        .post(format!("{}/api/v1/calls/{}/leave", app_url, call_id))
        .header("Authorization", format!("Bearer {}", MOCK_JWT_B))
        .send()
        .await
        .expect("Failed to leave call");

    assert_eq!(response.status(), 204, "Leave should return 204 No Content");

    // Verify participant count
    let response = client
        .get(format!("{}/api/v1/calls/{}/participants", app_url, call_id))
        .header("Authorization", format!("Bearer {}", MOCK_JWT_A))
        .send()
        .await
        .expect("Failed to get participants");

    let body: serde_json::Value = response.json().await.expect("Failed to parse response");
    let active_participants: Vec<_> = body["participants"]
        .as_array()
        .expect("No participants array")
        .iter()
        .filter(|p| p["left_at"].is_null())
        .collect();

    assert_eq!(
        active_participants.len(),
        2,
        "Should have 2 active participants after B leaves"
    );
    println!(
        "✓ User B left (active participants: {})",
        active_participants.len()
    );

    // Test 6: End call
    println!("\n🛑 Test 6: Ending call...");
    let response = client
        .post(format!("{}/api/v1/calls/{}/end", app_url, call_id))
        .header("Authorization", format!("Bearer {}", MOCK_JWT_A))
        .send()
        .await
        .expect("Failed to end call");

    assert_eq!(
        response.status(),
        204,
        "End call should return 204 No Content"
    );
    println!("✓ Call ended");

    println!("\n✅ All tests passed!\n");
}

#[tokio::test]
#[ignore]
async fn test_group_call_error_handling() {
    println!("\n🧪 Starting Group Call Error Handling Tests\n");

    let setup = setup().await;
    create_test_users(&setup.db).await;

    let client = reqwest::Client::new();
    let app_url = &setup.app_url;

    // Create conversation
    let conv_id = create_test_conversation(&setup.db, app_url, USER_A_ID, MOCK_JWT_A).await;

    // Test: Invalid call type
    println!("❌ Test: Invalid call type...");
    let response = client
        .post(format!(
            "{}/api/v1/conversations/{}/calls",
            app_url, conv_id
        ))
        .header("Authorization", format!("Bearer {}", MOCK_JWT_A))
        .json(&json!({
            "initiator_sdp": SDP_A,
            "call_type": "invalid"
        }))
        .send()
        .await
        .expect("Failed to send request");

    assert!(
        response.status().is_client_error(),
        "Should return client error for invalid type"
    );
    println!("✓ Invalid call type rejected");

    // Test: Exceeds max participants
    println!("❌ Test: Exceeds max participants...");
    let response = client
        .post(format!(
            "{}/api/v1/conversations/{}/calls",
            app_url, conv_id
        ))
        .header("Authorization", format!("Bearer {}", MOCK_JWT_A))
        .json(&json!({
            "initiator_sdp": SDP_A,
            "call_type": "group",
            "max_participants": 100
        }))
        .send()
        .await
        .expect("Failed to send request");

    assert!(
        response.status().is_client_error(),
        "Should reject max_participants > 50"
    );
    println!("✓ Max participants validation works");

    println!("\n✅ All error handling tests passed!\n");
}
