/// Bulk sync users from identity-service database to Elasticsearch
///
/// This tool is used for initial data population and recovery scenarios.
/// It reads users from the PostgreSQL database and indexes them into Elasticsearch.
///
/// Usage:
///   IDENTITY_DATABASE_URL=postgres://... ELASTICSEARCH_URL=http://... cargo run --bin sync-users
///
/// Environment variables:
///   - IDENTITY_DATABASE_URL: PostgreSQL connection string for identity-service database
///   - ELASTICSEARCH_URL: Elasticsearch connection string
///   - SYNC_BATCH_SIZE: Number of users to sync per batch (default: 100)
///   - SYNC_DELAY_MS: Delay between batches in milliseconds (default: 100)
use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::postgres::PgPoolOptions;
use sqlx::{FromRow, PgPool};
use std::env;
use std::time::Duration;
use tracing::{error, info, warn};
use uuid::Uuid;

/// User record from identity-service database
#[derive(Debug, FromRow)]
struct UserRecord {
    id: Uuid,
    username: String,
    display_name: Option<String>,
    bio: Option<String>,
    avatar_url: Option<String>,
    #[allow(dead_code)]
    created_at: DateTime<Utc>,
}

/// Elasticsearch user document
#[derive(Debug, Serialize)]
struct UserDocument {
    user_id: String,
    username: String,
    display_name: String,
    bio: Option<String>,
    avatar_url: Option<String>,
    location: Option<String>,
    interests: Vec<String>,
    is_verified: bool,
    follower_count: i32,
}

/// Elasticsearch client wrapper for bulk indexing
struct ElasticsearchSync {
    client: reqwest::Client,
    base_url: String,
}

impl ElasticsearchSync {
    fn new(base_url: &str) -> Self {
        Self {
            client: reqwest::Client::new(),
            base_url: base_url.trim_end_matches('/').to_string(),
        }
    }

    /// Ensure the users index exists with proper mapping
    async fn ensure_index(&self) -> Result<()> {
        let index_url = format!("{}/users", self.base_url);

        // Check if index exists
        let response = self.client.head(&index_url).send().await?;

        if response.status().is_success() {
            info!("Users index already exists");
            return Ok(());
        }

        // Create index with mapping
        let mapping = serde_json::json!({
            "settings": {
                "number_of_shards": 1,
                "number_of_replicas": 1,
                "analysis": {
                    "analyzer": {
                        "username_analyzer": {
                            "type": "custom",
                            "tokenizer": "standard",
                            "filter": ["lowercase", "asciifolding"]
                        }
                    }
                }
            },
            "mappings": {
                "properties": {
                    "user_id": { "type": "keyword" },
                    "username": {
                        "type": "text",
                        "analyzer": "username_analyzer",
                        "fields": {
                            "keyword": { "type": "keyword" }
                        }
                    },
                    "display_name": {
                        "type": "text",
                        "analyzer": "standard",
                        "fields": {
                            "keyword": { "type": "keyword" }
                        }
                    },
                    "bio": { "type": "text" },
                    "location": { "type": "text" },
                    "interests": { "type": "keyword" },
                    "is_verified": { "type": "boolean" },
                    "follower_count": { "type": "integer" }
                }
            }
        });

        let response = self.client.put(&index_url).json(&mapping).send().await?;

        if response.status().is_success() {
            info!("Created users index with mapping");
            Ok(())
        } else {
            let error_text = response.text().await?;
            error!("Failed to create index: {}", error_text);
            anyhow::bail!("Failed to create Elasticsearch index: {}", error_text)
        }
    }

    /// Index a single user document
    async fn index_user(&self, doc: &UserDocument) -> Result<()> {
        let url = format!("{}/users/_doc/{}", self.base_url, doc.user_id);

        let response = self
            .client
            .put(&url)
            .json(doc)
            .send()
            .await
            .context("Failed to send index request")?;

        if response.status().is_success() {
            Ok(())
        } else {
            let error_text = response.text().await?;
            anyhow::bail!("Failed to index user {}: {}", doc.user_id, error_text)
        }
    }

    /// Bulk index multiple user documents
    async fn bulk_index(&self, docs: &[UserDocument]) -> Result<(usize, usize)> {
        if docs.is_empty() {
            return Ok((0, 0));
        }

        // Build NDJSON bulk request body
        let mut body = String::new();
        for doc in docs {
            // Action line
            let action = serde_json::json!({
                "index": {
                    "_index": "users",
                    "_id": doc.user_id
                }
            });
            body.push_str(&serde_json::to_string(&action)?);
            body.push('\n');

            // Document line
            body.push_str(&serde_json::to_string(doc)?);
            body.push('\n');
        }

        let url = format!("{}/_bulk", self.base_url);

        let response = self
            .client
            .post(&url)
            .header("Content-Type", "application/x-ndjson")
            .body(body)
            .send()
            .await
            .context("Failed to send bulk request")?;

        if response.status().is_success() {
            let result: serde_json::Value = response.json().await?;

            // Count successes and failures
            let empty_vec = vec![];
            let items = result["items"].as_array().unwrap_or(&empty_vec);
            let mut success_count = 0;
            let mut failure_count = 0;

            for item in items {
                if let Some(index_result) = item.get("index") {
                    if index_result["error"].is_null() {
                        success_count += 1;
                    } else {
                        failure_count += 1;
                        warn!(
                            "Failed to index user: {}",
                            serde_json::to_string_pretty(index_result)?
                        );
                    }
                }
            }

            Ok((success_count, failure_count))
        } else {
            let error_text = response.text().await?;
            anyhow::bail!("Bulk index failed: {}", error_text)
        }
    }
}

