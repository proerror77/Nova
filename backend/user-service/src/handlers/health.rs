use actix_web::{web, HttpResponse, Responder};
use chrono::Utc;
use serde::Serialize;
use sqlx::PgPool;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

use crate::db::ch_client::ClickHouseClient;
use crate::grpc::health::{HealthChecker, HealthStatus};
use crate::services::kafka_producer::EventProducer;
use crate::utils::redis_timeout::run_with_timeout;
use redis_utils::SharedConnectionManager;

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

/// Aggregated state for health/readiness probes
#[derive(Clone)]
pub struct HealthCheckState {
    pub db_pool: PgPool,
    pub redis: SharedConnectionManager,
    pub clickhouse_client: Option<Arc<ClickHouseClient>>,
    pub kafka_producer: Option<Arc<EventProducer>>,
    pub health_checker: Arc<HealthChecker>,
    pub cdc_healthy: Arc<AtomicBool>,
    pub clickhouse_enabled: bool,
    pub cdc_enabled: bool,
}

impl HealthCheckState {
    pub fn new(
        db_pool: PgPool,
        redis: SharedConnectionManager,
        clickhouse_client: Option<Arc<ClickHouseClient>>,
        kafka_producer: Option<Arc<EventProducer>>,
        health_checker: Arc<HealthChecker>,
        cdc_healthy: Arc<AtomicBool>,
        clickhouse_enabled: bool,
        cdc_enabled: bool,
    ) -> Self {
        Self {
            db_pool,
            redis,
            clickhouse_client,
            kafka_producer,
            health_checker,
            cdc_healthy,
            clickhouse_enabled,
            cdc_enabled,
        }
    }

    async fn check_postgres(&self) -> Result<(), sqlx::Error> {
        sqlx::query("SELECT 1")
            .fetch_one(&self.db_pool)
            .await
            .map(|_| ())
    }

    async fn check_redis(&self) -> Result<(), redis::RedisError> {
        let mut conn = self.redis.lock().await.clone();
        let response: String = run_with_timeout(redis::cmd("PING").query_async(&mut conn)).await?;
        if response == "PONG" {
            Ok(())
        } else {
            Err(redis::RedisError::from((
                redis::ErrorKind::ResponseError,
                "unexpected PING response",
            )))
        }
    }

    async fn check_clickhouse(&self) -> Option<Result<(), String>> {
        let client = self.clickhouse_client.clone()?;
        Some(client.health_check().await.map_err(|e| e.to_string()))
    }

    async fn check_kafka(&self) -> Option<Result<(), String>> {
        let producer = self.kafka_producer.clone()?;
        Some(producer.health_check().await.map_err(|e| e.to_string()))
    }
}

