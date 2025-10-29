/// Experiments API handlers - A/B testing endpoints
use crate::db::experiment_repo::{CreateExperimentRequest, ExperimentStatus};
use crate::services::experiments::{
    AssignmentError, AssignmentService, ExperimentError, ExperimentService, MetricsError,
    MetricsService,
};
use actix_web::{web, HttpResponse, Responder};
use serde::Deserialize;
use std::sync::Arc;
use uuid::Uuid;

/// State containing experiment services
pub struct ExperimentState {
    pub experiment_service: Arc<ExperimentService>,
    pub assignment_service: Arc<AssignmentService>,
    pub metrics_service: Arc<MetricsService>,
}

/// POST /api/v1/experiments - Create new experiment
#[tracing::instrument(skip(state))]
pub async fn create_experiment(
    state: web::Data<Arc<ExperimentState>>,
    req: web::Json<CreateExperimentRequest>,
) -> impl Responder {
    match state
        .experiment_service
        .create_experiment(req.into_inner())
        .await
    {
        Ok(experiment) => {
            tracing::info!(
                "Created experiment: {} ({})",
                experiment.name,
                experiment.id
            );
            HttpResponse::Created().json(experiment)
        }
        Err(ExperimentError::DuplicateName(name)) => {
            HttpResponse::Conflict().json(serde_json::json!({
                "error": "Experiment name already exists",
                "name": name
            }))
        }
        Err(ExperimentError::ValidationError(msg)) => {
            HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Validation failed",
                "message": msg
            }))
        }
        Err(e) => {
            tracing::error!("Failed to create experiment: {:?}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Internal server error"
            }))
        }
    }
}

/// GET /api/v1/experiments/{id} - Get experiment details
#[tracing::instrument(skip(state))]
pub async fn get_experiment(
    state: web::Data<Arc<ExperimentState>>,
    path: web::Path<Uuid>,
) -> impl Responder {
    let experiment_id = path.into_inner();

    match state.experiment_service.get_experiment(experiment_id).await {
        Ok(experiment) => HttpResponse::Ok().json(experiment),
        Err(ExperimentError::NotFound(_)) => HttpResponse::NotFound().json(serde_json::json!({
            "error": "Experiment not found"
        })),
        Err(e) => {
            tracing::error!("Failed to get experiment: {:?}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Internal server error"
            }))
        }
    }
}

/// GET /api/v1/experiments - List all experiments
#[tracing::instrument(skip(state))]
pub async fn list_experiments(
    state: web::Data<Arc<ExperimentState>>,
    query: web::Query<ListExperimentsQuery>,
) -> impl Responder {
    let result = if let Some(status_str) = &query.status {
        // Parse status
        let status = match status_str.to_lowercase().as_str() {
            "draft" => ExperimentStatus::Draft,
            "running" => ExperimentStatus::Running,
            "completed" => ExperimentStatus::Completed,
            "cancelled" => ExperimentStatus::Cancelled,
            _ => {
                return HttpResponse::BadRequest().json(serde_json::json!({
                    "error": "Invalid status",
                    "valid_values": ["draft", "running", "completed", "cancelled"]
                }));
            }
        };

        state.experiment_service.list_by_status(status).await
    } else {
        state.experiment_service.list_experiments().await
    };

    match result {
        Ok(experiments) => HttpResponse::Ok().json(experiments),
        Err(e) => {
            tracing::error!("Failed to list experiments: {:?}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Internal server error"
            }))
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct ListExperimentsQuery {
    pub status: Option<String>,
}

/// POST /api/v1/experiments/{id}/start - Start experiment
#[tracing::instrument(skip(state))]
pub async fn start_experiment(
    state: web::Data<Arc<ExperimentState>>,
    path: web::Path<Uuid>,
) -> impl Responder {
    let experiment_id = path.into_inner();

    match state
        .experiment_service
        .start_experiment(experiment_id)
        .await
    {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({
            "message": "Experiment started",
            "experiment_id": experiment_id
        })),
        Err(ExperimentError::NotFound(_)) => HttpResponse::NotFound().json(serde_json::json!({
            "error": "Experiment not found"
        })),
        Err(ExperimentError::InvalidStateTransition { from, to }) => HttpResponse::BadRequest()
            .json(serde_json::json!({
                "error": "Invalid state transition",
                "from": from,
                "to": to
            })),
        Err(e) => {
            tracing::error!("Failed to start experiment: {:?}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Internal server error"
            }))
        }
    }
}

/// POST /api/v1/experiments/{id}/stop - Stop experiment
#[tracing::instrument(skip(state))]
pub async fn stop_experiment(
    state: web::Data<Arc<ExperimentState>>,
    path: web::Path<Uuid>,
) -> impl Responder {
    let experiment_id = path.into_inner();

    match state
        .experiment_service
        .stop_experiment(experiment_id)
        .await
    {
        Ok(_) => {
            // Invalidate assignment cache
            let _ = state
                .assignment_service
                .invalidate_experiment_cache(experiment_id)
                .await;

            HttpResponse::Ok().json(serde_json::json!({
                "message": "Experiment stopped",
                "experiment_id": experiment_id
            }))
        }
        Err(ExperimentError::NotFound(_)) => HttpResponse::NotFound().json(serde_json::json!({
            "error": "Experiment not found"
        })),
        Err(ExperimentError::InvalidStateTransition { from, to }) => HttpResponse::BadRequest()
            .json(serde_json::json!({
                "error": "Invalid state transition",
                "from": from,
                "to": to
            })),
        Err(e) => {
            tracing::error!("Failed to stop experiment: {:?}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Internal server error"
            }))
        }
    }
}

