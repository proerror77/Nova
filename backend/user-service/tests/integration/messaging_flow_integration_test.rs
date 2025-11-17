// Messaging flow integration (handler-level): create convo -> send -> history -> read
// Ignored by default; requires DATABASE_URL to a writable test DB.

use actix_web::{body, web, Responder};
use serde_json::Value;
use sqlx::PgPool;
use user_service::db::messaging::{ConversationType, MemberRole, MessagingRepository};
use user_service::handlers::messaging::{
    get_message_history, mark_as_read, send_message, MessageHistoryQuery, MarkReadRequest,
    SendMessageRequest,
};
use user_service::middleware::UserId;
use uuid::Uuid;

mod common;

#[actix_web::test]
#[ignore]
async fn test_messaging_flow_minimal() {
    let pool: PgPool = common::fixtures::create_test_pool().await;

    // Create two users
    let alice = common::fixtures::create_test_user(&pool).await; // sender
    let bob = common::fixtures::create_test_user(&pool).await; // recipient

    // Create a direct conversation with alice owner + bob member
    let repo = MessagingRepository::new(&pool);
    let convo = repo
        .create_conversation(alice.id, ConversationType::Direct, None)
        .await
        .expect("create_conversation");
    repo.add_member(convo.id, alice.id, MemberRole::Owner)
        .await
        .expect("add_member alice");
    repo.add_member(convo.id, bob.id, MemberRole::Member)
        .await
        .expect("add_member bob");

    // Send message as alice
    let resp_send = send_message(
        web::Data::new(pool.clone()),
        UserId(alice.id),
        web::Json(SendMessageRequest {
            conversation_id: convo.id,
            encrypted_content: "ZW5jcnlwdGVkLWJvZHk=".to_string(),
            nonce: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==".to_string(),
            message_type: "text".to_string(),
        }),
    )
    .await
    .respond_to(&actix_web::HttpRequest::default())
    .map_into_boxed_body();
    assert_eq!(resp_send.status(), 201);
    let body = body::to_bytes(resp_send.into_body()).await.unwrap();
    let msg: Value = serde_json::from_slice(&body).unwrap();
    let message_id = Uuid::parse_str(msg["id"].as_str().unwrap()).unwrap();

    // Get history (as bob), should include the sent message
    let resp_hist = get_message_history(
        web::Data::new(pool.clone()),
        UserId(bob.id),
        web::Path::from(convo.id),
        web::Query(MessageHistoryQuery {
            limit: Some(50),
            before: None,
        }),
    )
    .await
    .respond_to(&actix_web::HttpRequest::default())
    .map_into_boxed_body();
    assert_eq!(resp_hist.status(), 200);
    let body = body::to_bytes(resp_hist.into_body()).await.unwrap();
    let hist: Value = serde_json::from_slice(&body).unwrap();
    assert!(hist["messages"].is_array());
    assert!(hist["messages"].as_array().unwrap().iter().any(|m| m["id"] == message_id.to_string()));

    // Mark as read (bob)
    let resp_read = mark_as_read(
        web::Data::new(pool.clone()),
        UserId(bob.id),
        web::Path::from(convo.id),
        web::Json(MarkReadRequest { message_id }),
    )
    .await
    .respond_to(&actix_web::HttpRequest::default())
    .map_into_boxed_body();
    assert_eq!(resp_read.status(), 200);
}

