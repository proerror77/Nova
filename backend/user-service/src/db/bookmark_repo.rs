use crate::models::Bookmark;
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// Create a new bookmark
pub async fn create_bookmark(
    pool: &PgPool,
    user_id: Uuid,
    post_id: Uuid,
) -> Result<Bookmark, sqlx::Error> {
    let bookmark = sqlx::query_as::<_, Bookmark>(
        r#"
        INSERT INTO bookmarks (id, user_id, post_id, bookmarked_at)
        VALUES (gen_random_uuid(), $1, $2, CURRENT_TIMESTAMP)
        ON CONFLICT (user_id, post_id) DO NOTHING
        RETURNING id, user_id, post_id, bookmarked_at
        "#,
    )
    .bind(user_id)
    .bind(post_id)
    .fetch_optional(pool)
    .await?;

    match bookmark {
        Some(b) => Ok(b),
        None => {
            // Already bookmarked, return error
            Err(sqlx::Error::RowNotFound)
        }
    }
}

/// Delete a bookmark
pub async fn delete_bookmark(
    pool: &PgPool,
    user_id: Uuid,
    post_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        DELETE FROM bookmarks
        WHERE user_id = $1 AND post_id = $2
        "#,
    )
    .bind(user_id)
    .bind(post_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Check if a user has bookmarked a post
pub async fn has_bookmarked(
    pool: &PgPool,
    user_id: Uuid,
    post_id: Uuid,
) -> Result<bool, sqlx::Error> {
    let row =
        sqlx::query("SELECT EXISTS(SELECT 1 FROM bookmarks WHERE user_id = $1 AND post_id = $2)")
            .bind(user_id)
            .bind(post_id)
            .fetch_one(pool)
            .await?;

    Ok(row.get::<bool, _>(0))
}

/// Get user's bookmarks with pagination
pub async fn get_user_bookmarks(
    pool: &PgPool,
    user_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<Bookmark>, sqlx::Error> {
    let bookmarks = sqlx::query_as::<_, Bookmark>(
        r#"
        SELECT id, user_id, post_id, bookmarked_at
        FROM bookmarks
        WHERE user_id = $1
        ORDER BY bookmarked_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(user_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(bookmarks)
}

/// Count user's total bookmarks
pub async fn count_user_bookmarks(pool: &PgPool, user_id: Uuid) -> Result<i64, sqlx::Error> {
    let row = sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM bookmarks WHERE user_id = $1")
        .bind(user_id)
        .fetch_one(pool)
        .await?;

    Ok(row)
}
