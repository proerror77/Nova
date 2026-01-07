/// Post service - handles post creation, retrieval, and management
use crate::cache::ContentCache;
use crate::error::Result;
use crate::kafka::events::{
    publish_post_created, publish_post_created_for_vlm, publish_post_deleted,
    publish_post_status_updated,
};
use crate::models::Post;
use chrono::Utc;
use sqlx::PgPool;
use std::sync::Arc;
use transactional_outbox::SqlxOutboxRepository;
use uuid::Uuid;

pub struct PostService {
    pool: PgPool,
    cache: Option<Arc<ContentCache>>,
    outbox_repo: Option<Arc<SqlxOutboxRepository>>,
}

impl PostService {
    pub fn new(pool: PgPool) -> Self {
        Self {
            pool,
            cache: None,
            outbox_repo: None,
        }
    }

    pub fn with_cache(pool: PgPool, cache: Arc<ContentCache>) -> Self {
        Self {
            pool,
            cache: Some(cache),
            outbox_repo: None,
        }
    }

    pub fn with_outbox(
        pool: PgPool,
        cache: Arc<ContentCache>,
        outbox_repo: Arc<SqlxOutboxRepository>,
    ) -> Self {
        Self {
            pool,
            cache: Some(cache),
            outbox_repo: Some(outbox_repo),
        }
    }

    fn cache(&self) -> Option<&Arc<ContentCache>> {
        self.cache.as_ref()
    }

    /// Get a post by ID
    pub async fn get_post(&self, post_id: Uuid) -> Result<Option<Post>> {
        if let Some(cache) = self.cache() {
            if let Some(cached) = cache.get_post(post_id).await? {
                return Ok(Some(cached));
            }
        }

        let post = sqlx::query_as::<_, Post>(
            r#"
            SELECT id, user_id, content, caption, media_key, media_type, media_urls, status,
                   created_at, updated_at, deleted_at, soft_delete::text AS soft_delete, author_account_type
            FROM posts
            WHERE id = $1 AND deleted_at IS NULL
            "#,
        )
        .bind(post_id)
        .fetch_optional(&self.pool)
        .await?;

        if let (Some(cache), Some(post)) = (self.cache(), &post) {
            if let Err(err) = cache.cache_post(post).await {
                tracing::debug!(%post_id, "post cache set failed: {}", err);
            }
        }

        Ok(post)
    }

