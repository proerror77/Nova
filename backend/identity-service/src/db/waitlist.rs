use crate::error::{IdentityError, Result};
use chrono::{DateTime, Utc};
use sqlx::PgPool;
use uuid::Uuid;

/// Waitlist email entry
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct WaitlistEmail {
    pub id: Uuid,
    pub email: String,
    pub ip_address: Option<std::net::IpAddr>,
    pub user_agent: Option<String>,
    pub source: String,
    pub status: String,
    pub invited_at: Option<DateTime<Utc>>,
    pub invite_code_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Waitlist entry for API response (without sensitive fields)
#[derive(Debug, Clone)]
pub struct WaitlistEntry {
    pub id: Uuid,
    pub email: String,
    pub status: String,
    pub source: String,
    pub created_at: DateTime<Utc>,
    pub invited_at: Option<DateTime<Utc>>,
}

/// Waitlist statistics
#[derive(Debug, Clone)]
pub struct WaitlistStats {
    pub total: i64,
    pub pending: i64,
    pub invited: i64,
    pub registered: i64,
}

/// Add email to waitlist
/// Returns Ok(true) if newly added, Ok(false) if already exists
pub async fn add_to_waitlist(
    pool: &PgPool,
    email: &str,
    ip_address: Option<&str>,
    user_agent: Option<&str>,
    source: Option<&str>,
) -> Result<(bool, Uuid)> {
    let email_lower = email.to_lowercase().trim().to_string();
    let source = source.unwrap_or("invite_page");

    // Check if email already exists
    let existing: Option<(Uuid,)> =
        sqlx::query_as("SELECT id FROM waitlist_emails WHERE email = $1")
            .bind(&email_lower)
            .fetch_optional(pool)
            .await
            .map_err(|e| IdentityError::Database(e.to_string()))?;

    if let Some((id,)) = existing {
        return Ok((false, id));
    }

    // Insert new entry
    let id = Uuid::new_v4();

    sqlx::query(
        r#"
        INSERT INTO waitlist_emails (id, email, ip_address, user_agent, source, status)
        VALUES ($1, $2, $3::inet, $4, $5, 'pending')
        "#,
    )
    .bind(id)
    .bind(&email_lower)
    .bind(ip_address)
    .bind(user_agent)
    .bind(source)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    tracing::info!(email = %email_lower, source = %source, "New waitlist signup");

    Ok((true, id))
}

/// Get waitlist entries for admin panel
pub async fn list_waitlist(
    pool: &PgPool,
    status: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<(Vec<WaitlistEntry>, i64)> {
    let (entries, total): (Vec<WaitlistEntry>, i64) = if let Some(status) = status {
        let entries = sqlx::query_as::<
            _,
            (
                Uuid,
                String,
                String,
                String,
                DateTime<Utc>,
                Option<DateTime<Utc>>,
            ),
        >(
            r#"
            SELECT id, email, status, source, created_at, invited_at
            FROM waitlist_emails
            WHERE status = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(status)
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?
        .into_iter()
        .map(
            |(id, email, status, source, created_at, invited_at)| WaitlistEntry {
                id,
                email,
                status,
                source,
                created_at,
                invited_at,
            },
        )
        .collect();

        let total: (i64,) =
            sqlx::query_as("SELECT COUNT(*) FROM waitlist_emails WHERE status = $1")
                .bind(status)
                .fetch_one(pool)
                .await
                .map_err(|e| IdentityError::Database(e.to_string()))?;

        (entries, total.0)
    } else {
        let entries = sqlx::query_as::<
            _,
            (
                Uuid,
                String,
                String,
                String,
                DateTime<Utc>,
                Option<DateTime<Utc>>,
            ),
        >(
            r#"
            SELECT id, email, status, source, created_at, invited_at
            FROM waitlist_emails
            ORDER BY created_at DESC
            LIMIT $1 OFFSET $2
            "#,
        )
        .bind(limit)
        .bind(offset)
        .fetch_all(pool)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?
        .into_iter()
        .map(
            |(id, email, status, source, created_at, invited_at)| WaitlistEntry {
                id,
                email,
                status,
                source,
                created_at,
                invited_at,
            },
        )
        .collect();

        let total: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM waitlist_emails")
            .fetch_one(pool)
            .await
            .map_err(|e| IdentityError::Database(e.to_string()))?;

        (entries, total.0)
    };

    Ok((entries, total))
}

/// Get waitlist statistics
pub async fn get_waitlist_stats(pool: &PgPool) -> Result<WaitlistStats> {
    let stats = sqlx::query_as::<_, (i64, i64, i64, i64)>(
        r#"
        SELECT
            COUNT(*) as total,
            COUNT(*) FILTER (WHERE status = 'pending') as pending,
            COUNT(*) FILTER (WHERE status = 'invited') as invited,
            COUNT(*) FILTER (WHERE status = 'registered') as registered
        FROM waitlist_emails
        "#,
    )
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(WaitlistStats {
        total: stats.0,
        pending: stats.1,
        invited: stats.2,
        registered: stats.3,
    })
}

/// Update waitlist entry status (for admin panel)
pub async fn update_waitlist_status(
    pool: &PgPool,
    id: Uuid,
    status: &str,
    invite_code_id: Option<Uuid>,
) -> Result<bool> {
    let result = sqlx::query(
        r#"
        UPDATE waitlist_emails
        SET status = $2,
            updated_at = NOW(),
            invited_at = CASE WHEN $2 = 'invited' THEN NOW() ELSE invited_at END,
            invite_code_id = COALESCE($3, invite_code_id)
        WHERE id = $1
        "#,
    )
    .bind(id)
    .bind(status)
    .bind(invite_code_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(result.rows_affected() > 0)
}

/// Check if email is in waitlist
pub async fn is_email_in_waitlist(pool: &PgPool, email: &str) -> Result<bool> {
    let email_lower = email.to_lowercase().trim().to_string();

    let exists: (bool,) =
        sqlx::query_as("SELECT EXISTS(SELECT 1 FROM waitlist_emails WHERE email = $1)")
            .bind(&email_lower)
            .fetch_one(pool)
            .await
            .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(exists.0)
}

/// Delete waitlist entry (for admin panel)
pub async fn delete_waitlist_entry(pool: &PgPool, id: Uuid) -> Result<bool> {
    let result = sqlx::query("DELETE FROM waitlist_emails WHERE id = $1")
        .bind(id)
        .execute(pool)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(result.rows_affected() > 0)
}