/// Fetch users from PostgreSQL with pagination
async fn fetch_users(pool: &PgPool, offset: i64, limit: i64) -> Result<Vec<UserRecord>> {
    let users = sqlx::query_as::<_, UserRecord>(
        r#"
        SELECT id, username, display_name, bio, avatar_url, created_at
        FROM users
        WHERE deleted_at IS NULL
        ORDER BY created_at ASC
        LIMIT $1 OFFSET $2
        "#,
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await
    .context("Failed to fetch users from database")?;

    Ok(users)
}

/// Get total count of users
async fn get_user_count(pool: &PgPool) -> Result<i64> {
    let count: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM users WHERE deleted_at IS NULL")
        .fetch_one(pool)
        .await
        .context("Failed to count users")?;

    Ok(count.0)
}

/// Convert database record to Elasticsearch document
fn to_es_document(user: &UserRecord) -> UserDocument {
    UserDocument {
        user_id: user.id.to_string(),
        username: user.username.clone(),
        display_name: user.display_name.clone().unwrap_or_default(),
        bio: user.bio.clone(),
        avatar_url: user.avatar_url.clone(),
        location: None,
        interests: vec![],
        is_verified: false,
        follower_count: 0,
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("sync_users=info".parse()?)
                .add_directive("sqlx=warn".parse()?),
        )
        .init();

    info!("Starting user sync to Elasticsearch...");

    // Read configuration from environment
    let database_url = env::var("IDENTITY_DATABASE_URL")
        .context("IDENTITY_DATABASE_URL environment variable not set")?;

    let elasticsearch_url =
        env::var("ELASTICSEARCH_URL").context("ELASTICSEARCH_URL environment variable not set")?;

    let batch_size: i64 = env::var("SYNC_BATCH_SIZE")
        .unwrap_or_else(|_| "100".to_string())
        .parse()
        .context("Invalid SYNC_BATCH_SIZE")?;

    let delay_ms: u64 = env::var("SYNC_DELAY_MS")
        .unwrap_or_else(|_| "100".to_string())
        .parse()
        .context("Invalid SYNC_DELAY_MS")?;

    info!(
        batch_size = batch_size,
        delay_ms = delay_ms,
        "Configuration loaded"
    );

    // Connect to PostgreSQL
    info!("Connecting to PostgreSQL...");
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(30))
        .connect(&database_url)
        .await
        .context("Failed to connect to PostgreSQL")?;

    info!("Connected to PostgreSQL");

    // Initialize Elasticsearch client
    let es = ElasticsearchSync::new(&elasticsearch_url);

    // Ensure index exists
    info!("Ensuring Elasticsearch index exists...");
    es.ensure_index().await?;

    // Get total user count
    let total_users = get_user_count(&pool).await?;
    info!(total_users = total_users, "Found users to sync");

    if total_users == 0 {
        info!("No users to sync. Exiting.");
        return Ok(());
    }

    // Sync users in batches
    let mut offset = 0i64;
    let mut total_synced = 0usize;
    let mut total_failed = 0usize;

    loop {
        let users = fetch_users(&pool, offset, batch_size).await?;

        if users.is_empty() {
            break;
        }

        let batch_count = users.len();
        let docs: Vec<UserDocument> = users.iter().map(to_es_document).collect();

        match es.bulk_index(&docs).await {
            Ok((success, failure)) => {
                total_synced += success;
                total_failed += failure;

                info!(
                    batch = offset / batch_size + 1,
                    batch_success = success,
                    batch_failure = failure,
                    total_synced = total_synced,
                    total_failed = total_failed,
                    progress = format!("{}/{}", offset + batch_count as i64, total_users),
                    "Batch synced"
                );
            }
            Err(e) => {
                error!(
                    batch = offset / batch_size + 1,
                    error = %e,
                    "Batch failed, attempting individual indexing"
                );

                // Fall back to individual indexing
                for doc in &docs {
                    match es.index_user(doc).await {
                        Ok(()) => total_synced += 1,
                        Err(e) => {
                            error!(user_id = %doc.user_id, error = %e, "Failed to index user");
                            total_failed += 1;
                        }
                    }
                }
            }
        }

        offset += batch_count as i64;

        // Add delay between batches to avoid overwhelming Elasticsearch
        if delay_ms > 0 && offset < total_users {
            tokio::time::sleep(Duration::from_millis(delay_ms)).await;
        }
    }

    // Summary
    info!(
        total_synced = total_synced,
        total_failed = total_failed,
        "User sync completed"
    );

    if total_failed > 0 {
        warn!("{} users failed to sync", total_failed);
    }

    Ok(())
}
