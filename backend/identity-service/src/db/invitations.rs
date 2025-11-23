use crate::error::{IdentityError, Result};
use chrono::{DateTime, Duration, Utc};
use rand::distributions::Alphanumeric;
use rand::{thread_rng, Rng};
use sqlx::PgPool;
use uuid::Uuid;

#[derive(Debug, Clone, sqlx::FromRow)]
pub struct InviteCode {
    pub id: Uuid,
    pub code: String,
    pub issuer_user_id: Uuid,
    pub target_email: Option<String>,
    pub target_phone: Option<String>,
    pub expires_at: DateTime<Utc>,
    pub redeemed_by: Option<Uuid>,
    pub redeemed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

fn generate_code() -> String {
    let mut rng = thread_rng();
    std::iter::repeat_with(|| rng.sample(Alphanumeric))
        .map(char::from)
        .filter(|c| c.is_ascii_alphanumeric())
        .take(10)
        .collect::<String>()
        .to_uppercase()
}

pub async fn create_invite(
    pool: &PgPool,
    issuer: Uuid,
    target_email: Option<String>,
    target_phone: Option<String>,
    expires_at: Option<DateTime<Utc>>,
) -> Result<InviteCode> {
    // default expiry 7 days
    let expiry = expires_at.unwrap_or_else(|| Utc::now() + Duration::days(7));
    let mut attempts = 0;
    loop {
        let code = generate_code();
        attempts += 1;
        let res = sqlx::query_as::<_, InviteCode>(
            r#"
            INSERT INTO invite_codes (code, issuer_user_id, target_email, target_phone, expires_at)
            VALUES ($1, $2, $3, $4, $5)
            ON CONFLICT (code) DO NOTHING
            RETURNING id, code, issuer_user_id, target_email, target_phone, expires_at, redeemed_by, redeemed_at, created_at
            "#,
        )
        .bind(&code)
        .bind(issuer)
        .bind(target_email.clone())
        .bind(target_phone.clone())
        .bind(expiry)
        .fetch_optional(pool)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?;

        if let Some(invite) = res {
            return Ok(invite);
        }

        if attempts > 3 {
            return Err(IdentityError::Internal(
                "Failed to generate invite code".into(),
            ));
        }
    }
}

pub async fn redeem_invite(pool: &PgPool, code: &str, new_user_id: Uuid) -> Result<bool> {
    let now = Utc::now();
    let updated = sqlx::query(
        r#"
        UPDATE invite_codes
        SET redeemed_by = $2,
            redeemed_at = $3
        WHERE code = $1
          AND redeemed_at IS NULL
          AND expires_at > $3
        "#,
    )
    .bind(code)
    .bind(new_user_id)
    .bind(now)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(updated.rows_affected() > 0)
}

pub async fn get_invite(pool: &PgPool, code: &str) -> Result<Option<InviteCode>> {
    let invite = sqlx::query_as::<_, InviteCode>(
        "SELECT id, code, issuer_user_id, target_email, target_phone, expires_at, redeemed_by, redeemed_at, created_at FROM invite_codes WHERE code = $1",
    )
    .bind(code)
    .fetch_optional(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(invite)
}

/// List invitations created by a user
pub async fn list_user_invitations(
    pool: &PgPool,
    user_id: Uuid,
    limit: i64,
    offset: i64,
) -> Result<(Vec<InviteCode>, i64)> {
    let invites = sqlx::query_as::<_, InviteCode>(
        r#"
        SELECT id, code, issuer_user_id, target_email, target_phone,
               expires_at, redeemed_by, redeemed_at, created_at
        FROM invite_codes
        WHERE issuer_user_id = $1
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(user_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    let total = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM invite_codes WHERE issuer_user_id = $1",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok((invites, total))
}

/// Get invitation statistics for a user
pub async fn get_invitation_stats(pool: &PgPool, user_id: Uuid) -> Result<InvitationStats> {
    let stats = sqlx::query_as::<_, InvitationStatsRow>(
        r#"
        SELECT
            COUNT(*) as total_generated,
            COUNT(CASE WHEN redeemed_at IS NOT NULL THEN 1 END) as total_redeemed,
            COUNT(CASE WHEN redeemed_at IS NULL AND expires_at > NOW() THEN 1 END) as total_pending,
            COUNT(CASE WHEN redeemed_at IS NULL AND expires_at <= NOW() THEN 1 END) as total_expired
        FROM invite_codes
        WHERE issuer_user_id = $1
        "#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(InvitationStats {
        total_generated: stats.total_generated as i32,
        total_redeemed: stats.total_redeemed as i32,
        total_pending: stats.total_pending as i32,
        total_expired: stats.total_expired as i32,
    })
}

#[derive(Debug, sqlx::FromRow)]
struct InvitationStatsRow {
    total_generated: i64,
    total_redeemed: i64,
    total_pending: i64,
    total_expired: i64,
}

pub struct InvitationStats {
    pub total_generated: i32,
    pub total_redeemed: i32,
    pub total_pending: i32,
    pub total_expired: i32,
}
