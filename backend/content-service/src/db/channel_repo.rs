use crate::error::AppError;
use crate::models::Channel;
use sqlx::PgPool;
use uuid::Uuid;

/// List channels with optional category and enabled_only filters
/// Results are ordered by display_order (ascending), then by subscriber_count (descending)
pub async fn list_channels(
    pool: &PgPool,
    category: Option<&str>,
    enabled_only: bool,
    limit: i64,
    offset: i64,
) -> Result<(Vec<Channel>, i64), AppError> {
    // Build dynamic WHERE clause
    let mut conditions = Vec::new();
    if category.is_some() {
        conditions.push("category = $1");
    }
    if enabled_only {
        conditions.push("(is_enabled IS NULL OR is_enabled = true)");
    }

    let where_clause = if conditions.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", conditions.join(" AND "))
    };

    let query = format!(
        r#"
        SELECT id, name, description, category, subscriber_count,
               slug, icon_url, display_order, is_enabled, created_at, updated_at
        FROM channels
        {}
        ORDER BY COALESCE(display_order, 100) ASC, subscriber_count DESC, created_at DESC
        LIMIT {} OFFSET {}
        "#,
        where_clause,
        limit,
        offset
    );

    let rows = if let Some(cat) = category {
        sqlx::query_as::<_, Channel>(&query)
            .bind(cat)
            .fetch_all(pool)
            .await
            .map_err(|e| AppError::DatabaseError(e.to_string()))?
    } else {
        sqlx::query_as::<_, Channel>(&query)
            .fetch_all(pool)
            .await
            .map_err(|e| AppError::DatabaseError(e.to_string()))?
    };

    // Count query
    let count_where = if conditions.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", conditions.join(" AND "))
    };
    let count_query = format!("SELECT COUNT(*) FROM channels {}", count_where);

    let total = if let Some(cat) = category {
        sqlx::query_scalar::<_, i64>(&count_query)
            .bind(cat)
            .fetch_one(pool)
            .await
            .map_err(|e| AppError::DatabaseError(e.to_string()))?
    } else {
        sqlx::query_scalar::<_, i64>(&count_query)
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
        SELECT id, name, description, category, subscriber_count,
               slug, icon_url, display_order, is_enabled, created_at, updated_at
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

/// Fetch a single channel by slug
pub async fn get_channel_by_slug(pool: &PgPool, slug: &str) -> Result<Option<Channel>, AppError> {
    let channel = sqlx::query_as::<_, Channel>(
        r#"
        SELECT id, name, description, category, subscriber_count,
               slug, icon_url, display_order, is_enabled, created_at, updated_at
        FROM channels
        WHERE slug = $1
        "#,
    )
    .bind(slug)
    .fetch_optional(pool)
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    Ok(channel)
}

/// List post IDs by channel with cursor-based pagination
/// Returns posts that are tagged with the given channel_id
/// Ordered by created_at DESC (newest first)
pub async fn list_posts_by_channel(
    pool: &PgPool,
    channel_id: Uuid,
    limit: i64,
    cursor_post_id: Option<Uuid>,
    cursor_created_at: Option<i64>,
) -> Result<(Vec<Uuid>, bool), AppError> {
    // Cursor-based pagination: fetch posts older than the cursor
    let post_ids = if let (Some(cursor_id), Some(cursor_ts)) = (cursor_post_id, cursor_created_at) {
        let cursor_time = chrono::DateTime::from_timestamp(cursor_ts, 0)
            .unwrap_or_else(|| chrono::Utc::now());

        sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT pc.post_id
            FROM post_channels pc
            INNER JOIN posts p ON p.id = pc.post_id
            WHERE pc.channel_id = $1
              AND p.status = 'published'
              AND p.deleted_at IS NULL
              AND (p.created_at, p.id) < ($2, $3)
            ORDER BY p.created_at DESC, p.id DESC
            LIMIT $4
            "#,
        )
        .bind(channel_id)
        .bind(cursor_time)
        .bind(cursor_id)
        .bind(limit + 1) // Fetch one extra to check has_more
        .fetch_all(pool)
        .await
        .map_err(|e| AppError::DatabaseError(e.to_string()))?
    } else {
        sqlx::query_scalar::<_, Uuid>(
            r#"
            SELECT pc.post_id
            FROM post_channels pc
            INNER JOIN posts p ON p.id = pc.post_id
            WHERE pc.channel_id = $1
              AND p.status = 'published'
              AND p.deleted_at IS NULL
            ORDER BY p.created_at DESC, p.id DESC
            LIMIT $2
            "#,
        )
        .bind(channel_id)
        .bind(limit + 1)
        .fetch_all(pool)
        .await
        .map_err(|e| AppError::DatabaseError(e.to_string()))?
    };

    // Check if there are more results
    let has_more = post_ids.len() > limit as usize;
    let result_ids = if has_more {
        post_ids.into_iter().take(limit as usize).collect()
    } else {
        post_ids
    };

    Ok((result_ids, has_more))
}

/// Resolve channel_id from either UUID or slug
/// Returns None if channel doesn't exist
pub async fn resolve_channel_id(pool: &PgPool, channel_id_or_slug: &str) -> Result<Option<Uuid>, AppError> {
    // Try parsing as UUID first
    if let Ok(uuid) = Uuid::parse_str(channel_id_or_slug) {
        // Verify the channel exists
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM channels WHERE id = $1)"
        )
        .bind(uuid)
        .fetch_one(pool)
        .await
        .map_err(|e| AppError::DatabaseError(e.to_string()))?;

        return Ok(if exists { Some(uuid) } else { None });
    }

    // Otherwise, try to find by slug
    let channel_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM channels WHERE slug = $1"
    )
    .bind(channel_id_or_slug)
    .fetch_optional(pool)
    .await
    .map_err(|e| AppError::DatabaseError(e.to_string()))?;

    Ok(channel_id)
}
