use crate::error::Result;
use crate::models::EmailVerification;
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

pub async fn create_email_verification(
    pool: &PgPool,
    user_id: Uuid,
    email: &str,
    token_hash: &str,
    expires_at: DateTime<Utc>,
) -> Result<EmailVerification> {
    let verification = sqlx::query_as::<_, EmailVerification>(
        r#"
        INSERT INTO email_verifications (id, user_id, email, token_hash, expires_at, is_used, created_at)
        VALUES (gen_random_uuid(), $1, $2, $3, $4, false, CURRENT_TIMESTAMP)
        RETURNING *
        "#,
    )
    .bind(user_id)
    .bind(email)
    .bind(token_hash)
    .bind(expires_at)
    .fetch_one(pool)
    .await?;

    Ok(verification)
}

pub async fn get_email_verification(
    pool: &PgPool,
    token_hash: &str,
) -> Result<EmailVerification> {
    let verification = sqlx::query_as::<_, EmailVerification>(
        r#"
        SELECT * FROM email_verifications WHERE token_hash = $1 AND is_used = false AND expires_at > CURRENT_TIMESTAMP
        "#,
    )
    .bind(token_hash)
    .fetch_one(pool)
    .await?;

    Ok(verification)
}

pub async fn mark_email_verified(pool: &PgPool, verification_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE email_verifications SET is_used = true, used_at = CURRENT_TIMESTAMP WHERE id = $1
        "#,
    )
    .bind(verification_id)
    .execute(pool)
    .await?;

    Ok(())
}