/// Basic health check (快速检查,仅检查数据库连接)
pub async fn health_check(state: web::Data<HealthCheckState>) -> impl Responder {
    let database_status = match state.check_postgres().await {
        Ok(_) => "healthy",
        Err(e) => {
            tracing::error!("PostgreSQL health check failed: {}", e);
            "unhealthy"
        }
    };

    HttpResponse::Ok().json(HealthResponse {
        status: if database_status == "healthy" {
            "ok".to_string()
        } else {
            "degraded".to_string()
        },
        version: env!("CARGO_PKG_VERSION").to_string(),
        database: database_status.to_string(),
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
pub async fn readiness_check(state: web::Data<HealthCheckState>) -> impl Responder {
    let mut checks = HashMap::new();
    let mut overall_status = ComponentStatus::Healthy;
    let mut ready = true;
    let mut has_degraded = false;

    // 1. PostgreSQL check (critical)
    let start = Instant::now();
    let pg_result = state.check_postgres().await;
    let pg_latency = Some(start.elapsed().as_millis() as u64);
    let postgres_check = match pg_result {
        Ok(_) => ComponentCheck {
            status: ComponentStatus::Healthy,
            message: "PostgreSQL connection successful".to_string(),
            latency_ms: pg_latency,
        },
        Err(e) => {
            ready = false;
            overall_status = ComponentStatus::Unhealthy;
            ComponentCheck {
                status: ComponentStatus::Unhealthy,
                message: format!("PostgreSQL connection failed: {}", e),
                latency_ms: pg_latency,
            }
        }
    };
    checks.insert("postgresql".to_string(), postgres_check);

    // 2. Redis check (critical for sessions)
    let start = Instant::now();
    let redis_result = state.check_redis().await;
    let redis_latency = Some(start.elapsed().as_millis() as u64);
    let redis_check = match redis_result {
        Ok(_) => ComponentCheck {
            status: ComponentStatus::Healthy,
            message: "Redis ping successful".to_string(),
            latency_ms: redis_latency,
        },
        Err(e) => {
            ready = false;
            overall_status = ComponentStatus::Unhealthy;
            ComponentCheck {
                status: ComponentStatus::Unhealthy,
                message: format!("Redis ping failed: {}", e),
                latency_ms: redis_latency,
            }
        }
    };
    checks.insert("redis".to_string(), redis_check);

    // 3. Content-service gRPC health (critical for feed)
    let content_health = state.health_checker.content_service_health().await;
    let (content_status, content_message, content_ready) = match content_health.status {
        HealthStatus::Healthy => (
            ComponentStatus::Healthy,
            "Content-service reachable".to_string(),
            true,
        ),
        HealthStatus::Unavailable => {
            has_degraded = true;
            (
                ComponentStatus::Degraded,
                "Content-service reports transient failures".to_string(),
                false,
            )
        }
        HealthStatus::Unreachable => (
            ComponentStatus::Unhealthy,
            "Content-service unreachable (gRPC connection failed)".to_string(),
            false,
        ),
    };

    if !content_ready {
        ready = false;
        if matches!(content_status, ComponentStatus::Unhealthy) {
            overall_status = ComponentStatus::Unhealthy;
        } else {
            has_degraded = true;
        }
    }

    checks.insert(
        "content_service".to_string(),
        ComponentCheck {
            status: content_status.clone(),
            message: format!(
                "{}; last_checked={:?}",
                content_message, content_health.last_check
            ),
            latency_ms: None,
        },
    );

    let auth_health = state.health_checker.auth_service_health().await;
    let (auth_status, auth_message, auth_ready) = match auth_health.status {
        HealthStatus::Healthy => (
            ComponentStatus::Healthy,
            "Auth-service reachable".to_string(),
            true,
        ),
        HealthStatus::Unavailable => (
            ComponentStatus::Degraded,
            "Auth-service reporting transient failures".to_string(),
            false,
        ),
        HealthStatus::Unreachable => (
            ComponentStatus::Unhealthy,
            "Auth-service unreachable (gRPC connection failed)".to_string(),
            false,
        ),
    };

    if !auth_ready {
        has_degraded = true;
        if matches!(auth_status, ComponentStatus::Unhealthy) {
            ready = false;
            overall_status = ComponentStatus::Unhealthy;
        }
    }

    checks.insert(
        "auth_service".to_string(),
        ComponentCheck {
            status: auth_status,
            message: format!(
                "{}; last_checked={:?}",
                auth_message, auth_health.last_check
            ),
            latency_ms: None,
        },
    );

    // 4. ClickHouse check (optional, degrades gracefully)
    if !state.clickhouse_enabled {
        checks.insert(
            "clickhouse".to_string(),
            ComponentCheck {
                status: ComponentStatus::Healthy,
                message: "ClickHouse integration disabled by configuration".to_string(),
                latency_ms: None,
            },
        );
    } else {
        match state.check_clickhouse().await {
            Some(Ok(())) => {
                checks.insert(
                    "clickhouse".to_string(),
                    ComponentCheck {
                        status: ComponentStatus::Healthy,
                        message: "ClickHouse query successful".to_string(),
                        latency_ms: None,
                    },
                );
            }
            Some(Err(e)) => {
                has_degraded = true;
                checks.insert(
                    "clickhouse".to_string(),
                    ComponentCheck {
                        status: ComponentStatus::Degraded,
                        message: format!("ClickHouse health check failed: {}", e),
                        latency_ms: None,
                    },
                );
            }
            None => {
                has_degraded = true;
                checks.insert(
                    "clickhouse".to_string(),
                    ComponentCheck {
                        status: ComponentStatus::Degraded,
                        message: "ClickHouse client unavailable (initialization failed)"
                            .to_string(),
                        latency_ms: None,
                    },
                );
            }
        }
    }

    // 5. Kafka check (optional for event streaming)
    match state.check_kafka().await {
        Some(Ok(())) => {
            checks.insert(
                "kafka".to_string(),
                ComponentCheck {
                    status: ComponentStatus::Healthy,
                    message: "Kafka metadata fetch successful".to_string(),
                    latency_ms: None,
                },
            );
        }
        Some(Err(e)) => {
            has_degraded = true;
            checks.insert(
                "kafka".to_string(),
                ComponentCheck {
                    status: ComponentStatus::Degraded,
                    message: format!("Kafka metadata fetch failed: {}", e),
                    latency_ms: None,
                },
            );
        }
        None => {
            checks.insert(
                "kafka".to_string(),
                ComponentCheck {
                    status: ComponentStatus::Healthy,
                    message: "Kafka producer not configured for this deployment".to_string(),
                    latency_ms: None,
                },
            );
        }
    }

    // 6. CDC replication check (critical for analytics consistency)
    if !state.cdc_enabled {
        checks.insert(
            "cdc_replication".to_string(),
            ComponentCheck {
                status: ComponentStatus::Healthy,
                message: "CDC replication disabled".to_string(),
                latency_ms: None,
            },
        );
    } else if state.cdc_healthy.load(Ordering::SeqCst) {
        checks.insert(
            "cdc_replication".to_string(),
            ComponentCheck {
                status: ComponentStatus::Healthy,
                message: "CDC replication is healthy".to_string(),
                latency_ms: None,
            },
        );
    } else {
        ready = false;
        overall_status = ComponentStatus::Unhealthy;
        checks.insert(
            "cdc_replication".to_string(),
            ComponentCheck {
                status: ComponentStatus::Unhealthy,
                message: "CDC replication halted due to unrecoverable error".to_string(),
                latency_ms: None,
            },
        );
    }

    if ready && has_degraded {
        overall_status = ComponentStatus::Degraded;
    } else if !ready {
        overall_status = ComponentStatus::Unhealthy;
    }

    let response = ReadinessResponse {
        ready,
        status: overall_status,
        checks,
        timestamp: Utc::now().to_rfc3339(),
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
