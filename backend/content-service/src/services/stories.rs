use crate::error::{AppError, Result};
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::{postgres::PgRow, PgPool, Row};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PrivacyLevel {
    Public,
    Followers,
    CloseFriends,
}

impl PrivacyLevel {
    pub fn as_str(&self) -> &'static str {
        match self {
            PrivacyLevel::Public => "public",
            PrivacyLevel::Followers => "followers",
            PrivacyLevel::CloseFriends => "close_friends",
        }
    }
}

impl TryFrom<&str> for PrivacyLevel {
    type Error = AppError;
    fn try_from(s: &str) -> std::result::Result<Self, Self::Error> {
        match s {
            "public" => Ok(PrivacyLevel::Public),
            "followers" => Ok(PrivacyLevel::Followers),
            "close_friends" => Ok(PrivacyLevel::CloseFriends),
            _ => Err(AppError::BadRequest("invalid privacy_level".into())),
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct Story {
    pub id: Uuid,
    pub user_id: Uuid,
    pub content_url: String,
    pub thumbnail_url: Option<String>,
    pub caption: Option<String>,
    pub content_type: String,
    pub privacy_level: String,
    pub expires_at: DateTime<Utc>,
    pub created_at: DateTime<Utc>,
}

pub struct StoriesService {
    pool: PgPool,
}

impl StoriesService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    pub async fn create_story(
        &self,
        user_id: Uuid,
        content_url: &str,
        caption: Option<&str>,
        content_type: &str,
        privacy: PrivacyLevel,
        expires_at: DateTime<Utc>,
    ) -> Result<Story> {
        let row = sqlx::query(
            r#"
            INSERT INTO stories (user_id, content_url, caption, content_type, privacy_level, expires_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING id, user_id, content_url, thumbnail_url, caption, content_type, privacy_level, expires_at, created_at
            "#,
        )
        .bind(user_id)
        .bind(content_url)
        .bind(caption)
        .bind(content_type)
        .bind(privacy.as_str())
        .bind(expires_at)
        .fetch_one(&self.pool)
        .await?;

        Ok(Self::row_to_story(&row))
    }

    pub async fn get_story_for_viewer(
        &self,
        story_id: Uuid,
        viewer_id: Uuid,
    ) -> Result<Option<Story>> {
        // 基础获取（未过期、未删除）
        let row_opt = sqlx::query(
            r#"
            SELECT id, user_id, content_url, thumbnail_url, caption, content_type, privacy_level, expires_at, created_at
            FROM stories
            WHERE id = $1 AND deleted_at IS NULL AND expires_at > NOW()
            "#,
        )
        .bind(story_id)
        .fetch_optional(&self.pool)
        .await?;

        let row = match row_opt {
            Some(r) => r,
            None => return Ok(None),
        };
        let story = Self::row_to_story(&row);

        // 权限检查
        if self
            .can_view(viewer_id, story.user_id, &story.privacy_level)
            .await?
        {
            Ok(Some(story))
        } else {
            Ok(None)
        }
    }

    pub async fn list_feed(&self, viewer_id: Uuid, limit: i64) -> Result<Vec<Story>> {
        // 取 viewer 自己 + 他关注的人；隐私规则：
        // - public: 所有人可见
        // - followers: 仅粉丝可见
        // - close_friends: 仅 owner 的 close_friends 列表可见

        // 简化：一次性查出所有未过期故事，再在 SQL 中应用可见性规则
        let rows = sqlx::query(
            r#"
            SELECT s.id, s.user_id, s.content_url, s.thumbnail_url, s.caption, s.content_type, s.privacy_level, s.expires_at, s.created_at
            FROM stories s
            WHERE s.deleted_at IS NULL AND s.expires_at > NOW()
              AND (
                    s.privacy_level = 'public'
                 OR (s.privacy_level = 'followers' AND EXISTS (
                        SELECT 1 FROM follows f
                        WHERE f.follower_id = $1 AND f.following_id = s.user_id
                    ))
                 OR (s.privacy_level = 'close_friends' AND EXISTS (
                        SELECT 1 FROM story_close_friends cf
                        WHERE cf.owner_id = s.user_id AND cf.friend_id = $1
                    ))
                 OR s.user_id = $1
              )
            ORDER BY s.created_at DESC
            LIMIT $2
            "#,
        )
        .bind(viewer_id)
        .bind(limit.clamp(1, 100))
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.iter().map(Self::row_to_story).collect())
    }

    pub async fn track_view(&self, story_id: Uuid, viewer_id: Uuid) -> Result<()> {
        let _ = sqlx::query(
            r#"INSERT INTO story_views (story_id, viewer_id) VALUES ($1, $2)
               ON CONFLICT (story_id, viewer_id) DO NOTHING"#,
        )
        .bind(story_id)
        .bind(viewer_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Mark expired stories as deleted. Returns affected rows.
    pub async fn cleanup_expired(&self) -> Result<u64> {
        match sqlx::query(
            r#"UPDATE stories SET deleted_at = NOW() WHERE expires_at <= NOW() AND deleted_at IS NULL"#,
        )
        .execute(&self.pool)
        .await
        {
            Ok(res) => Ok(res.rows_affected()),
            Err(err) => {
                let table_missing = err
                    .as_database_error()
                    .and_then(|db_err| db_err.code())
                    .map(|code| code == "42P01")
                    .unwrap_or(false);
                if table_missing {
                    tracing::debug!(
                        "stories cleanup skipped because table does not exist (migration pending)"
                    );
                    Ok(0)
                } else {
                    Err(err.into())
                }
            }
        }
    }

    pub async fn add_close_friend(&self, owner_id: Uuid, friend_id: Uuid) -> Result<()> {
        sqlx::query(
            r#"INSERT INTO story_close_friends (owner_id, friend_id) VALUES ($1, $2)
               ON CONFLICT (owner_id, friend_id) DO NOTHING"#,
        )
        .bind(owner_id)
        .bind(friend_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    pub async fn remove_close_friend(&self, owner_id: Uuid, friend_id: Uuid) -> Result<()> {
        sqlx::query(r#"DELETE FROM story_close_friends WHERE owner_id = $1 AND friend_id = $2"#)
            .bind(owner_id)
            .bind(friend_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    pub async fn list_close_friends(&self, owner_id: Uuid) -> Result<Vec<Uuid>> {
        let rows = sqlx::query(
            r#"SELECT friend_id FROM story_close_friends WHERE owner_id = $1 ORDER BY added_at DESC"#,
        )
        .bind(owner_id)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .map(|r| r.get::<Uuid, _>("friend_id"))
            .collect())
    }

    pub async fn delete_story(&self, owner_id: Uuid, story_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            r#"UPDATE stories SET deleted_at = NOW() WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL"#,
        )
        .bind(story_id)
        .bind(owner_id)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn update_privacy(
        &self,
        owner_id: Uuid,
        story_id: Uuid,
        privacy: PrivacyLevel,
    ) -> Result<bool> {
        let result = sqlx::query(
            r#"UPDATE stories SET privacy_level = $1 WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL"#,
        )
        .bind(privacy.as_str())
        .bind(story_id)
        .bind(owner_id)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected() > 0)
    }

    pub async fn list_user_stories(
        &self,
        owner_id: Uuid,
        viewer_id: Uuid,
        limit: i64,
    ) -> Result<Vec<Story>> {
        let rows = sqlx::query(
            r#"
            SELECT s.id, s.user_id, s.content_url, s.thumbnail_url, s.caption, s.content_type, s.privacy_level, s.expires_at, s.created_at
            FROM stories s
            WHERE s.user_id = $1 AND s.deleted_at IS NULL AND s.expires_at > NOW()
              AND (
                    s.privacy_level = 'public'
                 OR (s.privacy_level = 'followers' AND EXISTS (
                        SELECT 1 FROM follows f WHERE f.follower_id = $2 AND f.following_id = s.user_id
                    ))
                 OR (s.privacy_level = 'close_friends' AND EXISTS (
                        SELECT 1 FROM story_close_friends cf WHERE cf.owner_id = s.user_id AND cf.friend_id = $2
                    ))
                 OR s.user_id = $2
              )
            ORDER BY s.created_at DESC
            LIMIT $3
            "#,
        )
        .bind(owner_id)
        .bind(viewer_id)
        .bind(limit.clamp(1, 100))
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.iter().map(Self::row_to_story).collect())
    }

    async fn can_view(&self, viewer_id: Uuid, owner_id: Uuid, privacy_level: &str) -> Result<bool> {
        if owner_id == viewer_id {
            return Ok(true);
        }
        match privacy_level {
            "public" => Ok(true),
            "followers" => {
                let exists: Option<(bool,)> = sqlx::query_as(
                    r#"SELECT EXISTS(SELECT 1 FROM follows WHERE follower_id = $1 AND following_id = $2)"#,
                )
                .bind(viewer_id)
                .bind(owner_id)
                .fetch_optional(&self.pool)
                .await?;
                Ok(exists.map(|t| t.0).unwrap_or(false))
            }
            "close_friends" => {
                let exists: Option<(bool,)> = sqlx::query_as(
                    r#"SELECT EXISTS(SELECT 1 FROM story_close_friends WHERE owner_id = $1 AND friend_id = $2)"#,
                )
                .bind(owner_id)
                .bind(viewer_id)
                .fetch_optional(&self.pool)
                .await?;
                Ok(exists.map(|t| t.0).unwrap_or(false))
            }
            _ => Ok(false),
        }
    }

    fn row_to_story(row: &PgRow) -> Story {
        Story {
            id: row.get("id"),
            user_id: row.get("user_id"),
            content_url: row.get("content_url"),
            thumbnail_url: row.get("thumbnail_url"),
            caption: row.get("caption"),
            content_type: row.get("content_type"),
            privacy_level: row.get("privacy_level"),
            expires_at: row.get("expires_at"),
            created_at: row.get("created_at"),
        }
    }
}
