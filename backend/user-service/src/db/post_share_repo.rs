use crate::models::PostShare;
use sqlx::PgPool;
use uuid::Uuid;

/// Create a new post share
pub async fn create_share(
    pool: &PgPool,
    post_id: Uuid,
    user_id: Uuid,
    share_via: Option<String>,
    shared_with_user_id: Option<Uuid>,
) -> Result<PostShare, sqlx::Error> {
    let share = sqlx::query_as::<_, PostShare>(
        r#"
        INSERT INTO post_shares (id, post_id, user_id, share_via, shared_with_user_id, shared_at)
        VALUES (uuid_generate_v4(), $1, $2, $3, $4, CURRENT_TIMESTAMP)
        RETURNING id, post_id, user_id, share_via, shared_with_user_id, shared_at
        "#,
    )
    .bind(post_id)
    .bind(user_id)
    .bind(&share_via)
    .bind(shared_with_user_id)
    .fetch_one(pool)
    .await?;

    Ok(share)
}

/// Delete a post share
pub async fn delete_share(pool: &PgPool, share_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        DELETE FROM post_shares
        WHERE id = $1
        "#,
    )
    .bind(share_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Get all shares for a post
pub async fn get_post_shares(
    pool: &PgPool,
    post_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<PostShare>, sqlx::Error> {
    let shares = sqlx::query_as::<_, PostShare>(
        r#"
        SELECT id, post_id, user_id, share_via, shared_with_user_id, shared_at
        FROM post_shares
        WHERE post_id = $1
        ORDER BY shared_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(post_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(shares)
}

/// Count shares for a post
pub async fn count_post_shares(pool: &PgPool, post_id: Uuid) -> Result<i64, sqlx::Error> {
    let row = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM post_shares WHERE post_id = $1")
        .bind(post_id)
        .fetch_one(pool)
        .await?;

    Ok(row)
}

/// Get user's shares with pagination
pub async fn get_user_shares(
    pool: &PgPool,
    user_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<PostShare>, sqlx::Error> {
    let shares = sqlx::query_as::<_, PostShare>(
        r#"
        SELECT id, post_id, user_id, share_via, shared_with_user_id, shared_at
        FROM post_shares
        WHERE user_id = $1
        ORDER BY shared_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(user_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(shares)
}

/// Count user's total shares
pub async fn count_user_shares(pool: &PgPool, user_id: Uuid) -> Result<i64, sqlx::Error> {
    let row = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM post_shares WHERE user_id = $1")
        .bind(user_id)
        .fetch_one(pool)
        .await?;

    Ok(row)
}
