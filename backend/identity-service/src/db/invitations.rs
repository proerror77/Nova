use crate::error::{IdentityError, Result};
use chrono::{DateTime, Duration, Utc};
use rand::distributions::Alphanumeric;
use rand::Rng;
use sqlx::PgPool;
use uuid::Uuid;

/// Default invite code expiry: 30 days
const DEFAULT_INVITE_EXPIRY_DAYS: i64 = 30;

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
    #[sqlx(default)]
    pub reusable: bool,
}

/// Invite quota information
#[derive(Debug, Clone)]
pub struct InviteQuota {
    pub total_quota: i32,
    pub used_quota: i32,
    pub remaining_quota: i32,
    pub successful_referrals: i32,
}

/// Invite validation result
#[derive(Debug, Clone)]
pub struct InviteValidation {
    pub is_valid: bool,
    pub issuer_username: Option<String>,
    pub expires_at: Option<DateTime<Utc>>,
    pub error: Option<String>,
}

/// Referral user info
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct ReferralUser {
    pub user_id: Uuid,
    pub username: String,
    pub avatar_url: Option<String>,
    pub joined_at: DateTime<Utc>,
    pub status: String,
}

/// Referral info response
#[derive(Debug, Clone)]
pub struct ReferralInfo {
    pub referred_by: Option<ReferralUser>,
    pub referrals: Vec<ReferralUser>,
    pub total_referrals: i32,
    pub active_referrals: i32,
}

/// Invite delivery record
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct InviteDelivery {
    pub id: Uuid,
    pub invite_code_id: Uuid,
    pub channel: String,
    pub recipient: Option<String>,
    pub external_id: Option<String>,
    pub status: String,
    pub sent_at: DateTime<Utc>,
}

fn generate_code() -> String {
    let mut rng = rand::rng();
    std::iter::repeat_with(|| rng.sample(Alphanumeric))
        .map(char::from)
        .filter(|c| c.is_ascii_alphanumeric())
        .take(10)
        .collect::<String>()
        .to_uppercase()
}

