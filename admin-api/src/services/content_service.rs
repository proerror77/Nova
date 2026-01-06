// Content service - handles content moderation operations
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

use crate::db::Database;
use crate::error::{AppError, Result};

pub struct ContentService {
    db: Database,
}

/// Post summary for list views (from main Nova posts table)
#[derive(Debug, Clone, FromRow, Serialize)]
pub struct PostSummary {
    pub id: Uuid,
    pub user_id: Uuid,
    pub content: String,
    pub status: String,
    pub images_count: i32,
    pub likes_count: i64,
    pub comments_count: i64,
    pub created_at: DateTime<Utc>,
}

/// Post detail with author info
#[derive(Debug, Clone, Serialize)]
pub struct PostDetail {
    pub id: Uuid,
    pub user_id: Uuid,
    pub content: String,
    pub images: Vec<String>,
    pub status: String,
    pub likes_count: i64,
    pub comments_count: i64,
    pub shares_count: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub author: Option<AuthorInfo>,
    pub reports: Vec<ContentReport>,
}

#[derive(Debug, Clone, Serialize)]
pub struct AuthorInfo {
    pub id: Uuid,
    pub nickname: String,
    pub avatar: Option<String>,
    pub warnings_count: i64,
    pub is_banned: bool,
}

/// Comment summary for list views
#[derive(Debug, Clone, FromRow, Serialize)]
pub struct CommentSummary {
    pub id: Uuid,
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub content: String,
    pub status: String,
    pub created_at: DateTime<Utc>,
}

/// Content report record
#[derive(Debug, Clone, FromRow, Serialize)]
pub struct ContentReport {
    pub id: Uuid,
    pub content_type: String,
    pub content_id: Uuid,
    pub reporter_id: Uuid,
    pub reason: String,
    pub description: Option<String>,
    pub status: String,
    pub reviewed_by: Option<Uuid>,
    pub reviewed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

/// Moderation log record
#[derive(Debug, Clone, FromRow, Serialize)]
pub struct ModerationLog {
    pub id: Uuid,
    pub admin_id: Uuid,
    pub content_type: String,
    pub content_id: Uuid,
    pub action: String,
    pub reason: Option<String>,
    pub notes: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize)]
pub struct ListContentParams {
    pub page: u32,
    pub limit: u32,
    pub status: Option<String>,
    pub search: Option<String>,
}

impl ContentService {
    pub fn new(db: Database) -> Self {
        Self { db }
    }

    /// List posts with pagination and filters
    pub async fn list_posts(&self, params: ListContentParams) -> Result<(Vec<PostSummary>, i64)> {
        let offset = ((params.page - 1) * params.limit) as i64;
        let limit = params.limit as i64;

        // Build dynamic query based on filters
        let mut where_clauses = vec!["1=1".to_string()];

        if let Some(ref status) = params.status {
            where_clauses.push(format!("status = '{}'", status));
        }

        if let Some(ref search) = params.search {
            where_clauses.push(format!("content ILIKE '%{}%'", search));
        }

        let where_clause = where_clauses.join(" AND ");

        // Query posts from main Nova database
        let query = format!(
            r#"
            SELECT
                id,
                user_id,
                COALESCE(content, '') as content,
                COALESCE(status, 'active') as status,
                COALESCE(array_length(images, 1), 0)::int as images_count,
                COALESCE(likes_count, 0) as likes_count,
                COALESCE(comments_count, 0) as comments_count,
                created_at
            FROM posts
            WHERE {}
            ORDER BY created_at DESC
            LIMIT $1 OFFSET $2
            "#,
            where_clause
        );

        let posts: Vec<PostSummary> = sqlx::query_as(&query)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.db.pg)
            .await
            .unwrap_or_default();

        // Get total count
        let count_query = format!(
            "SELECT COUNT(*) FROM posts WHERE {}",
            where_clause
        );

        let total: i64 = sqlx::query_scalar(&count_query)
            .fetch_one(&self.db.pg)
            .await
            .unwrap_or(0);

