use crate::models::Comment;
use sqlx::{PgPool, Row};
use uuid::Uuid;

/// Create a new comment on a post
pub async fn create_comment(
    pool: &PgPool,
    post_id: Uuid,
    user_id: Uuid,
    content: &str,
    parent_comment_id: Option<Uuid>,
) -> Result<Comment, sqlx::Error> {
    let comment = sqlx::query_as::<_, Comment>(
        r#"
        INSERT INTO comments (post_id, user_id, content, parent_comment_id)
        VALUES ($1, $2, $3, $4)
        RETURNING id, post_id, user_id, content, parent_comment_id, created_at, updated_at, soft_delete
        "#,
    )
    .bind(post_id)
    .bind(user_id)
    .bind(content)
    .bind(parent_comment_id)
    .fetch_one(pool)
    .await?;

    Ok(comment)
}

/// Get all comments for a post (excluding soft-deleted)
pub async fn get_comments_by_post(
    pool: &PgPool,
    post_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<Comment>, sqlx::Error> {
    let comments = sqlx::query_as::<_, Comment>(
        r#"
        SELECT id, post_id, user_id, content, parent_comment_id, created_at, updated_at, soft_delete
        FROM comments
        WHERE post_id = $1 AND soft_delete IS NULL
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(post_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(comments)
}

/// Get a single comment by ID
pub async fn get_comment_by_id(
    pool: &PgPool,
    comment_id: Uuid,
) -> Result<Option<Comment>, sqlx::Error> {
    let comment = sqlx::query_as::<_, Comment>(
        r#"
        SELECT id, post_id, user_id, content, parent_comment_id, created_at, updated_at, soft_delete
        FROM comments
        WHERE id = $1 AND soft_delete IS NULL
        "#,
    )
    .bind(comment_id)
    .fetch_optional(pool)
    .await?;

    Ok(comment)
}

/// Update comment content
pub async fn update_comment(
    pool: &PgPool,
    comment_id: Uuid,
    content: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE comments
        SET content = $1, updated_at = NOW()
        WHERE id = $2
        "#,
    )
    .bind(content)
    .bind(comment_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Soft delete a comment
pub async fn soft_delete_comment(pool: &PgPool, comment_id: Uuid) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE comments
        SET soft_delete = NOW()
        WHERE id = $1
        "#,
    )
    .bind(comment_id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Count comments for a post
pub async fn count_comments_by_post(pool: &PgPool, post_id: Uuid) -> Result<i32, sqlx::Error> {
    let row = sqlx::query(
        "SELECT COUNT(*) as count FROM comments WHERE post_id = $1 AND soft_delete IS NULL",
    )
    .bind(post_id)
    .fetch_one(pool)
    .await?;

    Ok(row.get::<i32, _>("count"))
}

/// Get replies to a comment
pub async fn get_comment_replies(
    pool: &PgPool,
    parent_comment_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<Vec<Comment>, sqlx::Error> {
    let comments = sqlx::query_as::<_, Comment>(
        r#"
        SELECT id, post_id, user_id, content, parent_comment_id, created_at, updated_at, soft_delete
        FROM comments
        WHERE parent_comment_id = $1 AND soft_delete IS NULL
        ORDER BY created_at ASC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(parent_comment_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(comments)
}
