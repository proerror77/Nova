/// Experiment repository - handles all database operations for A/B testing
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use uuid::Uuid;

/// Experiment status enum
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "experiment_status", rename_all = "lowercase")]
pub enum ExperimentStatus {
    Draft,
    Running,
    Completed,
    Cancelled,
}

/// Experiment entity
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Experiment {
    pub id: Uuid,
    pub name: String,
    pub description: Option<String>,
    pub status: ExperimentStatus,
    pub start_date: Option<DateTime<Utc>>,
    pub end_date: Option<DateTime<Utc>>,
    pub stratification_key: String,
    pub sample_size: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub created_by: Option<Uuid>,
}

/// Experiment variant entity
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ExperimentVariant {
    pub id: Uuid,
    pub experiment_id: Uuid,
    pub variant_name: String,
    pub variant_config: serde_json::Value,
    pub traffic_allocation: i32,
    pub created_at: DateTime<Utc>,
}

/// User assignment entity
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ExperimentAssignment {
    pub id: Uuid,
    pub experiment_id: Uuid,
    pub user_id: Uuid,
    pub variant_id: Uuid,
    pub assigned_at: DateTime<Utc>,
}

/// Metric event entity
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ExperimentMetric {
    pub id: Uuid,
    pub experiment_id: Uuid,
    pub user_id: Uuid,
    pub variant_id: Option<Uuid>,
    pub metric_name: String,
    pub metric_value: f64,
    pub recorded_at: DateTime<Utc>,
}

/// Aggregated results cache
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct ExperimentResultsCache {
    pub id: Uuid,
    pub experiment_id: Uuid,
    pub variant_id: Uuid,
    pub metric_name: String,
    pub sample_size: i64,
    pub metric_sum: f64,
    pub metric_mean: f64,
    pub metric_variance: Option<f64>,
    pub metric_std_dev: Option<f64>,
    pub last_updated: DateTime<Utc>,
}

/// Create experiment request
#[derive(Debug, Clone, Deserialize)]
pub struct CreateExperimentRequest {
    pub name: String,
    pub description: Option<String>,
    pub stratification_key: String,
    pub sample_size: i32,
    pub variants: Vec<CreateVariantRequest>,
    pub created_by: Option<Uuid>,
}

/// Create variant request
#[derive(Debug, Clone, Deserialize)]
pub struct CreateVariantRequest {
    pub name: String,
    pub config: serde_json::Value,
    pub traffic: i32,
}

/// Create a new experiment with variants (transactional)
pub async fn create_experiment(
    pool: &PgPool,
    req: CreateExperimentRequest,
) -> Result<Experiment, sqlx::Error> {
    // Start transaction
    let mut tx = pool.begin().await?;

    // Insert experiment
    let experiment = sqlx::query_as::<_, Experiment>(
        r#"
        INSERT INTO experiments (name, description, stratification_key, sample_size, created_by, status)
        VALUES ($1, $2, $3, $4, $5, 'draft')
        RETURNING id, name, description, status, start_date, end_date, stratification_key,
                  sample_size, created_at, updated_at, created_by
        "#,
    )
    .bind(&req.name)
    .bind(&req.description)
    .bind(&req.stratification_key)
    .bind(req.sample_size)
    .bind(req.created_by)
    .fetch_one(&mut *tx)
    .await?;

    // Insert variants
    for variant_req in req.variants {
        sqlx::query(
            r#"
            INSERT INTO experiment_variants (experiment_id, variant_name, variant_config, traffic_allocation)
            VALUES ($1, $2, $3, $4)
            "#,
        )
        .bind(experiment.id)
        .bind(&variant_req.name)
        .bind(&variant_req.config)
        .bind(variant_req.traffic)
        .execute(&mut *tx)
        .await?;
    }

    tx.commit().await?;

    Ok(experiment)
}

/// Get experiment by ID
pub async fn get_experiment(pool: &PgPool, id: Uuid) -> Result<Option<Experiment>, sqlx::Error> {
    sqlx::query_as::<_, Experiment>(
        r#"
        SELECT id, name, description, status, start_date, end_date, stratification_key,
               sample_size, created_at, updated_at, created_by
        FROM experiments
        WHERE id = $1
        "#,
    )
    .bind(id)
    .fetch_optional(pool)
    .await
}

