use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};

use crate::error::Result;
use crate::services::DashboardService;
use crate::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/stats", get(get_stats))
        .route("/charts/users", get(get_user_chart))
        .route("/charts/activity", get(get_activity_chart))
        .route("/activity", get(get_recent_activity))
        .route("/risks", get(get_risk_alerts))
}

async fn get_stats(
    State(state): State<AppState>,
) -> Result<Json<crate::services::DashboardStats>> {
    let dashboard_service = DashboardService::new(state.db.clone());
    let stats = dashboard_service.get_stats().await?;
    Ok(Json(stats))
}

#[derive(Debug, Deserialize)]
pub struct ChartQuery {
    #[serde(default = "default_days")]
    pub days: i32,
}

fn default_days() -> i32 {
    7
}

async fn get_user_chart(
    State(state): State<AppState>,
    Query(query): Query<ChartQuery>,
) -> Result<Json<Vec<crate::services::ChartDataPoint>>> {
    let days = query.days.min(30).max(1);
    let dashboard_service = DashboardService::new(state.db.clone());
    let data = dashboard_service.get_user_chart(days).await?;
    Ok(Json(data))
}

async fn get_activity_chart(
    State(state): State<AppState>,
    Query(query): Query<ChartQuery>,
) -> Result<Json<Vec<crate::services::ChartDataPoint>>> {
    let days = query.days.min(30).max(1);
    let dashboard_service = DashboardService::new(state.db.clone());
    let data = dashboard_service.get_activity_chart(days).await?;
    Ok(Json(data))
}

#[derive(Debug, Deserialize)]
pub struct ActivityQuery {
    #[serde(default = "default_limit")]
    pub limit: i64,
}

fn default_limit() -> i64 {
    20
}

async fn get_recent_activity(
    State(state): State<AppState>,
    Query(query): Query<ActivityQuery>,
) -> Result<Json<Vec<crate::services::RecentActivity>>> {
    let limit = query.limit.min(100).max(1);
    let dashboard_service = DashboardService::new(state.db.clone());
    let activities = dashboard_service.get_recent_activity(limit).await?;
    Ok(Json(activities))
}

#[derive(Debug, Serialize)]
pub struct RiskAlertResponse {
    pub id: String,
    pub level: String,
    pub title: String,
    pub description: String,
    pub user_id: Option<String>,
    pub created_at: String,
}

async fn get_risk_alerts(
    State(state): State<AppState>,
) -> Result<Json<Vec<RiskAlertResponse>>> {
    let dashboard_service = DashboardService::new(state.db.clone());
    let alerts = dashboard_service.get_risk_alerts().await?;

    let response: Vec<RiskAlertResponse> = alerts.into_iter().map(|a| RiskAlertResponse {
        id: a.id,
        level: a.level,
        title: a.title,
        description: a.description,
        user_id: a.user_id,
        created_at: a.created_at.to_rfc3339(),
    }).collect();

    Ok(Json(response))
}
