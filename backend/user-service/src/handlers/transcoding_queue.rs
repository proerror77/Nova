use crate::db::video_repo;
use crate::error::AppError;
use actix_web::{web, HttpResponse};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

/// Queue statistics response
#[derive(Debug, Serialize)]
pub struct QueueStatsResponse {
    pub total_jobs: i64,
    pub by_status: StatusCounts,
    pub jobs: Vec<JobInfo>,
    pub average_wait_time_seconds: Option<f64>,
    pub average_process_time_seconds: Option<f64>,
}

#[derive(Debug, Serialize)]
pub struct StatusCounts {
    pub pending: i64,
    pub processing: i64,
    pub failed: i64,
    pub published: i64,
}

#[derive(Debug, Serialize)]
pub struct JobInfo {
    pub video_id: Uuid,
    pub status: String,
    pub priority: i32,
    pub estimated_time_remaining: Option<i32>,
    pub current_stage: Option<String>,
    pub retry_count: i32,
    pub error_message: Option<String>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Deserialize)]
pub struct QueueQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
}

/// Get transcoding queue status and statistics
///
/// GET /api/v1/transcoding/queue?status=processing&limit=50
pub async fn get_queue_status(
    pool: web::Data<PgPool>,
    query: web::Query<QueueQuery>,
) -> Result<HttpResponse, AppError> {
    let status_filter = query.status.as_deref();
    let limit = query.limit.unwrap_or(50).min(200);

    // Get status counts
    let counts = sqlx::query_as::<_, (i64, i64, i64, i64)>(
        r#"
        SELECT
            COUNT(*) FILTER (WHERE transcoding_status = 'pending') AS pending,
            COUNT(*) FILTER (WHERE transcoding_status = 'processing') AS processing,
            COUNT(*) FILTER (WHERE transcoding_status = 'failed') AS failed,
            COUNT(*) FILTER (WHERE transcoding_status = 'published') AS published
        FROM videos
        WHERE deleted_at IS NULL
        "#,
    )
    .fetch_one(pool.as_ref())
    .await
    .map_err(|e| AppError::Internal(format!("Failed to fetch queue stats: {}", e)))?;

    let by_status = StatusCounts {
        pending: counts.0,
        processing: counts.1,
        failed: counts.2,
        published: counts.3,
    };

    let total_jobs = counts.0 + counts.1 + counts.2 + counts.3;

    // Get jobs with optional status filter
    let jobs_query = if let Some(status) = status_filter {
        sqlx::query_as::<
            _,
            (
                Uuid,
                String,
                i32,
                Option<i32>,
                Option<String>,
                i32,
                Option<String>,
                chrono::DateTime<chrono::Utc>,
            ),
        >(
            r#"
            SELECT
                id,
                transcoding_status,
                COALESCE(transcoding_priority, 5) AS priority,
                transcoding_estimated_remaining_seconds,
                transcoding_current_stage,
                COALESCE(transcoding_retry_count, 0) AS retry_count,
                transcoding_error_message,
                created_at
            FROM videos
            WHERE deleted_at IS NULL
              AND transcoding_status = $1
            ORDER BY transcoding_priority DESC, created_at ASC
            LIMIT $2
            "#,
        )
        .bind(status)
        .bind(limit)
        .fetch_all(pool.as_ref())
        .await
    } else {
        sqlx::query_as::<
            _,
            (
                Uuid,
                String,
                i32,
                Option<i32>,
                Option<String>,
                i32,
                Option<String>,
                chrono::DateTime<chrono::Utc>,
            ),
        >(
            r#"
            SELECT
                id,
                transcoding_status,
                COALESCE(transcoding_priority, 5) AS priority,
                transcoding_estimated_remaining_seconds,
                transcoding_current_stage,
                COALESCE(transcoding_retry_count, 0) AS retry_count,
                transcoding_error_message,
                created_at
            FROM videos
            WHERE deleted_at IS NULL
              AND transcoding_status IN ('pending', 'processing', 'failed')
            ORDER BY transcoding_priority DESC, created_at ASC
            LIMIT $1
            "#,
        )
        .bind(limit)
        .fetch_all(pool.as_ref())
        .await
    }
    .map_err(|e| AppError::Internal(format!("Failed to fetch jobs: {}", e)))?;

    let jobs = jobs_query
        .into_iter()
        .map(|row| JobInfo {
            video_id: row.0,
            status: row.1,
            priority: row.2,
            estimated_time_remaining: row.3,
            current_stage: row.4,
            retry_count: row.5,
            error_message: row.6,
            created_at: row.7,
        })
        .collect();

    // Calculate average wait time (for pending jobs)
    let avg_wait_time = sqlx::query_scalar::<_, Option<f64>>(
        r#"
        SELECT AVG(EXTRACT(EPOCH FROM (NOW() - created_at)))
        FROM videos
        WHERE deleted_at IS NULL
          AND transcoding_status = 'pending'
        "#,
    )
    .fetch_one(pool.as_ref())
    .await
    .ok()
    .flatten();

    // Calculate average process time (for completed jobs in last 24h)
    let avg_process_time = sqlx::query_scalar::<_, Option<f64>>(
        r#"
        SELECT AVG(EXTRACT(EPOCH FROM (updated_at - created_at)))
        FROM videos
        WHERE deleted_at IS NULL
          AND transcoding_status = 'published'
          AND updated_at > NOW() - INTERVAL '24 hours'
        "#,
    )
    .fetch_one(pool.as_ref())
    .await
    .ok()
    .flatten();

    Ok(HttpResponse::Ok().json(QueueStatsResponse {
        total_jobs,
        by_status,
        jobs,
        average_wait_time_seconds: avg_wait_time,
        average_process_time_seconds: avg_process_time,
    }))
}

#[derive(Debug, Deserialize)]
pub struct RetryRequest {
    pub priority: Option<i32>,
}

/// Retry a failed transcoding job
///
/// POST /api/v1/transcoding/jobs/{video_id}/retry
pub async fn retry_job(
    pool: web::Data<PgPool>,
    path: web::Path<Uuid>,
    body: web::Json<RetryRequest>,
) -> Result<HttpResponse, AppError> {
    let video_id = path.into_inner();
    let priority = body.priority.unwrap_or(5).clamp(1, 10);

    // Verify video exists and is in failed state
    let video = video_repo::get_video(pool.as_ref(), video_id)
        .await?
        .ok_or_else(|| AppError::NotFound("Video not found".into()))?;

    let transcoding_status = video.transcoding_status.as_deref().unwrap_or("unknown");
    if transcoding_status != "failed" {
        return Err(AppError::BadRequest("Video is not in failed state".into()));
    }

    // Reset transcoding state for retry
    sqlx::query(
        r#"
        UPDATE videos
        SET
            transcoding_status = 'pending',
            transcoding_priority = $2,
            transcoding_retry_count = COALESCE(transcoding_retry_count, 0) + 1,
            transcoding_last_retry_at = NOW(),
            transcoding_error_message = NULL,
            transcoding_progress_percent = 0,
            updated_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(video_id)
    .bind(priority)
    .execute(pool.as_ref())
    .await
    .map_err(|e| AppError::Internal(format!("Failed to retry job: {}", e)))?;

    tracing::info!(
        "Retry scheduled for video {} with priority {}",
        video_id,
        priority
    );

    let next_retry_attempt = video.transcoding_retry_count.unwrap_or(0) + 1;
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "status": "queued",
        "retry_attempt": next_retry_attempt,
        "priority": priority
    })))
}