/// GET /api/v1/experiments/{id}/assign - Assign user to variant
#[tracing::instrument(skip(state))]
pub async fn assign_variant(
    state: web::Data<Arc<ExperimentState>>,
    path: web::Path<Uuid>,
    query: web::Query<AssignQuery>,
) -> impl Responder {
    let experiment_id = path.into_inner();
    let user_id = query.user_id;

    match state
        .assignment_service
        .assign_variant(experiment_id, user_id)
        .await
    {
        Ok(assignment) => HttpResponse::Ok().json(assignment),
        Err(AssignmentError::ExperimentNotFound(_)) => {
            HttpResponse::NotFound().json(serde_json::json!({
                "error": "Experiment not found"
            }))
        }
        Err(AssignmentError::ExperimentNotRunning(_)) => {
            HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Experiment is not running"
            }))
        }
        Err(AssignmentError::UserNotSampled) => HttpResponse::Ok().json(serde_json::json!({
            "message": "User not in sample",
            "experiment_id": experiment_id,
            "user_id": user_id,
            "assigned": false
        })),
        Err(e) => {
            tracing::error!("Failed to assign variant: {:?}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Internal server error"
            }))
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct AssignQuery {
    pub user_id: Uuid,
}

/// POST /api/v1/experiments/{id}/metrics - Record metric
#[tracing::instrument(skip(state))]
pub async fn record_metric(
    state: web::Data<Arc<ExperimentState>>,
    path: web::Path<Uuid>,
    req: web::Json<RecordMetricRequest>,
) -> impl Responder {
    let experiment_id = path.into_inner();

    match state
        .metrics_service
        .record_metric(
            experiment_id,
            req.user_id,
            req.variant_id,
            &req.metric_name,
            req.metric_value,
        )
        .await
    {
        Ok(_) => HttpResponse::Accepted().json(serde_json::json!({
            "message": "Metric recorded",
            "experiment_id": experiment_id,
            "metric_name": req.metric_name
        })),
        Err(e) => {
            tracing::error!("Failed to record metric: {:?}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Internal server error"
            }))
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct RecordMetricRequest {
    pub user_id: Uuid,
    pub variant_id: Option<Uuid>,
    pub metric_name: String,
    pub metric_value: f64,
}

/// GET /api/v1/experiments/{id}/results - Get experiment results
#[tracing::instrument(skip(state))]
pub async fn get_results(
    state: web::Data<Arc<ExperimentState>>,
    path: web::Path<Uuid>,
) -> impl Responder {
    let experiment_id = path.into_inner();

    match state
        .metrics_service
        .get_experiment_results(experiment_id)
        .await
    {
        Ok(results) => HttpResponse::Ok().json(results),
        Err(MetricsError::ExperimentNotFound(_)) => {
            HttpResponse::NotFound().json(serde_json::json!({
                "error": "Experiment not found"
            }))
        }
        Err(e) => {
            tracing::error!("Failed to get results: {:?}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Internal server error"
            }))
        }
    }
}

/// POST /api/v1/experiments/{id}/refresh-cache - Refresh results cache
#[tracing::instrument(skip(state))]
pub async fn refresh_cache(
    state: web::Data<Arc<ExperimentState>>,
    path: web::Path<Uuid>,
) -> impl Responder {
    let experiment_id = path.into_inner();

    match state
        .metrics_service
        .refresh_results_cache(experiment_id)
        .await
    {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({
            "message": "Results cache refreshed",
            "experiment_id": experiment_id
        })),
        Err(e) => {
            tracing::error!("Failed to refresh cache: {:?}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Internal server error"
            }))
        }
    }
}

/// Configure experiment routes
pub fn configure(cfg: &mut web::ServiceConfig) {
    cfg.service(
        web::scope("/api/v1/experiments")
            .route("", web::post().to(create_experiment))
            .route("", web::get().to(list_experiments))
            .route("/{id}", web::get().to(get_experiment))
            .route("/{id}/start", web::post().to(start_experiment))
            .route("/{id}/stop", web::post().to(stop_experiment))
            .route("/{id}/assign", web::get().to(assign_variant))
            .route("/{id}/metrics", web::post().to(record_metric))
            .route("/{id}/results", web::get().to(get_results))
            .route("/{id}/refresh-cache", web::post().to(refresh_cache)),
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_record_metric_request_deserialize() {
        let json = r#"{
            "user_id": "123e4567-e89b-12d3-a456-426614174000",
            "variant_id": "123e4567-e89b-12d3-a456-426614174001",
            "metric_name": "click_rate",
            "metric_value": 0.75
        }"#;

        let req: RecordMetricRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.metric_name, "click_rate");
        assert_eq!(req.metric_value, 0.75);
    }

    #[test]
    fn test_assign_query_deserialize() {
        let query = r#"{"user_id":"123e4567-e89b-12d3-a456-426614174000"}"#;
        let parsed: AssignQuery = serde_json::from_str(query).unwrap();
        assert_eq!(
            parsed.user_id.to_string(),
            "123e4567-e89b-12d3-a456-426614174000"
        );
    }
}
