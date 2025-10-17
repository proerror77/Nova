use actix_web::{web, HttpResponse, Responder};
use serde::Serialize;
use sqlx::PgPool;

#[derive(Serialize)]
struct HealthResponse {
    status: String,
    version: String,
    database: String,
}

pub async fn health_check(pool: web::Data<PgPool>) -> impl Responder {
    let db_status = match sqlx::query("SELECT 1").fetch_one(pool.get_ref()).await {
        Ok(_) => "healthy",
        Err(_) => "unhealthy",
    };

    HttpResponse::Ok().json(HealthResponse {
        status: if db_status == "healthy" {
            "ok"
        } else {
            "degraded"
        }
        .to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        database: db_status.to_string(),
    })
}

pub async fn readiness_check(pool: web::Data<PgPool>) -> impl Responder {
    match sqlx::query("SELECT 1").fetch_one(pool.get_ref()).await {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({"ready": true})),
        Err(_) => HttpResponse::ServiceUnavailable().json(serde_json::json!({"ready": false})),
    }
}

pub async fn liveness_check() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({"alive": true}))
}
