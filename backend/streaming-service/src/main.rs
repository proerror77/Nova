use actix_web::{middleware::Logger, web, App, HttpRequest, HttpResponse, HttpServer};
use anyhow::{anyhow, Context};
use once_cell::sync::OnceCell;
use serde::Deserialize;
use std::env;
use tracing::{info, warn};
type RedisManager = redis::aio::ConnectionManager;

#[derive(Debug, Clone)]
struct Settings {
    shared_secret: String,
    allowlist: Vec<String>,
    admin_token: Option<String>,
}

#[derive(Clone)]
struct AppState {
    cfg: &'static Settings,
    redis: Option<RedisManager>,
}

static SETTINGS: OnceCell<Settings> = OnceCell::new();
static REDIS_MANAGER: OnceCell<RedisManager> = OnceCell::new();

#[derive(Debug, Deserialize)]
struct RtmpAuthQuery {
    app: Option<String>,
    name: Option<String>,
    addr: Option<String>,
    clientid: Option<String>,
}

async fn rtmp_auth(query: web::Query<RtmpAuthQuery>) -> HttpResponse {
    let name = query.name.clone().unwrap_or_default();
    let remote = query.addr.clone().unwrap_or_default();

    let Some(cfg) = SETTINGS.get() else {
        warn!("Configuration not loaded; rejecting publish");
        return HttpResponse::ServiceUnavailable().finish();
    };

    let allowed_cfg = cfg.allowlist.iter().any(|k| k == &name);
    let allowed_redis = match REDIS_MANAGER.get() {
        Some(manager) => {
            let mut conn = manager.clone();
            redis::cmd("SISMEMBER")
                .arg("streaming:keys:allowlist")
                .arg(&name)
                .query_async::<_, bool>(&mut conn)
                .await
                .unwrap_or(false)
        }
        None => false,
    };
    let allowed = allowed_cfg || allowed_redis;
    let using_default_secret = cfg.shared_secret == "changeme";
    let shared_ok = !using_default_secret && name == cfg.shared_secret;

    if !(shared_ok || allowed) {
        warn!(%name, %remote, "RTMP publish rejected: invalid stream key");
        return HttpResponse::Forbidden().finish();
    }

    info!(%name, %remote, allowed = %allowed, "RTMP publish accepted");
    HttpResponse::Ok().finish()
}

async fn rtmp_done(query: web::Query<RtmpAuthQuery>) -> HttpResponse {
    let name = query.name.clone().unwrap_or_default();
    let remote = query.addr.clone().unwrap_or_default();
    info!(%name, %remote, "RTMP publish done");
    HttpResponse::Ok().finish()
}

async fn health() -> HttpResponse {
    HttpResponse::Ok().body("ok")
}

fn has_admin_access(req: &HttpRequest, cfg: &Settings) -> bool {
    match cfg.admin_token.as_deref() {
        Some(token) if !token.is_empty() => req
            .headers()
            .get("x-admin-token")
            .and_then(|v| v.to_str().ok())
            .map(|v| v == token)
            .unwrap_or(false),
        _ => false,
    }
}

async fn admin_add_key(
    state: web::Data<AppState>,
    req: HttpRequest,
    body: web::Json<StreamKey>,
) -> HttpResponse {
    if !has_admin_access(&req, state.cfg) {
        return HttpResponse::Unauthorized().finish();
    }
    let Some(redis) = state.redis.clone() else {
        return HttpResponse::ServiceUnavailable().body("Redis not configured");
    };
    let mut conn = redis.clone();
    let key = body.key.trim();
    if key.is_empty() {
        return HttpResponse::BadRequest().body("key is required");
    }
    if let Err(e) = redis::cmd("SADD")
        .arg("streaming:keys:allowlist")
        .arg(key)
        .query_async::<_, ()>(&mut conn)
        .await
    {
        warn!(error = %e, "Failed to add stream key");
        return HttpResponse::InternalServerError().finish();
    }
    HttpResponse::Ok().finish()
}

