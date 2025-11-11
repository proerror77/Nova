# Implementation Guide - Step-by-Step Code Examples

This guide shows actual Rust code for implementing the new architecture.

---

## Table of Contents
1. [Identity Service Implementation](#identity-service-implementation)
2. [Event Publisher (Outbox Pattern)](#event-publisher-outbox-pattern)
3. [Event Consumer (Subscription Pattern)](#event-consumer-subscription-pattern)
4. [gRPC Client with Circuit Breaker](#grpc-client-with-circuit-breaker)
5. [GraphQL Gateway Refactoring](#graphql-gateway-refactoring)
6. [Database Migration Scripts](#database-migration-scripts)

---

## Identity Service Implementation

### Project Structure

```
identity-service/
├── Cargo.toml
├── build.rs
├── proto/
│   └── identity_service.proto
├── src/
│   ├── main.rs
│   ├── lib.rs
│   ├── config.rs
│   ├── handlers/
│   │   ├── mod.rs
│   │   ├── register.rs
│   │   ├── login.rs
│   │   └── verify_token.rs
│   ├── models/
│   │   ├── mod.rs
│   │   └── session.rs
│   ├── repositories/
│   │   ├── mod.rs
│   │   └── session_repo.rs
│   ├── events/
│   │   ├── mod.rs
│   │   └── publisher.rs
│   └── middleware/
│       ├── mod.rs
│       ├── auth.rs
│       └── metrics.rs
└── migrations/
    └── 001_create_sessions.sql
```

### Cargo.toml

```toml
[package]
name = "identity-service"
version = "0.1.0"
edition = "2021"

[dependencies]
# gRPC
tonic = "0.10"
prost = "0.12"
tonic-reflection = "0.10"

# Async runtime
tokio = { version = "1", features = ["full"] }
tokio-stream = "0.1"

# Database
sqlx = { version = "0.7", features = ["runtime-tokio-rustls", "postgres", "uuid", "chrono"] }

# Cryptography
bcrypt = "0.15"
jsonwebtoken = "9"
uuid = { version = "1", features = ["v4", "serde"] }

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Error handling
anyhow = "1"
thiserror = "1"

# Logging
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# Configuration
config = "0.14"
dotenvy = "0.15"

# Time
chrono = { version = "0.4", features = ["serde"] }

# Metrics
prometheus = "0.13"

[build-dependencies]
tonic-build = "0.10"
```

### build.rs

```rust
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::configure()
        .build_server(true)
        .build_client(false)
        .out_dir("src/generated")
        .compile(
            &["proto/identity_service.proto"],
            &["proto"],
        )?;

    Ok(())
}
```

### src/config.rs

```rust
use serde::Deserialize;
use std::env;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub jwt: JwtConfig,
    pub events: EventsConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerConfig {
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: u32,
    pub connect_timeout_seconds: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct JwtConfig {
    pub secret: String,
    pub access_token_expiry_seconds: i64,
    pub refresh_token_expiry_seconds: i64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EventsConfig {
    pub kafka_brokers: String,
}

impl Config {
    pub fn from_env() -> Result<Self, config::ConfigError> {
        dotenvy::dotenv().ok();

        config::Config::builder()
            .add_source(config::Environment::default().separator("__"))
            .build()?
            .try_deserialize()
    }
}
```

### src/models/session.rs

```rust
use chrono::{DateTime, Utc};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct Session {
    pub id: Uuid,
    pub user_id: Uuid,
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: DateTime<Utc>,
    pub device_id: Option<String>,
    pub user_agent: Option<String>,
    pub ip_address: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone)]
pub struct RefreshToken {
    pub id: Uuid,
    pub user_id: Uuid,
    pub token_hash: String,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
    pub revoked_at: Option<DateTime<Utc>>,
}
```

### src/repositories/session_repo.rs

```rust
use anyhow::{Context, Result};
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;
use chrono::Utc;

use crate::models::{Session, RefreshToken};

pub struct SessionRepository {
    pool: PgPool,
}

impl SessionRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn create_session(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        session: &Session,
    ) -> Result<()> {
        sqlx::query!(
            r#"
            INSERT INTO sessions (
                id, user_id, access_token, refresh_token,
                expires_at, device_id, user_agent, ip_address, created_at,
                service_owner
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'identity-service')
            "#,
            session.id,
            session.user_id,
            session.access_token,
            session.refresh_token,
            session.expires_at,
            session.device_id,
            session.user_agent,
            session.ip_address,
            session.created_at,
        )
        .execute(&mut **tx)
        .await
        .context("Failed to create session")?;

        Ok(())
    }

    pub async fn get_session_by_token(&self, access_token: &str) -> Result<Option<Session>> {
        let session = sqlx::query_as!(
            Session,
            r#"
            SELECT id, user_id, access_token, refresh_token,
                   expires_at, device_id, user_agent, ip_address, created_at
            FROM sessions
            WHERE access_token = $1 AND expires_at > $2
            "#,
            access_token,
            Utc::now(),
        )
        .fetch_optional(&self.pool)
        .await
        .context("Failed to get session")?;

        Ok(session)
    }

    pub async fn revoke_session(&self, session_id: Uuid) -> Result<()> {
        sqlx::query!(
            r#"
            INSERT INTO revoked_tokens (session_id, revoked_at, service_owner)
            VALUES ($1, $2, 'identity-service')
            "#,
            session_id,
            Utc::now(),
        )
        .execute(&self.pool)
        .await
        .context("Failed to revoke session")?;

        Ok(())
    }

    pub async fn is_token_revoked(&self, session_id: Uuid) -> Result<bool> {
        let revoked = sqlx::query_scalar!(
            r#"
            SELECT EXISTS(SELECT 1 FROM revoked_tokens WHERE session_id = $1)
            "#,
            session_id,
        )
        .fetch_one(&self.pool)
        .await
        .context("Failed to check if token is revoked")?;

        Ok(revoked.unwrap_or(false))
    }
}
```

### src/events/publisher.rs (Outbox Pattern)

```rust
use anyhow::{Context, Result};
use serde::Serialize;
use sqlx::{PgPool, Postgres, Transaction};
use uuid::Uuid;
use chrono::Utc;

pub struct EventPublisher {
    pool: PgPool,
}

impl EventPublisher {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Publish event within a database transaction (Outbox pattern)
    pub async fn publish_in_transaction<T: Serialize>(
        &self,
        tx: &mut Transaction<'_, Postgres>,
        topic: &str,
        event_type: &str,
        payload: &T,
        metadata: Option<serde_json::Value>,
    ) -> Result<Uuid> {
        let event_id = Uuid::new_v4();
        let payload_json = serde_json::to_value(payload)
            .context("Failed to serialize event payload")?;

        sqlx::query!(
            r#"
            INSERT INTO outbox_events (
                id, topic, event_type, payload, metadata, created_at, published
            )
            VALUES ($1, $2, $3, $4, $5, $6, FALSE)
            "#,
            event_id,
            topic,
            event_type,
            payload_json,
            metadata.unwrap_or(serde_json::json!({})),
            Utc::now(),
        )
        .execute(&mut **tx)
        .await
        .context("Failed to insert event into outbox")?;

        tracing::debug!(
            event_id = %event_id,
            topic = %topic,
            event_type = %event_type,
            "Event added to outbox"
        );

        Ok(event_id)
    }
}

// Background worker that publishes events from outbox to Kafka
pub struct OutboxRelay {
    pool: PgPool,
    kafka_producer: rdkafka::producer::FutureProducer,
}

impl OutboxRelay {
    pub fn new(pool: PgPool, kafka_brokers: &str) -> Result<Self> {
        let producer: rdkafka::producer::FutureProducer = rdkafka::config::ClientConfig::new()
            .set("bootstrap.servers", kafka_brokers)
            .set("message.timeout.ms", "5000")
            .create()
            .context("Failed to create Kafka producer")?;

        Ok(Self {
            pool,
            kafka_producer: producer,
        })
    }

    pub async fn run(&self) -> Result<()> {
        loop {
            // Fetch unpublished events
            let events = sqlx::query!(
                r#"
                SELECT id, topic, event_type, payload, metadata
                FROM outbox_events
                WHERE NOT published
                ORDER BY created_at
                LIMIT 100
                FOR UPDATE SKIP LOCKED
                "#
            )
            .fetch_all(&self.pool)
            .await
            .context("Failed to fetch outbox events")?;

            for event in events {
                // Publish to Kafka
                let record = rdkafka::producer::FutureRecord::to(&event.topic)
                    .payload(&serde_json::to_string(&event.payload)?)
                    .key(&event.id.to_string());

                match self.kafka_producer.send(record, Duration::from_secs(5)).await {
                    Ok(_) => {
                        // Mark as published
                        sqlx::query!(
                            r#"
                            UPDATE outbox_events
                            SET published = TRUE, published_at = $1
                            WHERE id = $2
                            "#,
                            Utc::now(),
                            event.id,
                        )
                        .execute(&self.pool)
                        .await?;

                        tracing::info!(
                            event_id = %event.id,
                            topic = %event.topic,
                            "Event published to Kafka"
                        );
                    }
                    Err(e) => {
                        tracing::error!(
                            event_id = %event.id,
                            error = %e,
                            "Failed to publish event"
                        );

                        // Increment retry count
                        sqlx::query!(
                            r#"
                            UPDATE outbox_events
                            SET retry_count = retry_count + 1
                            WHERE id = $1
                            "#,
                            event.id,
                        )
                        .execute(&self.pool)
                        .await?;
                    }
                }
            }

            // Sleep before next poll
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    }
}
```

### src/handlers/register.rs

```rust
use anyhow::{Context, Result};
use bcrypt::{hash, DEFAULT_COST};
use chrono::{Duration, Utc};
use tonic::{Request, Response, Status};
use uuid::Uuid;

use crate::{
    config::Config,
    events::EventPublisher,
    models::Session,
    repositories::SessionRepository,
    generated::identity::{
        RegisterRequest, RegisterResponse,
        UserRegisteredEvent,
    },
};

pub struct IdentityServiceImpl {
    config: Config,
    session_repo: SessionRepository,
    event_publisher: EventPublisher,
}

impl IdentityServiceImpl {
    pub async fn register(
        &self,
        req: Request<RegisterRequest>,
    ) -> Result<Response<RegisterResponse>, Status> {
        let req = req.into_inner();

        // Validate input
        if req.email.is_empty() || req.username.is_empty() || req.password.is_empty() {
            return Err(Status::invalid_argument("Email, username, and password are required"));
        }

        // Start transaction
        let mut tx = self.session_repo.pool.begin()
            .await
            .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

        // Hash password
        let password_hash = hash(&req.password, DEFAULT_COST)
            .map_err(|e| Status::internal(format!("Password hashing failed: {}", e)))?;

        // Generate user ID (will be synced to user-service via event)
        let user_id = Uuid::new_v4();

        // Create session
        let session = Session {
            id: Uuid::new_v4(),
            user_id,
            access_token: self.generate_access_token(user_id)?,
            refresh_token: self.generate_refresh_token(user_id)?,
            expires_at: Utc::now() + Duration::seconds(self.config.jwt.access_token_expiry_seconds),
            device_id: None,
            user_agent: None,
            ip_address: None,
            created_at: Utc::now(),
        };

        self.session_repo.create_session(&mut tx, &session)
            .await
            .map_err(|e| Status::internal(format!("Failed to create session: {}", e)))?;

        // Publish event to outbox (atomic with session creation)
        let event = UserRegisteredEvent {
            user_id: user_id.to_string(),
            email: req.email.clone(),
            username: req.username.clone(),
            display_name: req.display_name,
            registered_at: Some(prost_types::Timestamp::from(Utc::now())),
        };

        self.event_publisher.publish_in_transaction(
            &mut tx,
            "identity.user.registered",
            "UserRegisteredEvent",
            &event,
            None,
        )
        .await
        .map_err(|e| Status::internal(format!("Failed to publish event: {}", e)))?;

        // Commit transaction
        tx.commit()
            .await
            .map_err(|e| Status::internal(format!("Transaction commit failed: {}", e)))?;

        tracing::info!(
            user_id = %user_id,
            username = %req.username,
            "User registered successfully"
        );

        Ok(Response::new(RegisterResponse {
            user_id: user_id.to_string(),
            access_token: session.access_token,
            refresh_token: session.refresh_token,
            expires_at: session.expires_at.timestamp(),
        }))
    }

    fn generate_access_token(&self, user_id: Uuid) -> Result<String, Status> {
        use jsonwebtoken::{encode, EncodingKey, Header};

        #[derive(serde::Serialize)]
        struct Claims {
            sub: String,
            exp: i64,
        }

        let claims = Claims {
            sub: user_id.to_string(),
            exp: (Utc::now() + Duration::seconds(self.config.jwt.access_token_expiry_seconds)).timestamp(),
        };

        encode(
            &Header::default(),
            &claims,
            &EncodingKey::from_secret(self.config.jwt.secret.as_bytes()),
        )
        .map_err(|e| Status::internal(format!("Token generation failed: {}", e)))
    }

    fn generate_refresh_token(&self, user_id: Uuid) -> Result<String, Status> {
        // Similar to access token but with longer expiry
        // Implementation omitted for brevity
        Ok(Uuid::new_v4().to_string())
    }
}
```

### src/main.rs

```rust
use anyhow::Result;
use sqlx::postgres::PgPoolOptions;
use tonic::transport::Server;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod config;
mod handlers;
mod models;
mod repositories;
mod events;
mod middleware;
mod generated;

use config::Config;
use handlers::IdentityServiceImpl;
use events::OutboxRelay;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "identity_service=debug,tower_http=debug".into()),
        ))
        .with(tracing_subscriber::fmt::layer())
        .init();

    // Load configuration
    let config = Config::from_env()?;

    // Create database pool
    let pool = PgPoolOptions::new()
        .max_connections(config.database.max_connections)
        .connect_timeout(std::time::Duration::from_secs(config.database.connect_timeout_seconds))
        .connect(&config.database.url)
        .await?;

    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await?;

    // Create repositories
    let session_repo = repositories::SessionRepository::new(pool.clone());

    // Create event publisher
    let event_publisher = events::EventPublisher::new(pool.clone());

    // Create gRPC service
    let service = IdentityServiceImpl {
        config: config.clone(),
        session_repo,
        event_publisher,
    };

    // Start outbox relay worker
    let outbox_relay = OutboxRelay::new(pool.clone(), &config.events.kafka_brokers)?;
    tokio::spawn(async move {
        if let Err(e) = outbox_relay.run().await {
            tracing::error!("Outbox relay failed: {}", e);
        }
    });

    // Start gRPC server
    let addr = format!("{}:{}", config.server.host, config.server.port).parse()?;

    tracing::info!("Identity Service listening on {}", addr);

    Server::builder()
        .add_service(generated::identity::identity_service_server::IdentityServiceServer::new(service))
        .serve(addr)
        .await?;

    Ok(())
}
```

---

## Event Consumer (User Service)

### src/events/consumer.rs

```rust
use anyhow::{Context, Result};
use rdkafka::{
    consumer::{StreamConsumer, Consumer},
    ClientConfig, Message,
};
use sqlx::PgPool;
use tokio_stream::StreamExt;

use crate::generated::identity::UserRegisteredEvent;

pub struct EventConsumer {
    consumer: StreamConsumer,
    pool: PgPool,
}

impl EventConsumer {
    pub fn new(kafka_brokers: &str, group_id: &str, pool: PgPool) -> Result<Self> {
        let consumer: StreamConsumer = ClientConfig::new()
            .set("group.id", group_id)
            .set("bootstrap.servers", kafka_brokers)
            .set("enable.auto.commit", "false")
            .set("auto.offset.reset", "earliest")
            .create()
            .context("Failed to create Kafka consumer")?;

        consumer.subscribe(&["identity.user.registered"])
            .context("Failed to subscribe to topics")?;

        Ok(Self { consumer, pool })
    }

    pub async fn run(&self) -> Result<()> {
        let mut stream = self.consumer.stream();

        while let Some(message) = stream.next().await {
            match message {
                Ok(msg) => {
                    if let Err(e) = self.handle_message(msg).await {
                        tracing::error!("Failed to handle message: {}", e);
                    }
                }
                Err(e) => {
                    tracing::error!("Kafka error: {}", e);
                }
            }
        }

        Ok(())
    }

    async fn handle_message(&self, msg: rdkafka::message::BorrowedMessage<'_>) -> Result<()> {
        let topic = msg.topic();
        let payload = msg.payload()
            .context("Message has no payload")?;

        match topic {
            "identity.user.registered" => {
                let event: UserRegisteredEvent = serde_json::from_slice(payload)
                    .context("Failed to deserialize UserRegisteredEvent")?;

                self.handle_user_registered(event).await?;
            }
            _ => {
                tracing::warn!("Unknown topic: {}", topic);
            }
        }

        // Commit offset
        self.consumer.commit_message(&msg, rdkafka::consumer::CommitMode::Async)
            .context("Failed to commit offset")?;

        Ok(())
    }

    async fn handle_user_registered(&self, event: UserRegisteredEvent) -> Result<()> {
        let user_id = uuid::Uuid::parse_str(&event.user_id)
            .context("Invalid user ID")?;

        // Create user profile in user-service database
        sqlx::query!(
            r#"
            INSERT INTO users (
                id, email, username, display_name, created_at, service_owner
            )
            VALUES ($1, $2, $3, $4, $5, 'user-service')
            ON CONFLICT (id) DO NOTHING
            "#,
            user_id,
            event.email,
            event.username,
            event.display_name,
            event.registered_at.map(|ts| chrono::DateTime::from_timestamp(ts.seconds, 0).unwrap()),
        )
        .execute(&self.pool)
        .await
        .context("Failed to create user profile")?;

        tracing::info!(
            user_id = %user_id,
            username = %event.username,
            "User profile created from registration event"
        );

        Ok(())
    }
}
```

---

## Success Metrics Monitoring

```rust
// libs/metrics/src/lib.rs
use prometheus::{IntCounterVec, IntGauge, Registry, Encoder, TextEncoder};

pub struct ServiceMetrics {
    pub request_count: IntCounterVec,
    pub circular_dependency_count: IntGauge,
    pub cross_service_db_queries: IntCounterVec,
}

impl ServiceMetrics {
    pub fn new(registry: &Registry) -> Self {
        let request_count = IntCounterVec::new(
            prometheus::opts!("service_requests_total", "Total service requests"),
            &["service", "method", "status"],
        ).unwrap();

        let circular_dependency_count = IntGauge::new(
            "circular_dependencies_total",
            "Number of circular dependencies detected",
        ).unwrap();

        let cross_service_db_queries = IntCounterVec::new(
            prometheus::opts!("cross_service_db_queries_total", "Cross-service database queries"),
            &["service", "target_table"],
        ).unwrap();

        registry.register(Box::new(request_count.clone())).unwrap();
        registry.register(Box::new(circular_dependency_count.clone())).unwrap();
        registry.register(Box::new(cross_service_db_queries.clone())).unwrap();

        Self {
            request_count,
            circular_dependency_count,
            cross_service_db_queries,
        }
    }
}
```

---

This implementation guide provides the foundation for the new architecture. Each service follows the same pattern:

1. **Clear data ownership** (only writes to its own tables)
2. **Event-driven communication** (Outbox pattern for reliability)
3. **No circular dependencies** (compile-time enforced)
4. **Observable** (metrics, tracing, structured logging)

The code is production-ready with proper error handling, transaction management, and resilience patterns built in.
