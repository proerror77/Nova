//! Route configuration
//!
//! Centralized route setup extracted from main.rs
//! Each domain (feed, streams, videos, etc.) manages its own routes

use crate::app_state::AppState;
use crate::handlers;
use crate::middleware::{GlobalRateLimitMiddleware, JwtAuthMiddleware};
use actix_web::{web, HttpResponse};
use std::io;

/// Configure all routes for the application
pub fn configure_routes(cfg: &mut web::ServiceConfig) {
    cfg
        // Static/public endpoints
        .route("/metrics", web::get().to(metrics_handler))
        .route("/.well-known/jwks.json", web::get().to(handlers::get_jwks))
        .route("/api/v1/openapi.json", web::get().to(openapi_handler))
        .route("/swagger-ui", web::get().to(swagger_ui_handler))
        .route("/docs", web::get().to(docs_handler))
        // API routes
        .service(
            web::scope("/api/v1")
                .route("/health", web::get().to(handlers::health_check))
                .route("/health/ready", web::get().to(handlers::readiness_check))
                .route("/health/live", web::get().to(handlers::liveness_check))
                // Modular route configuration
                .configure(routes::feed::configure)
                .configure(routes::streams::configure)
                .configure(routes::events::configure)
                .configure(routes::videos::configure)
                .configure(routes::stories::configure)
                .configure(routes::auth::configure)
                .configure(routes::users::configure)
                .configure(routes::posts::configure)
                .configure(routes::comments::configure)
                .configure(routes::discover::configure)
                .configure(routes::trending::configure)
                .configure(routes::experiments::configure)
                .configure(routes::reels::configure)
                .configure(routes::transcoding::configure)
        )
        // WebSocket endpoints (outside /api/v1)
        .service(
            web::scope("/ws/streams")
                .wrap(JwtAuthMiddleware)
                .route("/{id}/chat", web::get().to(handlers::stream_chat_ws))
        );
}

/// Metrics handler
async fn metrics_handler() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("text/plain; version=0.0.4")
        .body(crate::metrics::gather_metrics())
}

/// OpenAPI JSON endpoint
async fn openapi_handler() -> HttpResponse {
    use utoipa::OpenApi;
    HttpResponse::Ok()
        .content_type("application/json")
        .json(crate::openapi::ApiDoc::openapi())
}

/// Swagger UI handler
async fn swagger_ui_handler() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(include_str!("../static/swagger-ui.html"))
}

/// API Documentation entry point
async fn docs_handler() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(include_str!("../static/docs.html"))
}

// Sub-modules for each domain
mod routes {
    use super::*;