/// Get experiment by name
pub async fn get_experiment_by_name(
    pool: &PgPool,
    name: &str,
) -> Result<Option<Experiment>, sqlx::Error> {
    sqlx::query_as::<_, Experiment>(
        r#"
        SELECT id, name, description, status, start_date, end_date, stratification_key,
               sample_size, created_at, updated_at, created_by
        FROM experiments
        WHERE name = $1
        "#,
    )
    .bind(name)
    .fetch_optional(pool)
    .await
}

/// List all experiments
pub async fn list_experiments(pool: &PgPool) -> Result<Vec<Experiment>, sqlx::Error> {
    sqlx::query_as::<_, Experiment>(
        r#"
        SELECT id, name, description, status, start_date, end_date, stratification_key,
               sample_size, created_at, updated_at, created_by
        FROM experiments
        ORDER BY created_at DESC
        "#,
    )
    .fetch_all(pool)
    .await
}

/// List experiments by status
pub async fn list_experiments_by_status(
    pool: &PgPool,
    status: ExperimentStatus,
) -> Result<Vec<Experiment>, sqlx::Error> {
    sqlx::query_as::<_, Experiment>(
        r#"
        SELECT id, name, description, status, start_date, end_date, stratification_key,
               sample_size, created_at, updated_at, created_by
        FROM experiments
        WHERE status = $1
        ORDER BY created_at DESC
        "#,
    )
    .bind(status)
    .fetch_all(pool)
    .await
}

/// Update experiment status
pub async fn update_experiment_status(
    pool: &PgPool,
    id: Uuid,
    status: ExperimentStatus,
) -> Result<(), sqlx::Error> {
    let now = Utc::now();

    sqlx::query(
        r#"
        UPDATE experiments
        SET status = $1,
            start_date = CASE WHEN $1 = 'running' AND start_date IS NULL THEN $2 ELSE start_date END,
            end_date = CASE WHEN $1 IN ('completed', 'cancelled') AND end_date IS NULL THEN $2 ELSE end_date END
        WHERE id = $3
        "#,
    )
    .bind(status)
    .bind(now)
    .bind(id)
    .execute(pool)
    .await?;

    Ok(())
}

/// Get all variants for an experiment
pub async fn get_experiment_variants(
    pool: &PgPool,
    experiment_id: Uuid,
) -> Result<Vec<ExperimentVariant>, sqlx::Error> {
    sqlx::query_as::<_, ExperimentVariant>(
        r#"
        SELECT id, experiment_id, variant_name, variant_config, traffic_allocation, created_at
        FROM experiment_variants
        WHERE experiment_id = $1
        ORDER BY created_at
        "#,
    )
    .bind(experiment_id)
    .fetch_all(pool)
    .await
}

/// Get variant by ID
pub async fn get_variant(
    pool: &PgPool,
    variant_id: Uuid,
) -> Result<Option<ExperimentVariant>, sqlx::Error> {
    sqlx::query_as::<_, ExperimentVariant>(
        r#"
        SELECT id, experiment_id, variant_name, variant_config, traffic_allocation, created_at
        FROM experiment_variants
        WHERE id = $1
        "#,
    )
    .bind(variant_id)
    .fetch_optional(pool)
    .await
}

/// Create assignment (idempotent via UNIQUE constraint)
pub async fn create_assignment(
    pool: &PgPool,
    experiment_id: Uuid,
    user_id: Uuid,
    variant_id: Uuid,
) -> Result<ExperimentAssignment, sqlx::Error> {
    sqlx::query_as::<_, ExperimentAssignment>(
        r#"
        INSERT INTO experiment_assignments (experiment_id, user_id, variant_id)
        VALUES ($1, $2, $3)
        ON CONFLICT (experiment_id, user_id) DO UPDATE
        SET variant_id = EXCLUDED.variant_id
        RETURNING id, experiment_id, user_id, variant_id, assigned_at
        "#,
    )
    .bind(experiment_id)
    .bind(user_id)
    .bind(variant_id)
    .fetch_one(pool)
    .await
}

