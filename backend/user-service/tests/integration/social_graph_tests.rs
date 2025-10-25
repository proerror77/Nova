use actix_web::HttpResponse;
use sqlx::postgres::PgPoolOptions;
use std::sync::Arc;
use user_service::handlers::relationships::{follow_user, get_followers};
use user_service::middleware::jwt_auth::UserId;
use user_service::services::graph::GraphService;
use user_service::services::kafka_producer::EventProducer;
use uuid::Uuid;

#[actix_rt::test]
async fn test_follow_self_returns_400() {
    // Lazy pool (won't connect)
    let pool = PgPoolOptions::new()
        .max_connections(1)
        .connect_lazy("postgresql://localhost:5432/nova_auth")
        .expect("lazy pool");

    // Graph disabled (no connection)
    let graph = GraphService::new(&user_service::config::GraphConfig {
        enabled: false,
        neo4j_uri: String::new(),
        neo4j_user: String::new(),
        neo4j_password: String::new(),
    })
    .await
    .unwrap();

    // Kafka producer (no actual broker contact on create)
    let producer = Arc::new(
        EventProducer::new("localhost:9092", "events".to_string()).expect("producer"),
    );

    // Same user id for follower and path param
    let uid = Uuid::new_v4();
    let resp: HttpResponse = follow_user(
        actix_web::web::Path::from(uid.to_string()),
        actix_web::web::Data::new(pool),
        actix_web::web::Data::new(graph),
        actix_web::web::Data::new(producer),
        None,
        UserId(uid),
    )
    .await;

    assert_eq!(resp.status(), actix_web::http::StatusCode::BAD_REQUEST);
}

#[actix_rt::test]
async fn test_list_followers_invalid_id_returns_400() {
    // Lazy pool (won't connect)
    let pool = PgPoolOptions::new()
        .max_connections(1)
        .connect_lazy("postgresql://localhost:5432/nova_auth")
        .expect("lazy pool");

    // Query with invalid UUID
    let resp = get_followers(
        actix_web::web::Path::from("not-a-uuid".to_string()),
        actix_web::web::Query(std::collections::HashMap::new()),
        actix_web::web::Data::new(pool),
    )
    .await;

    assert_eq!(resp.status(), actix_web::http::StatusCode::BAD_REQUEST);
}

#[actix_rt::test]
async fn test_list_following_invalid_id_returns_400() {
    // Lazy pool (won't connect)
    let pool = PgPoolOptions::new()
        .max_connections(1)
        .connect_lazy("postgresql://localhost:5432/nova_auth")
        .expect("lazy pool");

    // Query with invalid UUID
    let resp = user_service::handlers::relationships::get_following(
        actix_web::web::Path::from("not-a-uuid".to_string()),
        actix_web::web::Query(std::collections::HashMap::new()),
        actix_web::web::Data::new(pool),
    )
    .await;

    assert_eq!(resp.status(), actix_web::http::StatusCode::BAD_REQUEST);
}