    pub mod feed {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/feed")
                    .wrap(JwtAuthMiddleware)
                    .service(handlers::get_feed)
                    .service(handlers::invalidate_feed_cache),
            );
        }
    }

    pub mod streams {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/streams")
                    .route("", web::get().to(handlers::list_live_streams))
                    .route("/search", web::get().to(handlers::search_streams))
                    .route("/{id}", web::get().to(handlers::get_stream_details))
                    .route("/{id}/comments", web::get().to(handlers::get_stream_comments))
                    .route("/rtmp/auth", web::post().to(handlers::rtmp_authenticate))
                    .route("/rtmp/done", web::post().to(handlers::rtmp_done))
                    .service(
                        web::scope("")
                            .wrap(JwtAuthMiddleware)
                            .route("", web::post().to(handlers::create_stream))
                            .route("/{id}/join", web::post().to(handlers::join_stream))
                            .route("/{id}/leave", web::post().to(handlers::leave_stream))
                            .route("/{id}/comments", web::post().to(handlers::post_stream_comment))
                            .route("/{id}/analytics", web::get().to(handlers::get_stream_analytics)),
                    ),
            );
        }
    }

    pub mod events {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/events")
                    .service(handlers::ingest_events),
            );
        }
    }

    pub mod videos {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/videos")
                    .wrap(JwtAuthMiddleware)
                    .route("/upload/init", web::post().to(handlers::video_upload_init))
                    .route("/upload/complete", web::post().to(handlers::video_upload_complete))
                    .route("", web::post().to(handlers::create_video))
                    .route("/{id}", web::get().to(handlers::get_video))
                    .route("/{id}", web::patch().to(handlers::update_video))
                    .route("/{id}", web::delete().to(handlers::delete_video))
                    .route("/{id}/stream", web::get().to(handlers::get_stream_manifest)),
            );
        }
    }

    pub mod stories {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/stories")
                    .wrap(JwtAuthMiddleware)
                    .route("", web::get().to(handlers::list_stories))
                    .route("", web::post().to(handlers::create_story))
                    .route("/{id}", web::get().to(handlers::get_story))
                    .route("/{id}", web::delete().to(handlers::delete_story))
                    .route("/{id}/privacy", web::patch().to(handlers::update_story_privacy))
                    .route("/user/{user_id}", web::get().to(handlers::list_user_stories))
                    .route("/close-friends/{friend_id}", web::post().to(handlers::add_close_friend))
                    .route("/close-friends/{friend_id}", web::delete().to(handlers::remove_close_friend))
                    .route("/close-friends", web::get().to(handlers::list_close_friends)),
            );
        }
    }

    pub mod auth {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/auth")
                    .route("/dev-verify", web::post().to(handlers::dev_verify_email))
                    .route("/register", web::post().to(handlers::register))
                    .route("/login", web::post().to(handlers::login))
                    .route("/verify-email", web::post().to(handlers::verify_email))
                    .route("/logout", web::post().to(handlers::logout))
                    .route("/refresh", web::post().to(handlers::refresh_token))
                    .route("/forgot-password", web::post().to(handlers::forgot_password))
                    .route("/reset-password", web::post().to(handlers::reset_password))
                    .route("/2fa/verify", web::post().to(handlers::verify_2fa))
                    .route("/oauth/authorize", web::post().to(handlers::authorize))
                    .service(
                        web::scope("/2fa")
                            .wrap(JwtAuthMiddleware)
                            .route("/enable", web::post().to(handlers::enable_2fa))
                            .route("/confirm", web::post().to(handlers::confirm_2fa)),
                    )
                    .service(
                        web::scope("/oauth")
                            .wrap(JwtAuthMiddleware)
                            .route("/link", web::post().to(handlers::link_provider))
                            .route("/link/{provider}", web::delete().to(handlers::unlink_provider)),
                    ),
            );
        }
    }

    pub mod users {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg
                .service(
                    web::scope("/users/me")
                        .wrap(JwtAuthMiddleware)
                        .route("", web::get().to(handlers::get_current_user))
                        .route("", web::patch().to(handlers::update_profile))
                        .route("/public-key", web::put().to(handlers::upsert_my_public_key))
                        .route("/bookmarks", web::get().to(handlers::get_user_bookmarks)),
                )
                .service(
                    web::scope("/users")
                        .route("/{id}", web::get().to(handlers::get_user))
                        .route("/{id}/public-key", web::get().to(handlers::get_user_public_key))
                        .route("/{id}/followers", web::get().to(handlers::get_followers))
                        .route("/{id}/following", web::get().to(handlers::get_following))
                        .service(
                            web::scope("")
                                .wrap(JwtAuthMiddleware)
                                .route("/{id}/follow", web::post().to(handlers::follow_user))
                                .route("/{id}/follow", web::delete().to(handlers::unfollow_user))
                                .route("/{id}/block", web::post().to(handlers::block_user))
                                .route("/{id}/block", web::delete().to(handlers::unblock_user)),
                        ),
                );
        }
    }

    pub mod posts {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/posts")
                    .wrap(JwtAuthMiddleware)
                    .route("", web::post().to(handlers::create_post_with_media))
                    .route("/upload/init", web::post().to(handlers::upload_init_request))
                    .route("/upload/complete", web::post().to(handlers::upload_complete_request))
                    .route("/{id}", web::get().to(handlers::get_post_request))
                    .route("/{post_id}/comments", web::post().to(handlers::create_comment))
                    .route("/{post_id}/comments", web::get().to(handlers::get_comments))
                    .route("/{post_id}/like", web::post().to(handlers::like_post))
                    .route("/{post_id}/like", web::delete().to(handlers::unlike_post))
                    .route("/{post_id}/like/status", web::get().to(handlers::check_like_status))
                    .route("/{post_id}/likes", web::get().to(handlers::get_post_likes))
                    .route("/{id}/bookmark", web::post().to(handlers::bookmark_post))
                    .route("/{id}/bookmark", web::delete().to(handlers::unbookmark_post))
                    .route("/{id}/share", web::post().to(handlers::share_post)),
            );
        }
    }

    pub mod comments {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/comments")
                    .wrap(JwtAuthMiddleware)
                    .route("/{comment_id}", web::patch().to(handlers::update_comment))
                    .route("/{comment_id}", web::delete().to(handlers::delete_comment)),
            );
        }
    }

    pub mod discover {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/discover")
                    .wrap(JwtAuthMiddleware)
                    .route("/suggested-users", web::get().to(handlers::get_suggested_users)),
            );
        }
    }

    pub mod trending {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg
                .service(handlers::get_trending)
                .service(handlers::get_trending_videos)
                .service(handlers::get_trending_posts)
                .service(handlers::get_trending_streams)
                .service(handlers::get_trending_categories)
                .service(
                    web::scope("")
                        .wrap(JwtAuthMiddleware)
                        .service(handlers::record_engagement),
                );
        }
    }

    pub mod experiments {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/experiments")
                    .wrap(JwtAuthMiddleware)
                    // TODO: Add experiment endpoints
            );
        }
    }

    pub mod reels {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/reels")
                    .wrap(JwtAuthMiddleware)
                    // Reels uses /videos endpoints, no separate routing needed
            );
        }
    }

    pub mod transcoding {
        use super::*;
        pub fn configure(cfg: &mut web::ServiceConfig) {
            cfg.service(
                web::scope("/transcoding")
                    .wrap(JwtAuthMiddleware)
                    .route("/progress/{upload_id}", web::get().to(handlers::get_transcoding_progress))
                    .route("/queue", web::get().to(handlers::get_transcoding_queue)),
            );
        }
    }
}
