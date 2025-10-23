//! Integration tests for Stories and Videos minimal flows

mod common;

use actix_web::{test, web, App, HttpRequest};
use serde_json::json;
use user_service::{handlers, services::video_service::VideoService, config::video_config::VideoConfig};
use uuid::Uuid;

use crate::common::fixtures;

#[actix_web::test]
async fn test_stories_visibility_followers() {
    let pool = fixtures::create_test_pool().await;
    fixtures::cleanup_test_data(&pool).await;

    // Create users
    let owner = fixtures::create_test_user(&pool).await;
    let follower = fixtures::create_test_user(&pool).await;
    let stranger = fixtures::create_test_user(&pool).await;

    // Make follower follow owner
    sqlx::query("INSERT INTO follows (follower_id, following_id) VALUES ($1, $2) ON CONFLICT DO NOTHING")
        .bind(follower.id)
        .bind(owner.id)
        .execute(&pool)
        .await
        .unwrap();

    // App with handlers wired to inject UserId explicitly in closures
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .service(
                web::resource("/stories")
                    .route(web::post().to(move |payload: web::Json<handlers::stories::CreateStoryRequest>, pool: web::Data<sqlx::PgPool>| async move {
                        handlers::create_story(user_service::middleware::UserId(owner.id), pool, payload).await
                    }))
                    .route(web::get().to(move |pool: web::Data<sqlx::PgPool>| async move {
                        handlers::list_stories(user_service::middleware::UserId(follower.id), pool, web::Query(handlers::stories::FeedQuery{ limit:20})).await
                    })),
            )
            .service(
                web::resource("/stories_as_stranger")
                    .route(web::get().to(move |pool: web::Data<sqlx::PgPool>| async move {
                        handlers::list_stories(user_service::middleware::UserId(stranger.id), pool, web::Query(handlers::stories::FeedQuery{ limit:20})).await
                    })),
            )
    ).await;

    // Create followers-only story
    let req = test::TestRequest::post()
        .uri("/stories")
        .set_json(&json!({
            "content_url":"https://cdn/story.jpg",
            "content_type":"image",
            "caption":"hello",
            "privacy_level":"followers"
        }))
        .to_request();
    let resp = test::call_service(&app, req).await;
    assert!(resp.status().is_success());

    // Follower should see it
    let req = test::TestRequest::get().uri("/stories").to_request();
    let resp = test::call_service(&app, req).await;
    assert!(resp.status().is_success());
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["stories"].as_array().unwrap().len(), 1);

    // Stranger should not see it
    let req = test::TestRequest::get().uri("/stories_as_stranger").to_request();
    let resp = test::call_service(&app, req).await;
    assert!(resp.status().is_success());
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["stories"].as_array().unwrap().len(), 0);
}

#[actix_web::test]
async fn test_videos_create_like_share_flow() {
    let pool = fixtures::create_test_pool().await;
    fixtures::cleanup_test_data(&pool).await;
    let owner = fixtures::create_test_user(&pool).await;

    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(pool.clone()))
            .app_data(web::Data::new(VideoService::new(VideoConfig::from_env())))
            .route("/videos", web::post().to(move |req: HttpRequest, body: web::Json<user_service::models::video::CreateVideoRequest>, pool: web::Data<sqlx::PgPool>, vs: web::Data<VideoService>| async move {
                handlers::create_video(req, user_service::middleware::UserId(owner.id), pool, body, vs).await
            }))
            .route("/videos/{id}", web::get().to(handlers::get_video))
            .route("/videos/{id}/like", web::post().to(handlers::like_video))
            .route("/videos/{id}/share", web::post().to(handlers::share_video))
    ).await;

    // Create video
    let create = json!({ "title":"video1", "description": "desc" });
    let req = test::TestRequest::post().uri("/videos").set_json(&create).to_request();
    let resp = test::call_service(&app, req).await;
    assert!(resp.status().is_success());
    let body: serde_json::Value = test::read_body_json(resp).await;
    let id = Uuid::parse_str(body["video_id"].as_str().unwrap()).unwrap();

    // Like
    let req = test::TestRequest::post().uri(&format!("/videos/{}/like", id)).to_request();
    let resp = test::call_service(&app, req).await;
    assert!(resp.status().is_success());
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["video_id"].as_str().unwrap(), id.to_string());

    // Share
    let req = test::TestRequest::post().uri(&format!("/videos/{}/share", id)).to_request();
    let resp = test::call_service(&app, req).await;
    assert!(resp.status().is_success());
    let body: serde_json::Value = test::read_body_json(resp).await;
    assert_eq!(body["video_id"].as_str().unwrap(), id.to_string());
}
