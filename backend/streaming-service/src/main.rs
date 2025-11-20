use actix_web::{middleware::Logger, web, App, HttpResponse, HttpServer};
use anyhow::Context;
use once_cell::sync::Lazy;
use serde::Deserialize;
use std::env;
use tracing::{info, warn};

static SHARED_SECRET: Lazy<Option<String>> =
    Lazy::new(|| env::var("RTMP_SHARED_SECRET").ok().filter(|s| !s.is_empty()));

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

    // Basic shared-secret validation to prevent unauthenticated ingest
    let Some(secret) = SHARED_SECRET.as_ref() else {
        warn!("RTMP shared secret not configured; rejecting publish");
        return HttpResponse::Forbidden().finish();
    };

    if name != *secret {
        warn!(%name, %remote, "RTMP publish rejected: invalid stream key");
        return HttpResponse::Forbidden().finish();
    }

    info!(%name, %remote, "RTMP publish accepted");
    HttpResponse::Ok().finish()
}

async fn rtmp_done(query: web::Query<RtmpAuthQuery>) -> HttpResponse {
    let name = query.name.clone().unwrap_or_default();
    let remote = query.addr.clone().unwrap_or_default();
    info!(%name, %remote, "RTMP publish done");
    HttpResponse::Ok().finish()
}

#[actix_web::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,actix_web=info".into()),
        )
        .init();

    let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".into());
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8088);
    let bind_addr = format!("{host}:{port}");

    HttpServer::new(|| {
        App::new()
            .wrap(Logger::default())
            .service(
                web::scope("/api/v1/streams")
                    .route("/auth", web::post().to(rtmp_auth))
                    .route("/done", web::post().to(rtmp_done)),
            )
    })
    .bind(&bind_addr)
    .with_context(|| format!("Failed to bind on {bind_addr}"))?
    .run()
    .await
    .context("HTTP server error")?;

    Ok(())
}
