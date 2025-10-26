use messaging_service::{config::Config, routes, state::AppState, db};
use axum::Router;
use testcontainers::{clients::Cli, images::postgres::Postgres as TcPostgres, images::generic::GenericImage, RunnableImage};
use sqlx::{Pool, Postgres};
use uuid::Uuid;
use redis::Client as RedisClient;
use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::tungstenite::Message as WsMessage;
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
    let client = RedisClient::open(format!("redis://{}:{}/", host, port)).unwrap();
    (docker, client)
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
        async move { let _ = messaging_service::websocket::pubsub::start_psub_listener(redis, registry).await; }
    });
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    format!("http://{}:{}", addr.ip(), addr.port())
}

#[tokio::test]
async fn ws_typing_broadcast_between_two_clients() {
    let (_docker_db, pool) = start_db().await;
    let (_docker_redis, redis) = start_redis().await;
    // users + conversation
    let u1 = Uuid::new_v4();
    let u2 = Uuid::new_v4();
    sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2)").bind(u1).bind("alice").execute(&pool).await.unwrap();
    sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2)").bind(u2).bind("bob").execute(&pool).await.unwrap();
    let base = start_app(pool.clone(), redis).await;
    let body = serde_json::json!({"user_a": u1, "user_b": u2});
    let resp = reqwest::Client::new().post(format!("{}/conversations", base)).json(&body).send().await.unwrap();
    let v: serde_json::Value = resp.json().await.unwrap();
    let conv_id = Uuid::parse_str(v.get("id").unwrap().as_str().unwrap()).unwrap();

    // Connect two WS clients
    let ws_base = base.replacen("http", "ws", 1);
    let url_a = format!("{}/ws?conversation_id={}&user_id={}", ws_base, conv_id, u1);
    let url_b = format!("{}/ws?conversation_id={}&user_id={}", ws_base, conv_id, u2);
    let (mut a, _) = tokio_tungstenite::connect_async(url_a).await.unwrap();
    let (mut b, _) = tokio_tungstenite::connect_async(url_b).await.unwrap();

    // A sends typing event
    let typing = serde_json::json!({"type":"typing","conversation_id": conv_id, "user_id": u1}).to_string();
    a.send(WsMessage::Text(typing.clone())).await.unwrap();

    // B should receive
    let msg = b.next().await.unwrap().unwrap();
    match msg {
        WsMessage::Text(txt) => {
            assert!(txt.contains("typing"));
        }
        other => panic!("unexpected WS msg: {:?}", other)
    }
}