/// Get existing assignment
pub async fn get_assignment(
    pool: &PgPool,
    experiment_id: Uuid,
    user_id: Uuid,
) -> Result<Option<ExperimentAssignment>, sqlx::Error> {
    sqlx::query_as::<_, ExperimentAssignment>(
        r#"
        SELECT id, experiment_id, user_id, variant_id, assigned_at
        FROM experiment_assignments
        WHERE experiment_id = $1 AND user_id = $2
        "#,
    )
    .bind(experiment_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await
}

/// Record metric event
pub async fn record_metric(
    pool: &PgPool,
    experiment_id: Uuid,
    user_id: Uuid,
    variant_id: Option<Uuid>,
    metric_name: &str,
    metric_value: f64,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO experiment_metrics (experiment_id, user_id, variant_id, metric_name, metric_value)
        VALUES ($1, $2, $3, $4, $5)
        "#,
    )
    .bind(experiment_id)
    .bind(user_id)
    .bind(variant_id)
    .bind(metric_name)
    .bind(metric_value)
    .execute(pool)
    .await?;

    Ok(())
}

/// Get aggregated metrics for experiment (group by variant)
pub async fn get_experiment_metrics_aggregated(
    pool: &PgPool,
    experiment_id: Uuid,
) -> Result<Vec<AggregatedMetric>, sqlx::Error> {
    sqlx::query_as::<_, AggregatedMetric>(
        r#"
        SELECT
            v.id AS variant_id,
            v.variant_name,
            m.metric_name,
            COUNT(*) AS sample_size,
            SUM(m.metric_value) AS metric_sum,
            AVG(m.metric_value) AS metric_mean,
            VARIANCE(m.metric_value) AS metric_variance,
            STDDEV(m.metric_value) AS metric_std_dev
        FROM experiment_metrics m
        JOIN experiment_variants v ON m.variant_id = v.id
        WHERE m.experiment_id = $1
        GROUP BY v.id, v.variant_name, m.metric_name
        ORDER BY v.variant_name, m.metric_name
        "#,
    )
    .bind(experiment_id)
    .fetch_all(pool)
    .await
}

/// Aggregated metric result
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct AggregatedMetric {
    pub variant_id: Uuid,
    pub variant_name: String,
    pub metric_name: String,
    pub sample_size: i64,
    pub metric_sum: Option<f64>,
    pub metric_mean: Option<f64>,
    pub metric_variance: Option<f64>,
    pub metric_std_dev: Option<f64>,
}

/// Upsert aggregated results cache
pub async fn upsert_results_cache(
    pool: &PgPool,
    experiment_id: Uuid,
    variant_id: Uuid,
    metric_name: &str,
    sample_size: i64,
    metric_sum: f64,
    metric_mean: f64,
    metric_variance: Option<f64>,
    metric_std_dev: Option<f64>,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        INSERT INTO experiment_results_cache
            (experiment_id, variant_id, metric_name, sample_size, metric_sum, metric_mean, metric_variance, metric_std_dev)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ON CONFLICT (experiment_id, variant_id, metric_name) DO UPDATE
        SET sample_size = EXCLUDED.sample_size,
            metric_sum = EXCLUDED.metric_sum,
            metric_mean = EXCLUDED.metric_mean,
            metric_variance = EXCLUDED.metric_variance,
            metric_std_dev = EXCLUDED.metric_std_dev,
            last_updated = NOW()
        "#,
    )
    .bind(experiment_id)
    .bind(variant_id)
    .bind(metric_name)
    .bind(sample_size)
    .bind(metric_sum)
    .bind(metric_mean)
    .bind(metric_variance)
    .bind(metric_std_dev)
    .execute(pool)
    .await?;

    Ok(())
}

/// Get cached results for experiment
pub async fn get_cached_results(
    pool: &PgPool,
    experiment_id: Uuid,
) -> Result<Vec<ExperimentResultsCache>, sqlx::Error> {
    sqlx::query_as::<_, ExperimentResultsCache>(
        r#"
        SELECT id, experiment_id, variant_id, metric_name, sample_size,
               metric_sum, metric_mean, metric_variance, metric_std_dev, last_updated
        FROM experiment_results_cache
        WHERE experiment_id = $1
        ORDER BY variant_id, metric_name
        "#,
    )
    .bind(experiment_id)
    .fetch_all(pool)
    .await
}

/// Count active experiments for user (prevent concurrent enrollment)
pub async fn count_active_experiments_for_user(
    pool: &PgPool,
    user_id: Uuid,
) -> Result<i64, sqlx::Error> {
    let result = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(DISTINCT a.experiment_id)
        FROM experiment_assignments a
        JOIN experiments e ON a.experiment_id = e.id
        WHERE a.user_id = $1 AND e.status = 'running'
        "#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await?;

    Ok(result)
}