async fn admin_delete_key(
    state: web::Data<AppState>,
    req: HttpRequest,
    path: web::Path<String>,
) -> HttpResponse {
    if !has_admin_access(&req, state.cfg) {
        return HttpResponse::Unauthorized().finish();
    }
    let Some(redis) = state.redis.clone() else {
        return HttpResponse::ServiceUnavailable().body("Redis not configured");
    };
    let mut conn = redis.clone();
    let key = path.into_inner();
    if key.is_empty() {
        return HttpResponse::BadRequest().body("key is required");
    }
    if let Err(e) = redis::cmd("SREM")
        .arg("streaming:keys:allowlist")
        .arg(&key)
        .query_async::<_, ()>(&mut conn)
        .await
    {
        warn!(error = %e, "Failed to delete stream key");
        return HttpResponse::InternalServerError().finish();
    }
    HttpResponse::Ok().finish()
}

async fn admin_list_keys(state: web::Data<AppState>, req: HttpRequest) -> HttpResponse {
    if !has_admin_access(&req, state.cfg) {
        return HttpResponse::Unauthorized().finish();
    }
    let Some(redis) = state.redis.clone() else {
        return HttpResponse::ServiceUnavailable().body("Redis not configured");
    };
    let mut conn = redis.clone();
    match redis::cmd("SMEMBERS")
        .arg("streaming:keys:allowlist")
        .query_async::<_, Vec<String>>(&mut conn)
        .await
    {
        Ok(keys) => HttpResponse::Ok().json(keys),
        Err(e) => {
            warn!(error = %e, "Failed to list stream keys");
            HttpResponse::InternalServerError().finish()
        }
    }
}

#[derive(Debug, Deserialize)]
struct StreamKey {
    key: String,
}

#[actix_web::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=info".into()),
        )
        .init();

    let shared_secret = env::var("RTMP_SHARED_SECRET")
        .ok()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow!("RTMP_SHARED_SECRET must be set"))?;

    let allowlist = env::var("RTMP_ALLOWED_KEYS")
        .ok()
        .map(|s| {
            s.split(',')
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty())
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let admin_token = env::var("ADMIN_TOKEN").ok();

    let redis = if let Ok(redis_url) = env::var("REDIS_URL") {
        match redis::Client::open(redis_url) {
            Ok(client) => match client.get_tokio_connection_manager().await {
                Ok(manager) => Some(manager),
                Err(e) => {
                    warn!(error = %e, "Failed to connect Redis, continuing without allowlist store");
                    None
                }
            },
            Err(e) => {
                warn!(error = %e, "Invalid REDIS_URL, continuing without allowlist store");
                None
            }
        }
    } else {
        None
    };

    SETTINGS
        .set(Settings {
            shared_secret: shared_secret.clone(),
            allowlist,
            admin_token,
        })
        .map_err(|_| anyhow!("failed to set settings"))?;

    if let Some(redis) = redis {
        let _ = REDIS_MANAGER.set(redis);
        info!("Redis allowlist backend enabled");
    } else {
        info!("Redis allowlist backend disabled");
    }

    if shared_secret == "changeme" {
        warn!("RTMP_SHARED_SECRET is still default 'changeme' — reject unless allowlist matches");
    }

    let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".into());
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8088);
    let bind_addr = format!("{host}:{port}");

    let cfg = SETTINGS.get().expect("settings initialized");
    let state = AppState {
        cfg,
        redis: REDIS_MANAGER.get().cloned(),
    };

    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(state.clone()))
            .wrap(Logger::default())
            .service(
                web::scope("/api/v1/streams")
                    .route("/auth", web::post().to(rtmp_auth))
                    .route("/done", web::post().to(rtmp_done)),
            )
            .route("/health", web::get().to(health))
            .service(
                web::scope("/api/v1/admin/streams/keys")
                    .route("", web::post().to(admin_add_key))
                    .route("", web::get().to(admin_list_keys))
                    .route("/{key}", web::delete().to(admin_delete_key)),
            )
    })
    .bind(&bind_addr)
    .with_context(|| format!("Failed to bind on {bind_addr}"))?
    .run()
    .await
    .context("HTTP server error")?;

    Ok(())
}
