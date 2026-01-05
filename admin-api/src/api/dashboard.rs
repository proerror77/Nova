use axum::{
    extract::State,
    routing::get,
    Json, Router,
};
use serde::Serialize;

use crate::error::Result;
use crate::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/stats", get(get_stats))
        .route("/charts/users", get(get_user_chart))
        .route("/charts/content", get(get_content_chart))
        .route("/risks", get(get_risk_alerts))
}

#[derive(Debug, Serialize)]
pub struct DashboardStats {
    pub total_users: i64,
    pub active_users_today: i64,
    pub new_users_today: i64,
    pub pending_reviews: i64,
    pub reports_today: i64,
    pub revenue_today: f64,
}

async fn get_stats(
    State(_state): State<AppState>,
) -> Result<Json<DashboardStats>> {
    // TODO: Query real statistics from database/ClickHouse

    Ok(Json(DashboardStats {
        total_users: 125_000,
        active_users_today: 8_500,
        new_users_today: 320,
        pending_reviews: 45,
        reports_today: 12,
        revenue_today: 15_800.50,
    }))
}

#[derive(Debug, Serialize)]
pub struct ChartDataPoint {
    pub date: String,
    pub value: i64,
}

async fn get_user_chart(
    State(_state): State<AppState>,
) -> Result<Json<Vec<ChartDataPoint>>> {
    // TODO: Query real chart data

    Ok(Json(vec![
        ChartDataPoint { date: "2024-01-01".to_string(), value: 1200 },
        ChartDataPoint { date: "2024-01-02".to_string(), value: 1350 },
        ChartDataPoint { date: "2024-01-03".to_string(), value: 1100 },
    ]))
}

async fn get_content_chart(
    State(_state): State<AppState>,
) -> Result<Json<Vec<ChartDataPoint>>> {
    // TODO: Query real chart data

    Ok(Json(vec![
        ChartDataPoint { date: "2024-01-01".to_string(), value: 450 },
        ChartDataPoint { date: "2024-01-02".to_string(), value: 520 },
        ChartDataPoint { date: "2024-01-03".to_string(), value: 380 },
    ]))
}

#[derive(Debug, Serialize)]
pub struct RiskAlert {
    pub id: String,
    pub level: String,
    pub title: String,
    pub description: String,
    pub created_at: String,
}

async fn get_risk_alerts(
    State(_state): State<AppState>,
) -> Result<Json<Vec<RiskAlert>>> {
    // TODO: Query real risk alerts

    Ok(Json(vec![
        RiskAlert {
            id: "1".to_string(),
            level: "high".to_string(),
            title: "异常登录行为".to_string(),
            description: "检测到 15 个账号在短时间内从不同地区登录".to_string(),
            created_at: "2024-01-15T10:30:00Z".to_string(),
        },
    ]))
}