/// Check user's invite quota
pub async fn get_invite_quota(pool: &PgPool, user_id: Uuid) -> Result<InviteQuota> {
    #[derive(sqlx::FromRow)]
    struct QuotaRow {
        invite_quota: i32,
        total_successful_referrals: i32,
    }

    let user = sqlx::query_as::<_, QuotaRow>(
        "SELECT invite_quota, total_successful_referrals FROM users WHERE id = $1",
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?
    .ok_or_else(|| IdentityError::UserNotFound)?;

    let used =
        sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM invite_codes WHERE issuer_user_id = $1")
            .bind(user_id)
            .fetch_one(pool)
            .await
            .map_err(|e| IdentityError::Database(e.to_string()))? as i32;

    Ok(InviteQuota {
        total_quota: user.invite_quota,
        used_quota: used,
        remaining_quota: (user.invite_quota - used).max(0),
        successful_referrals: user.total_successful_referrals,
    })
}

/// Check if user can create more invites
pub async fn can_create_invite(pool: &PgPool, user_id: Uuid) -> Result<bool> {
    let quota = get_invite_quota(pool, user_id).await?;
    Ok(quota.remaining_quota > 0)
}

pub async fn create_invite(
    pool: &PgPool,
    issuer: Uuid,
    target_email: Option<String>,
    target_phone: Option<String>,
    expires_at: Option<DateTime<Utc>>,
) -> Result<InviteCode> {
    // Check quota first
    if !can_create_invite(pool, issuer).await? {
        return Err(IdentityError::Validation(
            "No remaining invite quota. Refer more friends to earn more invites.".into(),
        ));
    }

    // Default expiry: 30 days
    let expiry =
        expires_at.unwrap_or_else(|| Utc::now() + Duration::days(DEFAULT_INVITE_EXPIRY_DAYS));
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

    // Check if this is a reusable invite code (e.g., NOVATEST)
    // Reusable codes can be used unlimited times and don't get marked as redeemed
    let reusable_check = sqlx::query_scalar::<_, bool>(
        r#"
        SELECT EXISTS(
            SELECT 1 FROM invite_codes
            WHERE code = $1
              AND reusable = TRUE
              AND expires_at > $2
        )
        "#,
    )
    .bind(code)
    .bind(now)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    if reusable_check {
        return Ok(true);
    }

    // Standard single-use invite code: mark as redeemed
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

    let total =
        sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM invite_codes WHERE issuer_user_id = $1")
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

/// Validate an invite code (public endpoint - no auth required)
pub async fn validate_invite(pool: &PgPool, code: &str) -> Result<InviteValidation> {
    #[derive(sqlx::FromRow)]
    struct InviteWithIssuer {
        expires_at: DateTime<Utc>,
        redeemed_at: Option<DateTime<Utc>>,
        reusable: bool,
        username: String,
    }

    let result = sqlx::query_as::<_, InviteWithIssuer>(
        r#"
        SELECT ic.expires_at, ic.redeemed_at, ic.reusable, u.username
        FROM invite_codes ic
        JOIN users u ON u.id = ic.issuer_user_id
        WHERE ic.code = $1
        "#,
    )
    .bind(code)
    .fetch_optional(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    match result {
        None => Ok(InviteValidation {
            is_valid: false,
            issuer_username: None,
            expires_at: None,
            error: Some("not_found".into()),
        }),
        Some(invite) => {
            // Reusable codes ignore the redeemed_at check
            if !invite.reusable && invite.redeemed_at.is_some() {
                Ok(InviteValidation {
                    is_valid: false,
                    issuer_username: Some(invite.username),
                    expires_at: Some(invite.expires_at),
                    error: Some("already_used".into()),
                })
            } else if invite.expires_at < Utc::now() {
                Ok(InviteValidation {
                    is_valid: false,
                    issuer_username: Some(invite.username),
                    expires_at: Some(invite.expires_at),
                    error: Some("expired".into()),
                })
            } else {
                Ok(InviteValidation {
                    is_valid: true,
                    issuer_username: Some(invite.username),
                    expires_at: Some(invite.expires_at),
                    error: None,
                })
            }
        }
    }
}

/// Get referral information for a user
pub async fn get_referral_info(pool: &PgPool, user_id: Uuid) -> Result<ReferralInfo> {
    // Get who referred this user
    let referred_by = sqlx::query_as::<_, ReferralUser>(
        r#"
        SELECT
            u.id as user_id,
            u.username,
            u.avatar_url,
            u.created_at as joined_at,
            COALESCE(rc.status, 'active') as status
        FROM users u
        LEFT JOIN referral_chains rc ON rc.referrer_id = u.id AND rc.referee_id = $1
        WHERE u.id = (SELECT referred_by_user_id FROM users WHERE id = $1)
        "#,
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    // Get users this user has referred
    let referrals = sqlx::query_as::<_, ReferralUser>(
        r#"
        SELECT
            u.id as user_id,
            u.username,
            u.avatar_url,
            u.created_at as joined_at,
            COALESCE(rc.status, 'pending') as status
        FROM users u
        JOIN referral_chains rc ON rc.referee_id = u.id
        WHERE rc.referrer_id = $1
        ORDER BY u.created_at DESC
        LIMIT 100
        "#,
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    let total_referrals = referrals.len() as i32;
    let active_referrals = referrals.iter().filter(|r| r.status == "active").count() as i32;

    Ok(ReferralInfo {
        referred_by,
        referrals,
        total_referrals,
        active_referrals,
    })
}

/// Record an invite delivery (SMS, Email, or Link share)
pub async fn record_invite_delivery(
    pool: &PgPool,
    invite_code_id: Uuid,
    channel: &str,
    recipient: Option<&str>,
    external_id: Option<&str>,
) -> Result<InviteDelivery> {
    let delivery = sqlx::query_as::<_, InviteDelivery>(
        r#"
        INSERT INTO invite_deliveries (invite_code_id, channel, recipient, external_id, status)
        VALUES ($1, $2, $3, $4, 'sent')
        RETURNING id, invite_code_id, channel, recipient, external_id, status, sent_at
        "#,
    )
    .bind(invite_code_id)
    .bind(channel)
    .bind(recipient)
    .bind(external_id)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(delivery)
}

/// Update delivery status
pub async fn update_delivery_status(
    pool: &PgPool,
    delivery_id: Uuid,
    status: &str,
    error_message: Option<&str>,
) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE invite_deliveries
        SET status = $2,
            error_message = $3,
            delivered_at = CASE WHEN $2 = 'delivered' THEN NOW() ELSE delivered_at END,
            opened_at = CASE WHEN $2 = 'opened' THEN NOW() ELSE opened_at END
        WHERE id = $1
        "#,
    )
    .bind(delivery_id)
    .bind(status)
    .bind(error_message)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(())
}

/// Grant referral reward when referee becomes active
pub async fn grant_referral_reward(pool: &PgPool, referee_id: Uuid) -> Result<bool> {
    // This calls the database function we created in the migration
    let result = sqlx::query("SELECT grant_referral_reward($1)")
        .bind(referee_id)
        .execute(pool)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(result.rows_affected() > 0)
}
