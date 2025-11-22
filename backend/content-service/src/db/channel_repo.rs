use crate::error::AppError;
use crate::models::Channel;
use sqlx::PgPool;
use uuid::Uuid;

/// List channels with optional category filter
pub async fn list_channels(
    pool: &PgPool,
    category: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<(Vec<Channel>, i64), AppError> {
    let rows = if let Some(cat) = category {
        sqlx::query_as::<_, Channel>(
            r#"
            SELECT id, name, description, category, subscriber_count, created_at, updated_at
            FROM channels
            WHERE category = $1
            ORDER BY subscriber_count DESC, created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(cat)
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await
        .map_err(|e| AppError::DatabaseError(e.to_string()))?
    } else {
        sqlx::query_as::<_, Channel>(
            r#"
            SELECT id, name, description, category, subscriber_count, created_at, updated_at
            FROM channels
            ORDER BY subscriber_count DESC, created_at DESC
            LIMIT $1 OFFSET $2
            "#,
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await
        .map_err(|e| AppError::DatabaseError(e.to_string()))?
    };

    let total = if let Some(cat) = category {
        sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM channels WHERE category = $1")
            .bind(cat)
            .fetch_one(pool)
            .await
            .map_err(|e| AppError::DatabaseError(e.to_string()))?
    } else {
        sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM channels")
            .fetch_one(pool)
            .await
            .map_err(|e| AppError::DatabaseError(e.to_string()))?
    };

    Ok((rows, total))
}

/// Fetch a single channel by id
pub async fn get_channel(pool: &PgPool, id: Uuid) -> Result<Option<Channel>, AppError> {
    let channel = sqlx::query_as::<_, Channel>(
        r#"
        SELECT id, name, description, category, subscriber_count, created_at, updated_at
        FROM channels
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    Ok(channel)
}
