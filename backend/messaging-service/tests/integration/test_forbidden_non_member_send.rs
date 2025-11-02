use messaging_service::{config::Config, routes, state::AppState, db, redis_client::RedisClient, services::encryption::EncryptionService};
use actix_web::{web, App, HttpServer};
use testcontainers::{clients::Cli, images::postgres::Postgres as TcPostgres, images::generic::GenericImage, RunnableImage};
use sqlx::{Pool, Postgres};
use uuid::Uuid;
use std::sync::Arc;

async fn start_db() -> (Cli, Pool<Postgres>) {
    let docker = Cli::default();
    let image = RunnableImage::from(TcPostgres::default()).with_env_var(("POSTGRES_PASSWORD", "postgres"));
    let container = docker.run(image);
    let host = "127.0.0.1";
    let port = container.get_host_port_ipv4(5432);
    let admin_url = format!("postgres://postgres:postgres@{}:{}/postgres", host, port);
    let pool = sqlx::postgres::PgPoolOptions::new().max_connections(5).connect(&admin_url).await.unwrap();
    let dbname = format!("msg_{}", Uuid::new_v4().to_string().replace('-', ""));
    sqlx::query(&format!("CREATE DATABASE {}", dbname)).execute(&pool).await.unwrap();
    let test_url = format!("postgres://postgres:postgres@{}:{}/{}", host, port, dbname);
    let test_pool = sqlx::postgres::PgPoolOptions::new().max_connections(5).connect(&test_url).await.unwrap();
    db::MIGRATOR.run(&test_pool).await.unwrap();
    (docker, test_pool)
}

async fn start_redis() -> (Cli, RedisClient) {
    let docker = Cli::default();
    let image = GenericImage::new("redis:7-alpine").with_wait_for(testcontainers::core::WaitFor::message_on_stdout("Ready to accept connections"));
    let container = docker.run(image);
    let host = "127.0.0.1";
    let port = container.get_host_port_ipv4(6379);
    let client = RedisClient::from_url(&format!("redis://{}:{}/", host, port)).await.expect("Failed to create Redis client");
    (docker, client)
}

async fn start_app(db: Pool<Postgres>, redis: RedisClient) -> String {
    let registry = messaging_service::websocket::ConnectionRegistry::new();
    let cfg = Config::test_defaults();
    let state = AppState {
        db,
        registry: registry.clone(),
        redis: redis.clone(),
        config: Arc::new(cfg.clone()),
        apns: None,
        encryption: Arc::new(EncryptionService::new(cfg.encryption_master_key)),
        key_exchange_service: None,
    };
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let redis_clone = redis.clone();
    tokio::spawn({
        let registry = registry.clone();
        async move {
            let config = messaging_service::websocket::streams::StreamsConfig::default();
            let _ = messaging_service::websocket::streams::start_streams_listener(
                redis_clone,
                registry,
                config,
            )
            .await;
        }
    });
    tokio::spawn(async move {
        let state_data = web::Data::new(state);
        let server = HttpServer::new(move || {
            App::new()
                .app_data(state_data.clone())
                .configure(routes::configure_routes)
        })
        .listen(listener)
        .expect("Failed to bind server")
        .run();
        let _ = server.await;
    });
    format!("http://{}:{}", addr.ip(), addr.port())
}

#[tokio::test]
async fn non_member_cannot_send_message() {
    let (_docker_db, pool) = start_db().await;
    let (_docker_redis, redis) = start_redis().await;
    let u1 = Uuid::new_v4();
    let u2 = Uuid::new_v4();
    let u3 = Uuid::new_v4(); // not a member
    sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2)").bind(u1).bind("alice").execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2)").bind(u2).bind("bob").execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2)").bind(u3).bind("charlie").execute(&pool).await.unwrap();
    let base = start_app(pool.clone(), redis).await;

    // create conversation for u1,u2
    let body = serde_json::json!({"user_a": u1, "user_b": u2});
    let resp = reqwest::Client::new().post(format!("{}/conversations", base)).json(&body).send().await.unwrap();
    let v: serde_json::Value = resp.json().await.unwrap();
    let conv_id = Uuid::parse_str(v.get("id").unwrap().as_str().unwrap()).unwrap();

    // u3 try to send -> 403
    let body = serde_json::json!({"sender_id": u3, "plaintext": "hi", "idempotency_key": "z"});
    let resp = reqwest::Client::new().post(format!("{}/conversations/{}/messages", base, conv_id)).json(&body).send().await.unwrap();
    assert_eq!(resp.status(), reqwest::StatusCode::FORBIDDEN);
}