    /// Get posts for a user
    pub async fn get_user_posts(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<Post>> {
        let posts = sqlx::query_as::<_, Post>(
            r#"
            SELECT id, user_id, content, caption, media_key, media_type, media_urls, status,
                   created_at, updated_at, deleted_at, soft_delete::text AS soft_delete, author_account_type
            FROM posts
            WHERE user_id = $1 AND deleted_at IS NULL
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(posts)
    }

    /// Create a new post
    pub async fn create_post(
        &self,
        user_id: Uuid,
        caption: Option<&str>,
        media_key: &str,
        media_type: &str,
        author_account_type: Option<&str>,
    ) -> Result<Post> {
        self.create_post_with_urls(
            user_id,
            caption,
            media_key,
            media_type,
            &[],
            author_account_type,
        )
        .await
    }

    /// Create a new post with explicit media URLs
    pub async fn create_post_with_urls(
        &self,
        user_id: Uuid,
        caption: Option<&str>,
        media_key: &str,
        media_type: &str,
        media_urls: &[String],
        author_account_type: Option<&str>,
    ) -> Result<Post> {
        // Validate: posts must have either media or non-empty content
        // This prevents "empty posts" that have no content and no images
        let has_media = !media_urls.is_empty();
        let has_content = caption.map(|c| !c.trim().is_empty()).unwrap_or(false);
        if !has_media && !has_content {
            return Err(crate::error::AppError::ValidationError(
                "Post must have either media or text content".to_string(),
            ));
        }

        // Start transaction for atomic post creation + event publishing
        let mut tx = self.pool.begin().await?;

        // Serialize media_urls to JSON
        let media_urls_json = serde_json::to_value(media_urls).unwrap_or_default();

        // Note: media_urls fallback to media_key only when media_type is NOT 'text'
        let account_type = author_account_type.unwrap_or("primary");
        let post = sqlx::query_as::<_, Post>(
            r#"
            INSERT INTO posts (user_id, caption, media_key, media_type, media_urls, status, author_account_type)
            VALUES (
                $1,
                $2,
                $3,
                $4,
                CASE WHEN $5::jsonb = '[]'::jsonb AND $4 <> 'text' THEN jsonb_build_array($3) ELSE $5::jsonb END,
                'published',
                $6
            )
            RETURNING id, user_id, content, caption, media_key, media_type, media_urls, status,
                      created_at, updated_at, deleted_at, soft_delete::text AS soft_delete, author_account_type
            "#,
        )
        .bind(user_id)
        .bind(caption)
        .bind(media_key)
        .bind(media_type)
        .bind(media_urls_json)
        .bind(account_type)
        .fetch_one(&mut *tx)
        .await?;

        // Publish event to outbox (same transaction)
        if let Some(outbox) = &self.outbox_repo {
            publish_post_created(&mut tx, outbox.as_ref(), &post).await?;

            // Publish VLM event for posts with images (async processing)
            if media_type != "text" && !media_urls.is_empty() {
                publish_post_created_for_vlm(&mut tx, outbox.as_ref(), &post, media_urls, true)
                    .await?;
                tracing::debug!(
                    post_id = %post.id,
                    image_count = media_urls.len(),
                    "Published VLM event for post"
                );
            }
        }

        // Commit transaction (both post and event committed atomically)
        tx.commit().await?;

        // Cache post after successful commit (fire-and-forget, not transactional)
        if let Some(cache) = self.cache() {
            if let Err(err) = cache.cache_post(&post).await {
                tracing::debug!(post_id = %post.id, "post cache set failed: {}", err);
            }
        }

        Ok(post)
    }

    /// Create a new post with explicit media URLs and channel associations
    pub async fn create_post_with_urls_and_channels(
        &self,
        user_id: Uuid,
        caption: Option<&str>,
        media_key: &str,
        media_type: &str,
        media_urls: &[String],
        channel_ids: &[Uuid],
        author_account_type: Option<&str>,
    ) -> Result<Post> {
        // Validate: posts must have either media or non-empty content
        // This prevents "empty posts" that have no content and no images
        let has_media = !media_urls.is_empty();
        let has_content = caption.map(|c| !c.trim().is_empty()).unwrap_or(false);
        if !has_media && !has_content {
            return Err(crate::error::AppError::ValidationError(
                "Post must have either media or text content".to_string(),
            ));
        }

        // Start transaction for atomic post creation + channel associations + event publishing
        let mut tx = self.pool.begin().await?;

        // Serialize media_urls to JSON
        let media_urls_json = serde_json::to_value(media_urls).unwrap_or_default();

        // 1. Create the post
        // Note: media_urls should only be populated with media_key as fallback when:
        //   - media_urls is empty AND media_type is NOT 'text' (text-only posts)
        // For text-only posts (media_type='text'), media_urls should remain empty
        let account_type = author_account_type.unwrap_or("primary");
        let post = sqlx::query_as::<_, Post>(
            r#"
            INSERT INTO posts (user_id, caption, media_key, media_type, media_urls, status, author_account_type)
            VALUES (
                $1,
                $2,
                $3,
                $4,
                CASE WHEN $5::jsonb = '[]'::jsonb AND $4 <> 'text' THEN jsonb_build_array($3) ELSE $5::jsonb END,
                'published',
                $6
            )
            RETURNING id, user_id, content, caption, media_key, media_type, media_urls, status,
                      created_at, updated_at, deleted_at, soft_delete::text AS soft_delete, author_account_type
            "#,
        )
        .bind(user_id)
        .bind(caption)
        .bind(media_key)
        .bind(media_type)
        .bind(media_urls_json)
        .bind(account_type)
        .fetch_one(&mut *tx)
        .await?;

        // 2. Insert channel associations (if any channels provided)
        if !channel_ids.is_empty() {
            let now = Utc::now();
            for channel_id in channel_ids {
                sqlx::query(
                    r#"
                    INSERT INTO post_channels (post_id, channel_id, confidence, tagged_by, created_at)
                    VALUES ($1, $2, $3, $4, $5)
                    ON CONFLICT (post_id, channel_id) DO NOTHING
                    "#,
                )
                .bind(post.id)
                .bind(channel_id)
                .bind(1.0_f32) // confidence: 1.0 for manual author tagging
                .bind("author") // tagged_by: author tagged their own post
                .bind(now)
                .execute(&mut *tx)
                .await?;
            }
            tracing::info!(
                post_id = %post.id,
                channel_count = channel_ids.len(),
                "Post associated with channels"
            );
        }

        // 3. Publish event to outbox (same transaction)
        if let Some(outbox) = &self.outbox_repo {
            publish_post_created(&mut tx, outbox.as_ref(), &post).await?;

            // 3a. Publish VLM event for posts with images (async processing)
            // Only if media_type indicates actual media (not 'text' for text-only posts)
            if media_type != "text" && !media_urls.is_empty() {
                // Determine if channels should be auto-assigned (if none were manually specified)
                let auto_assign = channel_ids.is_empty();
                publish_post_created_for_vlm(
                    &mut tx,
                    outbox.as_ref(),
                    &post,
                    media_urls,
                    auto_assign,
                )
                .await?;
                tracing::debug!(
                    post_id = %post.id,
                    image_count = media_urls.len(),
                    auto_assign = auto_assign,
                    "Published VLM event for post"
                );
            }
        }

        // 4. Commit transaction (post, channel associations, and event committed atomically)
        tx.commit().await?;

        // Cache post after successful commit (fire-and-forget, not transactional)
        if let Some(cache) = self.cache() {
            if let Err(err) = cache.cache_post(&post).await {
                tracing::debug!(post_id = %post.id, "post cache set failed: {}", err);
            }
        }

        Ok(post)
    }

    /// Update post status
    pub async fn update_post_status(
        &self,
        post_id: Uuid,
        user_id: Uuid,
        status: &str,
    ) -> Result<bool> {
        // Start transaction for atomic status update + event publishing
        let mut tx = self.pool.begin().await?;

        let result = sqlx::query(
            r#"
            UPDATE posts
            SET status = $1, updated_at = NOW()
            WHERE id = $2 AND user_id = $3 AND deleted_at IS NULL
            "#,
        )
        .bind(status)
        .bind(post_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

        let updated = result.rows_affected() > 0;

        if updated {
            // Publish event to outbox (same transaction)
            if let Some(outbox) = &self.outbox_repo {
                publish_post_status_updated(&mut tx, outbox.as_ref(), post_id, user_id, status)
                    .await?;
            }
        }

        // Commit transaction (both update and event committed atomically)
        tx.commit().await?;

        // Invalidate cache after successful commit (fire-and-forget, not transactional)
        if updated {
            if let Some(cache) = self.cache() {
                if let Err(err) = cache.invalidate_post(post_id).await {
                    tracing::debug!(%post_id, "post cache invalidation failed: {}", err);
                }
            }
        }

        Ok(updated)
    }

    /// Get posts liked by a user using SQL JOIN (single query)
    pub async fn get_user_liked_posts(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<(Vec<Post>, i64)> {
        // Get posts with JOIN on likes table
        let posts = sqlx::query_as::<_, Post>(
            r#"
            SELECT p.id, p.user_id, p.content, p.caption, p.media_key, p.media_type, p.media_urls, p.status,
                   p.created_at, p.updated_at, p.deleted_at, p.soft_delete::text AS soft_delete, p.author_account_type
            FROM posts p
            INNER JOIN likes l ON p.id = l.post_id
            WHERE l.user_id = $1 AND p.deleted_at IS NULL
            ORDER BY l.created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        // Get total count
        let total: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*)
            FROM likes l
            INNER JOIN posts p ON p.id = l.post_id
            WHERE l.user_id = $1 AND p.deleted_at IS NULL
            "#,
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        // Cache fetched posts
        for post in &posts {
            if let Some(cache) = self.cache() {
                if let Err(err) = cache.cache_post(post).await {
                    tracing::debug!(post_id = %post.id, "post cache set failed: {}", err);
                }
            }
        }

        Ok((posts, total))
    }

    /// Get posts saved/bookmarked by a user using SQL JOIN (single query)
    pub async fn get_user_saved_posts(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<(Vec<Post>, i64)> {
        // Get posts with JOIN on bookmarks table
        let posts = sqlx::query_as::<_, Post>(
            r#"
            SELECT p.id, p.user_id, p.content, p.caption, p.media_key, p.media_type, p.media_urls, p.status,
                   p.created_at, p.updated_at, p.deleted_at, p.soft_delete::text AS soft_delete, p.author_account_type
            FROM posts p
            INNER JOIN bookmarks b ON p.id = b.post_id
            WHERE b.user_id = $1 AND p.deleted_at IS NULL
            ORDER BY b.bookmarked_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        // Get total count
        let total: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*)
            FROM bookmarks b
            INNER JOIN posts p ON p.id = b.post_id
            WHERE b.user_id = $1 AND p.deleted_at IS NULL
            "#,
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        // Cache fetched posts
        for post in &posts {
            if let Some(cache) = self.cache() {
                if let Err(err) = cache.cache_post(post).await {
                    tracing::debug!(post_id = %post.id, "post cache set failed: {}", err);
                }
            }
        }

        Ok((posts, total))
    }

    /// Get multiple posts by IDs in a single query (batch fetch)
    /// Returns posts in the order of the input IDs, skipping any that don't exist
    pub async fn get_posts_batch(&self, post_ids: &[Uuid]) -> Result<Vec<Post>> {
        if post_ids.is_empty() {
            return Ok(vec![]);
        }

        // Limit batch size to prevent abuse
        const MAX_BATCH_SIZE: usize = 100;
        let ids_to_fetch = if post_ids.len() > MAX_BATCH_SIZE {
            tracing::warn!(
                requested = post_ids.len(),
                max = MAX_BATCH_SIZE,
                "Batch request exceeds max size, truncating"
            );
            &post_ids[..MAX_BATCH_SIZE]
        } else {
            post_ids
        };

        // Check cache first for any cached posts
        let mut cached_posts: std::collections::HashMap<Uuid, Post> =
            std::collections::HashMap::new();
        let mut uncached_ids: Vec<Uuid> = Vec::new();

        if let Some(cache) = self.cache() {
            for &id in ids_to_fetch {
                match cache.get_post(id).await {
                    Ok(Some(post)) => {
                        cached_posts.insert(id, post);
                    }
                    _ => {
                        uncached_ids.push(id);
                    }
                }
            }
        } else {
            uncached_ids.extend(ids_to_fetch);
        }

        // Fetch uncached posts from database in a single query
        let mut db_posts: std::collections::HashMap<Uuid, Post> = std::collections::HashMap::new();
        if !uncached_ids.is_empty() {
            let posts = sqlx::query_as::<_, Post>(
                r#"
                SELECT id, user_id, content, caption, media_key, media_type, media_urls, status,
                       created_at, updated_at, deleted_at, soft_delete::text AS soft_delete, author_account_type
                FROM posts
                WHERE id = ANY($1) AND deleted_at IS NULL
                "#,
            )
            .bind(&uncached_ids)
            .fetch_all(&self.pool)
            .await?;

            // Cache fetched posts and build lookup map
            for post in posts {
                if let Some(cache) = self.cache() {
                    if let Err(err) = cache.cache_post(&post).await {
                        tracing::debug!(post_id = %post.id, "post cache set failed: {}", err);
                    }
                }
                db_posts.insert(post.id, post);
            }
        }

        // Build result in original order
        let result: Vec<Post> = ids_to_fetch
            .iter()
            .filter_map(|id| cached_posts.remove(id).or_else(|| db_posts.remove(id)))
            .collect();

        tracing::debug!(
            requested = ids_to_fetch.len(),
            found = result.len(),
            "Batch post fetch completed"
        );

        Ok(result)
    }

    /// Soft delete a post
    pub async fn delete_post(&self, post_id: Uuid, user_id: Uuid) -> Result<bool> {
        // Start transaction for atomic soft delete + event publishing
        let mut tx = self.pool.begin().await?;

        let result = sqlx::query(
            r#"
            UPDATE posts
            SET deleted_at = NOW()
            WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
            "#,
        )
        .bind(post_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

        let deleted = result.rows_affected() > 0;

        if deleted {
            // Publish event to outbox (same transaction)
            if let Some(outbox) = &self.outbox_repo {
                publish_post_deleted(&mut tx, outbox.as_ref(), post_id, user_id).await?;
            }
        }

        // Commit transaction (both delete and event committed atomically)
        tx.commit().await?;

        // Invalidate cache after successful commit (fire-and-forget, not transactional)
        if deleted {
            if let Some(cache) = self.cache() {
                if let Err(err) = cache.invalidate_post(post_id).await {
                    tracing::debug!(%post_id, "post cache invalidation failed: {}", err);
                }
            }
        }

        Ok(deleted)
    }
}
