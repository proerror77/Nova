use crate::error::AppError;
use actix_web::{web, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

/// User preferences for feed personalization
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct UserFeedPreferences {
    pub user_id: Uuid,
    /// Whether to show content from muted keywords
    pub show_muted_keywords: bool,
    /// Whether to show content from blocked users
    pub show_blocked_users: bool,
    /// Preferred content language (e.g., "en", "zh", "all")
    pub preferred_language: String,
    /// Age range filter (e.g., "all", "18+", "21+")
    pub age_filter: String,
    /// Content safety filter level (0=off, 1=moderate, 2=strict)
    pub safety_filter_level: i32,
    /// Whether to enable ads
    pub enable_ads: bool,
    /// Topics/hashtags to prioritize (JSON array)
    pub prioritized_topics: Option<String>,
    /// Topics/hashtags to hide (JSON array)
    pub muted_topics: Option<String>,
    /// User IDs to block (JSON array)
    pub blocked_user_ids: Option<String>,
    /// Keywords to mute (JSON array)
    pub muted_keywords: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateFeedPreferencesRequest {
    pub show_muted_keywords: Option<bool>,
    pub show_blocked_users: Option<bool>,
    pub preferred_language: Option<String>,
    pub age_filter: Option<String>,
    pub safety_filter_level: Option<i32>,
    pub enable_ads: Option<bool>,
    pub prioritized_topics: Option<Vec<String>>,
    pub muted_topics: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
pub struct PreferencesResponse {
    pub preferences: UserFeedPreferences,
}

/// Get current user's feed preferences
pub async fn get_feed_preferences(
    req: HttpRequest,
    pool: web::Data<PgPool>,
) -> Result<HttpResponse, AppError> {
    // Extract user ID from JWT token
    let user_id = extract_user_id(&req)?;

    // Try to get existing preferences
    let prefs = sqlx::query_as::<_, UserFeedPreferences>(
        "SELECT * FROM user_feed_preferences WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_optional(pool.get_ref())
    .await?;

    match prefs {
        Some(prefs) => Ok(HttpResponse::Ok().json(PreferencesResponse { preferences: prefs })),
        None => {
            // Return default preferences if none exist
            let default_prefs = UserFeedPreferences {
                user_id,
                show_muted_keywords: false,
                show_blocked_users: false,
                preferred_language: "all".to_string(),
                age_filter: "all".to_string(),
                safety_filter_level: 1,
                enable_ads: true,
                prioritized_topics: None,
                muted_topics: None,
                blocked_user_ids: None,
                muted_keywords: None,
                created_at: chrono::Utc::now(),
                updated_at: chrono::Utc::now(),
            };

            Ok(HttpResponse::Ok().json(PreferencesResponse {
                preferences: default_prefs,
            }))
        }
    }
}

/// Update current user's feed preferences
pub async fn update_feed_preferences(
    req: HttpRequest,
    pool: web::Data<PgPool>,
    payload: web::Json<UpdateFeedPreferencesRequest>,
) -> Result<HttpResponse, AppError> {
    let user_id = extract_user_id(&req)?;

    // Validate inputs
    if let Some(level) = payload.safety_filter_level {
        if !(0..=2).contains(&level) {
            return Err(AppError::BadRequest(
                "safety_filter_level must be 0, 1, or 2".to_string(),
            ));
        }
    }

    // Get current preferences or create default
    let current = sqlx::query_as::<_, UserFeedPreferences>(
        "SELECT * FROM user_feed_preferences WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_optional(pool.get_ref())
    .await?;

    let now = chrono::Utc::now();
    let prioritized_topics = payload
        .prioritized_topics
        .as_ref()
        .map(|t| serde_json::to_string(t).unwrap_or_default());
    let muted_topics = payload
        .muted_topics
        .as_ref()
        .map(|t| serde_json::to_string(t).unwrap_or_default());

    if let Some(mut current) = current {
        // Update existing preferences
        if let Some(val) = payload.show_muted_keywords {
            current.show_muted_keywords = val;
        }
        if let Some(val) = payload.show_blocked_users {
            current.show_blocked_users = val;
        }
        if let Some(val) = &payload.preferred_language {
            current.preferred_language = val.clone();
        }
        if let Some(val) = &payload.age_filter {
            current.age_filter = val.clone();
        }
        if let Some(val) = payload.safety_filter_level {
            current.safety_filter_level = val;
        }
        if let Some(val) = payload.enable_ads {
            current.enable_ads = val;
        }
        if prioritized_topics.is_some() {
            current.prioritized_topics = prioritized_topics;
        }
        if muted_topics.is_some() {
            current.muted_topics = muted_topics;
        }
        current.updated_at = now;

        // Update in database
        sqlx::query(
            r#"
            UPDATE user_feed_preferences
            SET show_muted_keywords = $2,
                show_blocked_users = $3,
                preferred_language = $4,
                age_filter = $5,
                safety_filter_level = $6,
                enable_ads = $7,
                prioritized_topics = $8,
                muted_topics = $9,
                updated_at = $10
            WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .bind(current.show_muted_keywords)
        .bind(current.show_blocked_users)
        .bind(&current.preferred_language)
        .bind(&current.age_filter)
        .bind(current.safety_filter_level)
        .bind(current.enable_ads)
        .bind(&current.prioritized_topics)
        .bind(&current.muted_topics)
        .bind(now)
        .execute(pool.get_ref())
        .await?;

        Ok(HttpResponse::Ok().json(PreferencesResponse {
            preferences: current,
        }))
    } else {
        // Create new preferences
        let prefs = UserFeedPreferences {
            user_id,
            show_muted_keywords: payload.show_muted_keywords.unwrap_or(false),
            show_blocked_users: payload.show_blocked_users.unwrap_or(false),
            preferred_language: payload
                .preferred_language
                .clone()
                .unwrap_or_else(|| "all".to_string()),
            age_filter: payload
                .age_filter
                .clone()
                .unwrap_or_else(|| "all".to_string()),
            safety_filter_level: payload.safety_filter_level.unwrap_or(1),
            enable_ads: payload.enable_ads.unwrap_or(true),
            prioritized_topics,
            muted_topics,
            blocked_user_ids: None,
            muted_keywords: None,
            created_at: now,
            updated_at: now,
        };

        sqlx::query(
            r#"
            INSERT INTO user_feed_preferences
            (user_id, show_muted_keywords, show_blocked_users, preferred_language, age_filter,
             safety_filter_level, enable_ads, prioritized_topics, muted_topics, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            "#
        )
        .bind(prefs.user_id)
        .bind(prefs.show_muted_keywords)
        .bind(prefs.show_blocked_users)
        .bind(&prefs.preferred_language)
        .bind(&prefs.age_filter)
        .bind(prefs.safety_filter_level)
        .bind(prefs.enable_ads)
        .bind(&prefs.prioritized_topics)
        .bind(&prefs.muted_topics)
        .bind(prefs.created_at)
        .bind(prefs.updated_at)
        .execute(pool.get_ref())
        .await?;

        Ok(HttpResponse::Created().json(PreferencesResponse { preferences: prefs }))
    }
}

/// Add a user to the block list
pub async fn block_user(
    req: HttpRequest,
    pool: web::Data<PgPool>,
    blocked_user_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let user_id = extract_user_id(&req)?;
    let blocked_user_id = blocked_user_id.into_inner();

    if user_id == blocked_user_id {
        return Err(AppError::BadRequest("Cannot block yourself".to_string()));
    }

    // Get or create preferences
    let mut prefs = sqlx::query_as::<_, UserFeedPreferences>(
        "SELECT * FROM user_feed_preferences WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_optional(pool.get_ref())
    .await?
    .unwrap_or_else(|| UserFeedPreferences {
        user_id,
        show_muted_keywords: false,
        show_blocked_users: false,
        preferred_language: "all".to_string(),
        age_filter: "all".to_string(),
        safety_filter_level: 1,
        enable_ads: true,
        prioritized_topics: None,
        muted_topics: None,
        blocked_user_ids: None,
        muted_keywords: None,
        created_at: chrono::Utc::now(),
        updated_at: chrono::Utc::now(),
    });

    // Add to blocked users list
    let mut blocked: Vec<String> = prefs
        .blocked_user_ids
        .as_ref()
        .and_then(|b| serde_json::from_str(b).ok())
        .unwrap_or_default();

    let blocked_id_str = blocked_user_id.to_string();
    if !blocked.contains(&blocked_id_str) {
        blocked.push(blocked_id_str);
    }

    prefs.blocked_user_ids = Some(serde_json::to_string(&blocked)?);
    prefs.updated_at = chrono::Utc::now();

    // Update or insert
    sqlx::query(
        r#"
        INSERT INTO user_feed_preferences (user_id, blocked_user_ids, created_at, updated_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (user_id) DO UPDATE SET blocked_user_ids = $2, updated_at = $4
        "#,
    )
    .bind(prefs.user_id)
    .bind(&prefs.blocked_user_ids)
    .bind(prefs.created_at)
    .bind(prefs.updated_at)
    .execute(pool.get_ref())
    .await?;

    Ok(HttpResponse::Created().json(PreferencesResponse { preferences: prefs }))
}

/// Remove a user from the block list
pub async fn unblock_user(
    req: HttpRequest,
    pool: web::Data<PgPool>,
    blocked_user_id: web::Path<Uuid>,
) -> Result<HttpResponse, AppError> {
    let user_id = extract_user_id(&req)?;
    let blocked_id_str = blocked_user_id.into_inner().to_string();

    let mut prefs = sqlx::query_as::<_, UserFeedPreferences>(
        "SELECT * FROM user_feed_preferences WHERE user_id = $1",
    )
    .bind(user_id)
    .fetch_optional(pool.get_ref())
    .await?
    .ok_or_else(|| AppError::NotFound("Preferences not found".to_string()))?;

    // Remove from blocked users list
    let mut blocked: Vec<String> = prefs
        .blocked_user_ids
        .as_ref()
        .and_then(|b| serde_json::from_str(b).ok())
        .unwrap_or_default();

    blocked.retain(|id| id != &blocked_id_str);
    prefs.blocked_user_ids = if blocked.is_empty() {
        None
    } else {
        Some(serde_json::to_string(&blocked)?)
    };
    prefs.updated_at = chrono::Utc::now();

    sqlx::query(
        "UPDATE user_feed_preferences SET blocked_user_ids = $1, updated_at = $2 WHERE user_id = $3"
    )
    .bind(&prefs.blocked_user_ids)
    .bind(prefs.updated_at)
    .bind(user_id)
    .execute(pool.get_ref())
    .await?;

    Ok(HttpResponse::Ok().json(PreferencesResponse { preferences: prefs }))
}

/// Extract user ID from JWT token in request header
fn extract_user_id(req: &HttpRequest) -> Result<Uuid, AppError> {
    // This would typically extract from JWT token
    // For now, return a placeholder that would be implemented with proper JWT validation
    req.headers()
        .get("X-User-ID")
        .and_then(|h| h.to_str().ok())
        .and_then(|s| Uuid::parse_str(s).ok())
        .ok_or_else(|| AppError::Authentication("Missing or invalid X-User-ID header".to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preferences_creation() {
        let user_id = Uuid::new_v4();
        let prefs = UserFeedPreferences {
            user_id,
            show_muted_keywords: false,
            show_blocked_users: false,
            preferred_language: "en".to_string(),
            age_filter: "all".to_string(),
            safety_filter_level: 1,
            enable_ads: true,
            prioritized_topics: None,
            muted_topics: None,
            blocked_user_ids: None,
            muted_keywords: None,
            created_at: chrono::Utc::now(),
            updated_at: chrono::Utc::now(),
        };

        assert_eq!(prefs.user_id, user_id);
        assert_eq!(prefs.safety_filter_level, 1);
    }
}
