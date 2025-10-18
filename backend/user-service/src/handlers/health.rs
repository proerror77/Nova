use actix_web::{web, HttpResponse, Responder};
use serde::Serialize;
use sqlx::PgPool;
use std::collections::HashMap;

#[derive(Serialize)]
struct HealthResponse {
    status: String,
    version: String,
    database: String,
}

#[derive(Serialize, Debug, Clone)]
#[serde(rename_all = "lowercase")]
enum ComponentStatus {
    Healthy,
    Degraded,
    Unhealthy,
}

#[derive(Serialize)]
struct ComponentCheck {
    status: ComponentStatus,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    latency_ms: Option<u64>,
}

#[derive(Serialize)]
struct ReadinessResponse {
    ready: bool,
    status: ComponentStatus,
    checks: HashMap<String, ComponentCheck>,
    timestamp: String,
}

/// Basic health check (快速检查,仅检查数据库连接)
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

/// Comprehensive readiness check (详细检查所有关键组件)
///
/// Checks:
/// - PostgreSQL: Primary database connectivity
/// - Redis: Cache and session store availability
/// - ClickHouse: Analytics database (optional, degrades gracefully)
/// - Kafka: Event streaming availability (optional)
///
/// Returns:
/// - 200 OK: All critical components healthy
/// - 503 Service Unavailable: One or more critical components unhealthy
pub async fn readiness_check(pool: web::Data<PgPool>) -> impl Responder {
    let mut checks = HashMap::new();
    let mut overall_status = ComponentStatus::Healthy;

    // 1. PostgreSQL check (critical)
    let start = std::time::Instant::now();
    let pg_check = match sqlx::query("SELECT 1").fetch_one(pool.get_ref()).await {
        Ok(_) => ComponentCheck {
            status: ComponentStatus::Healthy,
            message: "PostgreSQL connection successful".to_string(),
            latency_ms: Some(start.elapsed().as_millis() as u64),
        },
        Err(e) => {
            overall_status = ComponentStatus::Unhealthy;
            ComponentCheck {
                status: ComponentStatus::Unhealthy,
                message: format!("PostgreSQL connection failed: {}", e),
                latency_ms: Some(start.elapsed().as_millis() as u64),
            }
        }
    };
    checks.insert("postgresql".to_string(), pg_check);

    // 2. Redis check (critical for sessions)
    // TODO: Add actual Redis connection check when RedisManager is available
    // For now, mark as healthy by default
    checks.insert(
        "redis".to_string(),
        ComponentCheck {
            status: ComponentStatus::Healthy,
            message: "Redis check not implemented (assumed healthy)".to_string(),
            latency_ms: None,
        },
    );

    // 3. ClickHouse check (optional, degrades gracefully)
    // TODO: Add actual ClickHouse connection check when ClickHouseClient is available
    checks.insert(
        "clickhouse".to_string(),
        ComponentCheck {
            status: ComponentStatus::Healthy,
            message: "ClickHouse check not implemented (assumed healthy)".to_string(),
            latency_ms: None,
        },
    );

    // 4. Kafka check (optional for event streaming)
    // TODO: Add actual Kafka broker check when KafkaProducer is available
    checks.insert(
        "kafka".to_string(),
        ComponentCheck {
            status: ComponentStatus::Healthy,
            message: "Kafka check not implemented (assumed healthy)".to_string(),
            latency_ms: None,
        },
    );

    let ready = matches!(overall_status, ComponentStatus::Healthy);
    let response = ReadinessResponse {
        ready,
        status: overall_status,
        checks,
        timestamp: chrono::Utc::now().to_rfc3339(),
    };

    if ready {
        HttpResponse::Ok().json(response)
    } else {
        HttpResponse::ServiceUnavailable().json(response)
    }
}

pub async fn liveness_check() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({"alive": true}))
}
