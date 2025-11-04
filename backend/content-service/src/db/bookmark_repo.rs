use crate::models::Bookmark;
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// Create a new bookmark on a post
/// Returns the created bookmark, or an error if already bookmarked
pub async fn create_bookmark(
    pool: &PgPool,
    user_id: Uuid,
    post_id: Uuid,
) -> Result<Bookmark, sqlx::Error> {
    let bookmark = sqlx::query_as::<_, Bookmark>(
        r#"
        INSERT INTO bookmarks (user_id, post_id)
        VALUES ($1, $2)
        RETURNING id, user_id, post_id, bookmarked_at
        "#,
    )
    .bind(user_id)
    .bind(post_id)
    .fetch_one(pool)
    .await?;

    Ok(bookmark)
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
pub async fn find_bookmark(
    pool: &PgPool,
    user_id: Uuid,
    post_id: Uuid,
) -> Result<Option<Bookmark>, sqlx::Error> {
    let bookmark = sqlx::query_as::<_, Bookmark>(
        r#"
        SELECT id, user_id, post_id, bookmarked_at
        FROM bookmarks
        WHERE user_id = $1 AND post_id = $2
        "#,
    )
    .bind(user_id)
    .bind(post_id)
    .fetch_optional(pool)
    .await?;

    Ok(bookmark)
}

/// Get all bookmarks for a user
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

/// Count total bookmarks for a user
pub async fn count_user_bookmarks(pool: &PgPool, user_id: Uuid) -> Result<i64, sqlx::Error> {
    let row = sqlx::query("SELECT COUNT(*) as count FROM bookmarks WHERE user_id = $1")
        .bind(user_id)
        .fetch_one(pool)
        .await?;

    Ok(row.get::<i64, _>("count"))
}

/// Get count of bookmarks for a post
pub async fn count_post_bookmarks(pool: &PgPool, post_id: Uuid) -> Result<i64, sqlx::Error> {
    let row = sqlx::query("SELECT COUNT(*) as count FROM bookmarks WHERE post_id = $1")
        .bind(post_id)
        .fetch_one(pool)
        .await?;

    Ok(row.get::<i64, _>("count"))
}

/// Get all users who bookmarked a post
pub async fn get_post_bookmarkers(
    pool: &PgPool,
    post_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<Bookmark>, sqlx::Error> {
    let bookmarks = sqlx::query_as::<_, Bookmark>(
        r#"
        SELECT id, user_id, post_id, bookmarked_at
        FROM bookmarks
        WHERE post_id = $1
        ORDER BY bookmarked_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(post_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(bookmarks)
}

/// Get bookmark count for multiple posts
pub async fn count_bookmarks_batch(
    pool: &PgPool,
    post_ids: &[Uuid],
) -> Result<Vec<(Uuid, i64)>, sqlx::Error> {
    let rows = sqlx::query(
        r#"
        SELECT post_id, COUNT(*) as count
        FROM bookmarks
        WHERE post_id = ANY($1)
        GROUP BY post_id
        "#,
    )
    .bind(post_ids)
    .fetch_all(pool)
    .await?;

    let counts: Vec<(Uuid, i64)> = rows
        .into_iter()
        .map(|row| {
            let post_id: Uuid = row.get("post_id");
            let count: i64 = row.get("count");
            (post_id, count)
        })
        .collect();

    Ok(counts)
}
