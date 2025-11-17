// Integration test for conversations listing endpoint (handler-level)
// Requires a running PostgreSQL with migrations applied by fixture

use actix_web::web;
use serde_json::Value;
use sqlx::PgPool;
use user_service::db::messaging::{ConversationType, MemberRole, MessagingRepository};
use user_service::handlers::messaging::{list_conversations, ListConversationsQuery};
use user_service::middleware::UserId;

mod common;

#[actix_web::test]
#[ignore] // Requires DATABASE_URL pointing to a test DB
async fn test_list_conversations_returns_total_and_last_message() {
    // Arrange: test DB
    let pool: PgPool = common::fixtures::create_test_pool().await;

    // Create two users
    let alice = common::fixtures::create_test_user(&pool).await;
    let bob = common::fixtures::create_test_user(&pool).await;

    // Create a direct conversation and add members
    let repo = MessagingRepository::new(&pool);
    let convo = repo
        .create_conversation(alice.id, ConversationType::Direct, None)
        .await
        .expect("create_conversation failed");
    repo.add_member(convo.id, alice.id, MemberRole::Owner)
        .await
        .expect("add_member alice failed");
    repo.add_member(convo.id, bob.id, MemberRole::Member)
        .await
        .expect("add_member bob failed");

    // Create a message to populate last_message and updated_at
    let _m = repo
        .create_message(
            convo.id,
            alice.id,
            "ZW5jcnlwdGVkLWJvZHk=".to_string(),
            "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==".to_string(),
            user_service::db::messaging::MessageType::Text,
        )
        .await
        .expect("create_message failed");

    // Act: call handler directly
    let resp = list_conversations(
        web::Data::new(pool.clone()),
        UserId(alice.id),
        web::Query(ListConversationsQuery {
            limit: Some(20),
            offset: Some(0),
            archived: Some(false),
        }),
    )
    .await;

    // Assert: 200 and shape
    let resp = resp.respond_to(&actix_web::HttpRequest::default()).map_into_boxed_body();
    assert_eq!(resp.status(), 200);
    let body = actix_web::body::to_bytes(resp.into_body()).await.unwrap();
    let json: Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["total"].as_i64().unwrap_or(-1), 1);
    let items = json["conversations"].as_array().expect("conversations array");
    assert_eq!(items.len(), 1);
    let item = &items[0];
    assert!(item["last_message"].is_object());
    assert!(item["unread_count"].is_number());
    assert!(item["updated_at"].is_string());
}

