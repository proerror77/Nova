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
    pub async fn get_trending_polls(&self, limit: i32, tags: Option<Vec<String>>) -> Result<Vec<Poll>> {
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
    pub async fn get_top_candidates(&self, poll_id: Uuid, limit: i32) -> Result<Vec<CandidatePreview>> {
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
    pub async fn vote(
        &self,
        poll_id: Uuid,
        candidate_id: Uuid,
        user_id: Uuid,
    ) -> Result<PollVote> {
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
}
