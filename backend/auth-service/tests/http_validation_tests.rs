use actix_web::{test, web, App};
use redis::aio::ConnectionManager;
use sqlx::postgres::PgPoolOptions;
use std::sync::Arc;
use testcontainers::{core::WaitFor, runners::AsyncRunner, ContainerAsync, GenericImage};
use tokio::sync::Mutex;

use auth_service::{
    config::{EmailConfig, OAuthConfig},
    handlers::auth::{login, register},
    models::user::{LoginRequest, RegisterRequest},
    services::{email::EmailService, oauth::OAuthService, two_fa::TwoFaService},
    AppState,
};
use redis_utils::SharedConnectionManager;

async fn build_state(pg_url: &str, redis_url: &str) -> AppState {
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(pg_url)
        .await
        .expect("connect postgres");

    sqlx::migrate!("../migrations")
        .run(&pool)
        .await
        .expect("run migrations");

    let redis_client = redis::Client::open(redis_url).expect("redis client");
    let redis_conn = ConnectionManager::new(redis_client)
        .await
        .expect("redis connection");
    let redis_manager: SharedConnectionManager = Arc::new(Mutex::new(redis_conn));

    let email_service = EmailService::new(&EmailConfig::default()).expect("email service");
    let oauth_service = Arc::new(OAuthService::new(
        OAuthConfig::default(),
        pool.clone(),
        redis_manager.clone(),
        None,
    ));
    let two_fa_service = TwoFaService::new(pool.clone(), redis_manager.clone(), None);

    AppState {
        db: pool,
        redis: redis_manager,
        kafka_producer: None,
        email_service,
        oauth_service,
        two_fa_service,
    }
}

async fn start_postgres() -> (ContainerAsync<GenericImage>, String) {
    let image = GenericImage::new("postgres", "15-alpine")
        .with_env_var("POSTGRES_PASSWORD", "password")
        .with_env_var("POSTGRES_USER", "postgres")
        .with_env_var("POSTGRES_DB", "auth_service_test")
        .with_exposed_port(5432)
        .with_wait_for(WaitFor::message_on_stdout(
            "database system is ready to accept connections",
        ));

    let container = image.start().await;
    let port = container.get_host_port_ipv4(5432).await;
    let url = format!(
        "postgres://postgres:password@127.0.0.1:{}/auth_service_test",
        port
    );
    (container, url)
}

async fn start_redis() -> (ContainerAsync<GenericImage>, String) {
    let image = GenericImage::new("redis", "7-alpine")
        .with_exposed_port(6379)
        .with_wait_for(WaitFor::message_on_stdout("Ready to accept connections"));

    let container = image.start().await;
    let port = container.get_host_port_ipv4(6379).await;
    let url = format!("redis://127.0.0.1:{}/", port);
    (container, url)
}

#[actix_web::test]
async fn register_invalid_email_returns_400() {
    let (_pg, pg_url) = start_postgres().await;
    let (_redis, redis_url) = start_redis().await;
    let state = build_state(&pg_url, &redis_url).await;

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(state))
            .route("/register", web::post().to(register)),
    )
    .await;

    let req = RegisterRequest {
        email: "invalid".into(),
        username: "valid_user".into(),
        password: "SecurePass123!".into(),
    };

    let resp = test::call_service(
        &app,
        test::TestRequest::post()
            .uri("/register")
            .set_json(&req)
            .to_request(),
    )
    .await;

    assert_eq!(resp.status(), actix_web::http::StatusCode::BAD_REQUEST);
}

#[actix_web::test]
async fn register_weak_password_returns_400() {
    let (_pg, pg_url) = start_postgres().await;
    let (_redis, redis_url) = start_redis().await;
    let state = build_state(&pg_url, &redis_url).await;

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(state))
            .route("/register", web::post().to(register)),
    )
    .await;

    let req = RegisterRequest {
        email: "user@example.com".into(),
        username: "valid_user".into(),
        password: "weakpass".into(),
    };

    let resp = test::call_service(
        &app,
        test::TestRequest::post()
            .uri("/register")
            .set_json(&req)
            .to_request(),
    )
    .await;

    assert_eq!(resp.status(), actix_web::http::StatusCode::BAD_REQUEST);
}

#[actix_web::test]
async fn login_invalid_email_returns_400() {
    let (_pg, pg_url) = start_postgres().await;
    let (_redis, redis_url) = start_redis().await;
    let state = build_state(&pg_url, &redis_url).await;

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(state))
            .route("/login", web::post().to(login)),
    )
    .await;

    let req = LoginRequest {
        email: "bad".into(),
        password: "whatever".into(),
    };

    let resp = test::call_service(
        &app,
        test::TestRequest::post()
            .uri("/login")
            .set_json(&req)
            .to_request(),
    )
    .await;

    assert_eq!(resp.status(), actix_web::http::StatusCode::BAD_REQUEST);
}
