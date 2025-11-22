use crate::error::{IdentityError, Result};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn list_user_channels(pool: &PgPool, user_id: Uuid) -> Result<Vec<String>> {
    let channels = sqlx::query_scalar::<_, String>(
        "SELECT channel_id FROM user_channels WHERE user_id = $1 ORDER BY subscribed_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(channels)
}

pub async fn update_user_channels(
    pool: &PgPool,
    user_id: Uuid,
    subscribe_ids: &[String],
    unsubscribe_ids: &[String],
) -> Result<Vec<String>> {
    let mut tx = pool
        .begin()
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?;

    if !subscribe_ids.is_empty() {
        sqlx::query(
            r#"
            INSERT INTO user_channels (user_id, channel_id)
            SELECT $1, unnest($2::text[])
            ON CONFLICT (user_id, channel_id) DO NOTHING
            "#,
        )
        .bind(user_id)
        .bind(subscribe_ids)
        .execute(&mut *tx)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?;
    }

    if !unsubscribe_ids.is_empty() {
        sqlx::query(
            r#"
            DELETE FROM user_channels
            WHERE user_id = $1 AND channel_id = ANY($2::text[])
            "#,
        )
        .bind(user_id)
        .bind(unsubscribe_ids)
        .execute(&mut *tx)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?;
    }

    let channels = sqlx::query_scalar::<_, String>(
        "SELECT channel_id FROM user_channels WHERE user_id = $1 ORDER BY subscribed_at DESC",
    )
    .bind(user_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    tx.commit()
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(channels)
}
