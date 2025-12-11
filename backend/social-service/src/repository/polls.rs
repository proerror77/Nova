use crate::domain::models::{CandidatePreview, CandidateWithRank, Poll, PollCandidate, PollVote};
use anyhow::{Context, Result};
use sqlx::PgPool;
use uuid::Uuid;

/// Repository for Poll operations
#[derive(Clone)]
pub struct PollRepository {
    pool: PgPool,
}

impl PollRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Get trending polls (active polls sorted by vote count)
    pub async fn get_trending_polls(
        &self,
        limit: i32,
        tags: Option<Vec<String>>,
    ) -> Result<Vec<Poll>> {
        let polls = if let Some(tags) = tags {
            sqlx::query_as::<_, Poll>(
                r#"
                SELECT id, title, description, cover_image_url, creator_id, poll_type,
                       status, total_votes, candidate_count, tags, created_at, updated_at,
                       ends_at, is_deleted
                FROM polls
                WHERE status = 'active' AND is_deleted = FALSE AND tags && $1
                ORDER BY total_votes DESC
                LIMIT $2
                "#,
            )
            .bind(&tags)
            .bind(limit)
            .fetch_all(&self.pool)
            .await?
        } else {
            sqlx::query_as::<_, Poll>(
                r#"
                SELECT id, title, description, cover_image_url, creator_id, poll_type,
                       status, total_votes, candidate_count, tags, created_at, updated_at,
                       ends_at, is_deleted
                FROM polls
                WHERE status = 'active' AND is_deleted = FALSE
                ORDER BY total_votes DESC
                LIMIT $1
                "#,
            )
            .bind(limit)
            .fetch_all(&self.pool)
            .await?
        };

        Ok(polls)
    }

    /// Get poll by ID
    pub async fn get_poll(&self, poll_id: Uuid) -> Result<Option<Poll>> {
        let poll = sqlx::query_as::<_, Poll>(
            r#"
            SELECT id, title, description, cover_image_url, creator_id, poll_type,
                   status, total_votes, candidate_count, tags, created_at, updated_at,
                   ends_at, is_deleted
            FROM polls
            WHERE id = $1 AND is_deleted = FALSE
            "#,
        )
        .bind(poll_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(poll)
    }

    /// Get candidates for a poll (sorted by vote_count DESC)
    pub async fn get_poll_candidates(&self, poll_id: Uuid) -> Result<Vec<PollCandidate>> {
        let candidates = sqlx::query_as::<_, PollCandidate>(
            r#"
            SELECT id, poll_id, name, avatar_url, description, user_id,
                   vote_count, position, created_at, is_deleted
            FROM poll_candidates
            WHERE poll_id = $1 AND is_deleted = FALSE
            ORDER BY vote_count DESC, position ASC
            "#,
        )
        .bind(poll_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(candidates)
    }

    /// Get top N candidates for preview
    pub async fn get_top_candidates(
        &self,
        poll_id: Uuid,
        limit: i32,
    ) -> Result<Vec<CandidatePreview>> {
        let rows = sqlx::query_as::<_, (Uuid, String, Option<String>, i64)>(
            r#"
            SELECT id, name, avatar_url, vote_count
            FROM poll_candidates
            WHERE poll_id = $1 AND is_deleted = FALSE
            ORDER BY vote_count DESC
            LIMIT $2
            "#,
        )
        .bind(poll_id)
        .bind(limit)
        .fetch_all(&self.pool)
        .await?;

        let previews: Vec<CandidatePreview> = rows
            .into_iter()
            .enumerate()
            .map(|(idx, (id, name, avatar_url, _))| CandidatePreview {
                id,
                name,
                avatar_url,
                rank: (idx + 1) as i32,
            })
            .collect();

        Ok(previews)
    }

    /// Get rankings with pagination
    pub async fn get_rankings(
        &self,
        poll_id: Uuid,
        limit: i32,
        offset: i32,
    ) -> Result<(Vec<CandidateWithRank>, i32, i64)> {
        // Get total votes for percentage calculation
        let poll = self.get_poll(poll_id).await?.context("Poll not found")?;
        let total_votes = poll.total_votes;

        // Get candidates with rank
        let candidates = sqlx::query_as::<_, PollCandidate>(
            r#"
            SELECT id, poll_id, name, avatar_url, description, user_id,
                   vote_count, position, created_at, is_deleted
            FROM poll_candidates
            WHERE poll_id = $1 AND is_deleted = FALSE
            ORDER BY vote_count DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(poll_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        let ranked: Vec<CandidateWithRank> = candidates
            .into_iter()
            .enumerate()
            .map(|(idx, c)| {
                let rank = offset + (idx as i32) + 1;
                let vote_percentage = if total_votes > 0 {
                    (c.vote_count as f64 / total_votes as f64) * 100.0
                } else {
                    0.0
                };
                CandidateWithRank {
                    id: c.id,
                    name: c.name,
                    avatar_url: c.avatar_url,
                    description: c.description,
                    user_id: c.user_id,
                    vote_count: c.vote_count,
                    rank,
                    rank_change: 0, // TODO: Track rank changes over time
                    vote_percentage,
                }
            })
            .collect();

        Ok((ranked, poll.candidate_count, total_votes))
    }

    /// Vote on a poll (one vote per user per poll)
    pub async fn vote(&self, poll_id: Uuid, candidate_id: Uuid, user_id: Uuid) -> Result<PollVote> {
        // Check if user already voted
        let existing = sqlx::query_scalar::<_, bool>(
            r#"
            SELECT EXISTS(
                SELECT 1 FROM poll_votes
                WHERE poll_id = $1 AND user_id = $2
            )
            "#,
        )
        .bind(poll_id)
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        if existing {
            anyhow::bail!("User has already voted on this poll");
        }

        // Insert vote (triggers will update counts)
        let vote = sqlx::query_as::<_, PollVote>(
            r#"
            INSERT INTO poll_votes (poll_id, candidate_id, user_id)
            VALUES ($1, $2, $3)
            RETURNING id, poll_id, candidate_id, user_id, created_at
            "#,
        )
        .bind(poll_id)
        .bind(candidate_id)
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        Ok(vote)
    }

    /// Check if user has voted on a poll
    pub async fn check_voted(&self, poll_id: Uuid, user_id: Uuid) -> Result<Option<PollVote>> {
        let vote = sqlx::query_as::<_, PollVote>(
            r#"
            SELECT id, poll_id, candidate_id, user_id, created_at
            FROM poll_votes
            WHERE poll_id = $1 AND user_id = $2
            "#,
        )
        .bind(poll_id)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(vote)
    }

    /// Get a specific candidate
    pub async fn get_candidate(&self, candidate_id: Uuid) -> Result<Option<PollCandidate>> {
        let candidate = sqlx::query_as::<_, PollCandidate>(
            r#"
            SELECT id, poll_id, name, avatar_url, description, user_id,
                   vote_count, position, created_at, is_deleted
            FROM poll_candidates
            WHERE id = $1 AND is_deleted = FALSE
            "#,
        )
        .bind(candidate_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(candidate)
    }

    /// Create a new poll with optional initial candidates
    pub async fn create_poll(
        &self,
        creator_id: Uuid,
        title: String,
        description: Option<String>,
        cover_image_url: Option<String>,
        poll_type: String,
        tags: Vec<String>,
        ends_at: Option<chrono::DateTime<chrono::Utc>>,
        initial_candidates: Vec<CreateCandidateInput>,
    ) -> Result<(Poll, Vec<PollCandidate>)> {
        let mut tx = self.pool.begin().await?;

        // Create poll
        let poll = sqlx::query_as::<_, Poll>(
            r#"
            INSERT INTO polls (creator_id, title, description, cover_image_url, poll_type, tags, ends_at, status, candidate_count)
            VALUES ($1, $2, $3, $4, $5, $6, $7, 'active', $8)
            RETURNING id, title, description, cover_image_url, creator_id, poll_type,
                      status, total_votes, candidate_count, tags, created_at, updated_at,
                      ends_at, is_deleted
            "#,
        )
        .bind(creator_id)
        .bind(&title)
        .bind(&description)
        .bind(&cover_image_url)
        .bind(&poll_type)
        .bind(&tags)
        .bind(ends_at)
        .bind(initial_candidates.len() as i32)
        .fetch_one(&mut *tx)
        .await?;

        // Insert initial candidates
        let mut candidates = Vec::with_capacity(initial_candidates.len());
        for (idx, input) in initial_candidates.into_iter().enumerate() {
            let candidate = sqlx::query_as::<_, PollCandidate>(
                r#"
                INSERT INTO poll_candidates (poll_id, name, avatar_url, description, user_id, position)
                VALUES ($1, $2, $3, $4, $5, $6)
                RETURNING id, poll_id, name, avatar_url, description, user_id,
                          vote_count, position, created_at, is_deleted
                "#,
            )
            .bind(poll.id)
            .bind(&input.name)
            .bind(&input.avatar_url)
            .bind(&input.description)
            .bind(input.user_id)
            .bind((idx + 1) as i32)
            .fetch_one(&mut *tx)
            .await?;
            candidates.push(candidate);
        }

        tx.commit().await?;
        Ok((poll, candidates))
    }

    /// Unvote (remove vote) from a poll
    pub async fn unvote(&self, poll_id: Uuid, user_id: Uuid) -> Result<bool> {
        // Get existing vote to find candidate_id
        let vote = sqlx::query_as::<_, PollVote>(
            r#"
            SELECT id, poll_id, candidate_id, user_id, created_at
            FROM poll_votes
            WHERE poll_id = $1 AND user_id = $2
            "#,
        )
        .bind(poll_id)
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?;

        if vote.is_none() {
            return Ok(false);
        }

        // SAFETY: We checked is_none() above and returned early
        let vote = vote.expect("vote checked above");

        // Delete vote and update counts
        let mut tx = self.pool.begin().await?;

        sqlx::query("DELETE FROM poll_votes WHERE id = $1")
            .bind(vote.id)
            .execute(&mut *tx)
            .await?;

        // Decrement candidate vote count
        sqlx::query(
            "UPDATE poll_candidates SET vote_count = vote_count - 1 WHERE id = $1 AND vote_count > 0",
        )
        .bind(vote.candidate_id)
        .execute(&mut *tx)
        .await?;

        // Decrement poll total votes
        sqlx::query(
            "UPDATE polls SET total_votes = total_votes - 1 WHERE id = $1 AND total_votes > 0",
        )
        .bind(poll_id)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(true)
    }

    /// Add a candidate to a poll
    pub async fn add_candidate(
        &self,
        poll_id: Uuid,
        name: String,
        avatar_url: Option<String>,
        description: Option<String>,
        user_id: Option<Uuid>,
    ) -> Result<PollCandidate> {
        let mut tx = self.pool.begin().await?;

        // Get next position
        let next_position: i32 = sqlx::query_scalar(
            "SELECT COALESCE(MAX(position), 0) + 1 FROM poll_candidates WHERE poll_id = $1",
        )
        .bind(poll_id)
        .fetch_one(&mut *tx)
        .await?;

        let candidate = sqlx::query_as::<_, PollCandidate>(
            r#"
            INSERT INTO poll_candidates (poll_id, name, avatar_url, description, user_id, position)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING id, poll_id, name, avatar_url, description, user_id,
                      vote_count, position, created_at, is_deleted
            "#,
        )
        .bind(poll_id)
        .bind(&name)
        .bind(&avatar_url)
        .bind(&description)
        .bind(user_id)
        .bind(next_position)
        .fetch_one(&mut *tx)
        .await?;

        // Update poll candidate count
        sqlx::query("UPDATE polls SET candidate_count = candidate_count + 1 WHERE id = $1")
            .bind(poll_id)
            .execute(&mut *tx)
            .await?;

        tx.commit().await?;
        Ok(candidate)
    }

    /// Remove a candidate from a poll (soft delete)
    pub async fn remove_candidate(&self, poll_id: Uuid, candidate_id: Uuid) -> Result<bool> {
        let mut tx = self.pool.begin().await?;

        let result = sqlx::query(
            "UPDATE poll_candidates SET is_deleted = TRUE WHERE id = $1 AND poll_id = $2 AND is_deleted = FALSE",
        )
        .bind(candidate_id)
        .bind(poll_id)
        .execute(&mut *tx)
        .await?;

        if result.rows_affected() > 0 {
            // Update poll candidate count
            sqlx::query(
                "UPDATE polls SET candidate_count = candidate_count - 1 WHERE id = $1 AND candidate_count > 0",
            )
            .bind(poll_id)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(result.rows_affected() > 0)
    }

    /// Close a poll (set status to 'closed')
    pub async fn close_poll(&self, poll_id: Uuid, creator_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            "UPDATE polls SET status = 'closed', updated_at = NOW() WHERE id = $1 AND creator_id = $2 AND status = 'active'",
        )
        .bind(poll_id)
        .bind(creator_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Delete a poll (soft delete)
    pub async fn delete_poll(&self, poll_id: Uuid, creator_id: Uuid) -> Result<bool> {
        let result = sqlx::query(
            "UPDATE polls SET is_deleted = TRUE, updated_at = NOW() WHERE id = $1 AND creator_id = $2 AND is_deleted = FALSE",
        )
        .bind(poll_id)
        .bind(creator_id)
        .execute(&self.pool)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    /// Get active polls with pagination
    pub async fn get_active_polls(
        &self,
        limit: i32,
        offset: i32,
        tags: Option<Vec<String>>,
    ) -> Result<(Vec<Poll>, i32)> {
        let (polls, total) = if let Some(tags) = tags {
            let polls = sqlx::query_as::<_, Poll>(
                r#"
                SELECT id, title, description, cover_image_url, creator_id, poll_type,
                       status, total_votes, candidate_count, tags, created_at, updated_at,
                       ends_at, is_deleted
                FROM polls
                WHERE status = 'active' AND is_deleted = FALSE AND tags && $1
                ORDER BY created_at DESC
                LIMIT $2 OFFSET $3
                "#,
            )
            .bind(&tags)
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.pool)
            .await?;

            let total: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM polls WHERE status = 'active' AND is_deleted = FALSE AND tags && $1",
            )
            .bind(&tags)
            .fetch_one(&self.pool)
            .await?;

            (polls, total as i32)
        } else {
            let polls = sqlx::query_as::<_, Poll>(
                r#"
                SELECT id, title, description, cover_image_url, creator_id, poll_type,
                       status, total_votes, candidate_count, tags, created_at, updated_at,
                       ends_at, is_deleted
                FROM polls
                WHERE status = 'active' AND is_deleted = FALSE
                ORDER BY created_at DESC
                LIMIT $1 OFFSET $2
                "#,
            )
            .bind(limit)
            .bind(offset)
            .fetch_all(&self.pool)
            .await?;

            let total: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM polls WHERE status = 'active' AND is_deleted = FALSE",
            )
            .fetch_one(&self.pool)
            .await?;

            (polls, total as i32)
        };

        Ok((polls, total))
    }
}

/// Input for creating a candidate
pub struct CreateCandidateInput {
    pub name: String,
    pub avatar_url: Option<String>,
    pub description: Option<String>,
    pub user_id: Option<Uuid>,
}
