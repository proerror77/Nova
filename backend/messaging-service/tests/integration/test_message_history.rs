use messaging_service::{config::Config, routes, state::AppState, db};
use axum::Router;
use testcontainers::{clients::Cli, images::postgres::Postgres as TcPostgres, images::generic::GenericImage, RunnableImage};
use sqlx::{Pool, Postgres};
use uuid::Uuid;
use redis::Client as RedisClient;
use base64::{engine::general_purpose, Engine as _};
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

async fn start_app(db: Pool<Postgres>, redis: RedisClient) -> String {
    let registry = messaging_service::websocket::ConnectionRegistry::new();
    let state = AppState {
        db,
        registry: registry.clone(),
        redis: redis.clone(),
        config: Arc::new(Config::test_defaults()),
        apns: None,
    };
    let app: Router<AppState> = routes::build_router().with_state(state);
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0)).await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn({
        let registry = registry.clone();
        async move {
            let config = messaging_service::websocket::streams::StreamsConfig::default();
            let _ = messaging_service::websocket::streams::start_streams_listener(
                redis,
                registry,
                config,
            )
            .await;
        }
    });
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    format!("http://{}:{}", addr.ip(), addr.port())
}

async fn start_redis() -> (Cli, RedisClient) {
    let docker = Cli::default();
    let image = GenericImage::new("redis:7-alpine").with_wait_for(testcontainers::core::WaitFor::message_on_stdout("Ready to accept connections"));
    let container = docker.run(image);
    let host = "127.0.0.1";
    let port = container.get_host_port_ipv4(6379);
    let client = RedisClient::open(format!("redis://{}:{}/", host, port)).unwrap();
    (docker, client)
}

#[tokio::test]
async fn message_history_ordering() {
    let key_b64 = general_purpose::STANDARD.encode([0u8;32]);
    std::env::set_var("SECRETBOX_KEY_B64", key_b64);
    let (_docker_db, pool) = start_db().await;
    let (_docker_redis, redis) = start_redis().await;
    let u1 = Uuid::new_v4();
    let u2 = Uuid::new_v4();
    sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2)").bind(u1).bind("alice").execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2)").bind(u2).bind("bob").execute(&pool).await.unwrap();
    let base = start_app(pool.clone(), redis).await;

    let body = serde_json::json!({"user_a": u1, "user_b": u2});
    let resp = reqwest::Client::new().post(format!("{}/conversations", base)).json(&body).send().await.unwrap();
    let v: serde_json::Value = resp.json().await.unwrap();
    let conv_id = Uuid::parse_str(v.get("id").unwrap().as_str().unwrap()).unwrap();

    // send multiple
    for i in 0..5 {
        let key = format!("k{}", i);
        let body = serde_json::json!({"sender_id": u1, "plaintext": format!("m{}", i), "idempotency_key": key});
        let resp = reqwest::Client::new().post(format!("{}/conversations/{}/messages", base, conv_id)).json(&body).send().await.unwrap();
        assert!(resp.status().is_success());
    }
    let resp = reqwest::Client::new().get(format!("{}/conversations/{}/messages", base, conv_id)).send().await.unwrap();
    let arr: serde_json::Value = resp.json().await.unwrap();
    let seqs: Vec<i64> = arr.as_array().unwrap().iter().map(|x| x.get("sequence_number").unwrap().as_i64().unwrap()).collect();
    let mut sorted = seqs.clone();
    sorted.sort();
    assert_eq!(seqs, sorted);
}