        Ok((posts, total))
    }

    /// Get post detail by ID
    pub async fn get_post(&self, post_id: Uuid) -> Result<PostDetail> {
        // Get post
        let post: Option<(Uuid, Uuid, String, Option<Vec<String>>, String, i64, i64, i64, DateTime<Utc>, DateTime<Utc>)> = sqlx::query_as(
            r#"
            SELECT
                id,
                user_id,
                COALESCE(content, '') as content,
                images,
                COALESCE(status, 'active') as status,
                COALESCE(likes_count, 0) as likes_count,
                COALESCE(comments_count, 0) as comments_count,
                COALESCE(shares_count, 0) as shares_count,
                created_at,
                updated_at
            FROM posts
            WHERE id = $1
            "#
        )
        .bind(post_id)
        .fetch_optional(&self.db.pg)
        .await?;

        let post = post.ok_or(AppError::NotFound(format!("Post {} not found", post_id)))?;

        // Get author info
        let author: Option<(Uuid, String, Option<String>)> = sqlx::query_as(
            r#"
            SELECT id, COALESCE(nickname, 'Unknown') as nickname, avatar
            FROM users WHERE id = $1
            "#
        )
        .bind(post.1)
        .fetch_optional(&self.db.pg)
        .await
        .unwrap_or(None);

        // Get warnings count and ban status for author
        let (warnings_count, is_banned) = if let Some((user_id, _, _)) = &author {
            let warnings: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM user_warnings WHERE user_id = $1"
            )
            .bind(user_id)
            .fetch_one(&self.db.pg)
            .await
            .unwrap_or(0);

            let bans: i64 = sqlx::query_scalar(
                r#"
                SELECT COUNT(*) FROM user_bans
                WHERE user_id = $1 AND is_active = true
                AND (expires_at IS NULL OR expires_at > NOW())
                "#
            )
            .bind(user_id)
            .fetch_one(&self.db.pg)
            .await
            .unwrap_or(0);

            (warnings, bans > 0)
        } else {
            (0, false)
        };

        // Get reports for this post
        let reports: Vec<ContentReport> = sqlx::query_as(
            r#"
            SELECT * FROM content_reports
            WHERE content_type = 'post' AND content_id = $1
            ORDER BY created_at DESC
            "#
        )
        .bind(post_id)
        .fetch_all(&self.db.pg)
        .await
        .unwrap_or_default();

        Ok(PostDetail {
            id: post.0,
            user_id: post.1,
            content: post.2,
            images: post.3.unwrap_or_default(),
            status: post.4,
            likes_count: post.5,
            comments_count: post.6,
            shares_count: post.7,
            created_at: post.8,
            updated_at: post.9,
            author: author.map(|(id, nickname, avatar)| AuthorInfo {
                id,
                nickname,
                avatar,
                warnings_count,
                is_banned,
            }),
            reports,
        })
    }

    /// Approve a post
    pub async fn approve_post(&self, post_id: Uuid, admin_id: Uuid, notes: Option<&str>) -> Result<()> {
        // Update post status in main table
        sqlx::query("UPDATE posts SET status = 'active' WHERE id = $1")
            .bind(post_id)
            .execute(&self.db.pg)
            .await?;

        // Log moderation action
        self.log_moderation(admin_id, "post", post_id, "approve", None, notes).await?;

        // Resolve pending reports
        sqlx::query(
            r#"
            UPDATE content_reports
            SET status = 'resolved', reviewed_by = $2, reviewed_at = NOW()
            WHERE content_type = 'post' AND content_id = $1 AND status = 'pending'
            "#
        )
        .bind(post_id)
        .bind(admin_id)
        .execute(&self.db.pg)
        .await?;

        Ok(())
    }

    /// Reject a post
    pub async fn reject_post(&self, post_id: Uuid, admin_id: Uuid, reason: &str, notes: Option<&str>) -> Result<()> {
        // Update post status
        sqlx::query("UPDATE posts SET status = 'rejected' WHERE id = $1")
            .bind(post_id)
            .execute(&self.db.pg)
            .await?;

        // Log moderation action
        self.log_moderation(admin_id, "post", post_id, "reject", Some(reason), notes).await?;

        // Resolve pending reports
        sqlx::query(
            r#"
            UPDATE content_reports
            SET status = 'resolved', reviewed_by = $2, reviewed_at = NOW()
            WHERE content_type = 'post' AND content_id = $1 AND status = 'pending'
            "#
        )
        .bind(post_id)
        .bind(admin_id)
        .execute(&self.db.pg)
        .await?;

        Ok(())
    }

    /// List comments with pagination
    pub async fn list_comments(&self, params: ListContentParams) -> Result<(Vec<CommentSummary>, i64)> {
        let offset = ((params.page - 1) * params.limit) as i64;
        let limit = params.limit as i64;

        let mut where_clauses = vec!["1=1".to_string()];

        if let Some(ref status) = params.status {
            where_clauses.push(format!("status = '{}'", status));
        }

        if let Some(ref search) = params.search {
            where_clauses.push(format!("content ILIKE '%{}%'", search));
        }

        let where_clause = where_clauses.join(" AND ");

        let query = format!(
            r#"
            SELECT
                id,
                post_id,
                user_id,
                COALESCE(content, '') as content,
                COALESCE(status, 'active') as status,
                created_at
            FROM comments
            WHERE {}
            ORDER BY created_at DESC
            LIMIT $1 OFFSET $2
            "#,
            where_clause
        );

        let comments: Vec<CommentSummary> = sqlx::query_as(&query)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.db.pg)
            .await
            .unwrap_or_default();

        let count_query = format!(
            "SELECT COUNT(*) FROM comments WHERE {}",
            where_clause
        );

        let total: i64 = sqlx::query_scalar(&count_query)
            .fetch_one(&self.db.pg)
            .await
            .unwrap_or(0);

        Ok((comments, total))
    }

    /// Approve a comment
    pub async fn approve_comment(&self, comment_id: Uuid, admin_id: Uuid, notes: Option<&str>) -> Result<()> {
        sqlx::query("UPDATE comments SET status = 'active' WHERE id = $1")
            .bind(comment_id)
            .execute(&self.db.pg)
            .await?;

        self.log_moderation(admin_id, "comment", comment_id, "approve", None, notes).await?;

        sqlx::query(
            r#"
            UPDATE content_reports
            SET status = 'resolved', reviewed_by = $2, reviewed_at = NOW()
            WHERE content_type = 'comment' AND content_id = $1 AND status = 'pending'
            "#
        )
        .bind(comment_id)
        .bind(admin_id)
        .execute(&self.db.pg)
        .await?;

        Ok(())
    }

    /// Reject a comment
    pub async fn reject_comment(&self, comment_id: Uuid, admin_id: Uuid, reason: &str, notes: Option<&str>) -> Result<()> {
        sqlx::query("UPDATE comments SET status = 'rejected' WHERE id = $1")
            .bind(comment_id)
            .execute(&self.db.pg)
            .await?;

        self.log_moderation(admin_id, "comment", comment_id, "reject", Some(reason), notes).await?;

        sqlx::query(
            r#"
            UPDATE content_reports
            SET status = 'resolved', reviewed_by = $2, reviewed_at = NOW()
            WHERE content_type = 'comment' AND content_id = $1 AND status = 'pending'
            "#
        )
        .bind(comment_id)
        .bind(admin_id)
        .execute(&self.db.pg)
        .await?;

        Ok(())
    }

    /// Get report counts for content
    pub async fn get_reports_count(&self, content_type: &str, content_id: Uuid) -> Result<i64> {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM content_reports WHERE content_type = $1 AND content_id = $2"
        )
        .bind(content_type)
        .bind(content_id)
        .fetch_one(&self.db.pg)
        .await
        .unwrap_or(0);

        Ok(count)
    }

    /// Remove (soft delete) a post
    pub async fn remove_post(&self, post_id: Uuid, admin_id: Uuid, reason: &str, notes: Option<&str>) -> Result<()> {
        // Update post status to removed
        sqlx::query("UPDATE posts SET status = 'removed' WHERE id = $1")
            .bind(post_id)
            .execute(&self.db.pg)
            .await?;

        // Log moderation action
        self.log_moderation(admin_id, "post", post_id, "remove", Some(reason), notes).await?;

        // Resolve pending reports
        sqlx::query(
            r#"
            UPDATE content_reports
            SET status = 'resolved', reviewed_by = $2, reviewed_at = NOW()
            WHERE content_type = 'post' AND content_id = $1 AND status = 'pending'
            "#
        )
        .bind(post_id)
        .bind(admin_id)
        .execute(&self.db.pg)
        .await?;

        Ok(())
    }

    /// Restore a removed post
    pub async fn restore_post(&self, post_id: Uuid, admin_id: Uuid, notes: Option<&str>) -> Result<()> {
        // Check if post exists and is removed
        let status: Option<String> = sqlx::query_scalar("SELECT status FROM posts WHERE id = $1")
            .bind(post_id)
            .fetch_optional(&self.db.pg)
            .await?;

        match status {
            Some(s) if s == "removed" || s == "rejected" => {
                // Restore post
                sqlx::query("UPDATE posts SET status = 'active' WHERE id = $1")
                    .bind(post_id)
                    .execute(&self.db.pg)
                    .await?;

                self.log_moderation(admin_id, "post", post_id, "restore", None, notes).await?;
                Ok(())
            }
            Some(_) => Err(AppError::BadRequest("Post is not in removed/rejected status".to_string())),
            None => Err(AppError::NotFound(format!("Post {} not found", post_id))),
        }
    }

    /// Remove (soft delete) a comment
    pub async fn remove_comment(&self, comment_id: Uuid, admin_id: Uuid, reason: &str, notes: Option<&str>) -> Result<()> {
        sqlx::query("UPDATE comments SET status = 'removed' WHERE id = $1")
            .bind(comment_id)
            .execute(&self.db.pg)
            .await?;

        self.log_moderation(admin_id, "comment", comment_id, "remove", Some(reason), notes).await?;

        sqlx::query(
            r#"
            UPDATE content_reports
            SET status = 'resolved', reviewed_by = $2, reviewed_at = NOW()
            WHERE content_type = 'comment' AND content_id = $1 AND status = 'pending'
            "#
        )
        .bind(comment_id)
        .bind(admin_id)
        .execute(&self.db.pg)
        .await?;

        Ok(())
    }

    /// Get moderation queue - pending posts and comments
    pub async fn get_moderation_queue(&self, limit: u32) -> Result<ModerationQueue> {
        let limit = limit as i64;

        // Get pending posts (status = 'pending' or with unresolved reports)
        let pending_posts: Vec<PostSummary> = sqlx::query_as(
            r#"
            SELECT DISTINCT
                p.id,
                p.user_id,
                COALESCE(p.content, '') as content,
                COALESCE(p.status, 'active') as status,
                COALESCE(array_length(p.images, 1), 0)::int as images_count,
                COALESCE(p.likes_count, 0) as likes_count,
                COALESCE(p.comments_count, 0) as comments_count,
                p.created_at
            FROM posts p
            LEFT JOIN content_reports cr ON cr.content_type = 'post' AND cr.content_id = p.id AND cr.status = 'pending'
            WHERE p.status = 'pending' OR cr.id IS NOT NULL
            ORDER BY p.created_at ASC
            LIMIT $1
            "#
        )
        .bind(limit)
        .fetch_all(&self.db.pg)
        .await
        .unwrap_or_default();

        // Get pending comments
        let pending_comments: Vec<CommentSummary> = sqlx::query_as(
            r#"
            SELECT DISTINCT
                c.id,
                c.post_id,
                c.user_id,
                COALESCE(c.content, '') as content,
                COALESCE(c.status, 'active') as status,
                c.created_at
            FROM comments c
            LEFT JOIN content_reports cr ON cr.content_type = 'comment' AND cr.content_id = c.id AND cr.status = 'pending'
            WHERE c.status = 'pending' OR cr.id IS NOT NULL
            ORDER BY c.created_at ASC
            LIMIT $1
            "#
        )
        .bind(limit)
        .fetch_all(&self.db.pg)
        .await
        .unwrap_or_default();

        // Get total counts
        let total_pending_posts: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(DISTINCT p.id)
            FROM posts p
            LEFT JOIN content_reports cr ON cr.content_type = 'post' AND cr.content_id = p.id AND cr.status = 'pending'
            WHERE p.status = 'pending' OR cr.id IS NOT NULL
            "#
        )
        .fetch_one(&self.db.pg)
        .await
        .unwrap_or(0);

        let total_pending_comments: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(DISTINCT c.id)
            FROM comments c
            LEFT JOIN content_reports cr ON cr.content_type = 'comment' AND cr.content_id = c.id AND cr.status = 'pending'
            WHERE c.status = 'pending' OR cr.id IS NOT NULL
            "#
        )
        .fetch_one(&self.db.pg)
        .await
        .unwrap_or(0);

        Ok(ModerationQueue {
            pending_posts,
            pending_comments,
            total_pending_posts,
            total_pending_comments,
        })
    }

    /// Log a moderation action
    async fn log_moderation(
        &self,
        admin_id: Uuid,
        content_type: &str,
        content_id: Uuid,
        action: &str,
        reason: Option<&str>,
        notes: Option<&str>,
    ) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO moderation_logs (admin_id, content_type, content_id, action, reason, notes)
            VALUES ($1, $2, $3, $4, $5, $6)
            "#
        )
        .bind(admin_id)
        .bind(content_type)
        .bind(content_id)
        .bind(action)
        .bind(reason)
        .bind(notes)
        .execute(&self.db.pg)
        .await?;

        Ok(())
    }
}

/// Moderation queue response
#[derive(Debug, Clone, Serialize)]
pub struct ModerationQueue {
    pub pending_posts: Vec<PostSummary>,
    pub pending_comments: Vec<CommentSummary>,
    pub total_pending_posts: i64,
    pub total_pending_comments: i64,
}
