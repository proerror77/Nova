/// Integration tests for POST endpoints (Phase 2)
/// Tests get-post endpoint with comprehensive scenarios
mod common;

#[cfg(test)]
mod tests {
    use actix_web::{test, web, App};
    use serde::{Deserialize, Serialize};
    use sqlx::PgPool;
    use user_service::{config::Config, handlers, models::PostResponse};
    use uuid::Uuid;

    // Include test fixtures from common module
    use crate::common::fixtures;

    #[derive(Debug, Serialize, Deserialize)]
    struct ErrorResponse {
        error: String,
        details: Option<String>,
    }

    // ============================================
    // Test Setup Helpers
    // ============================================

    async fn setup_test_app(
        pool: PgPool,
    ) -> impl actix_web::dev::Service<
        actix_http::Request,
        Response = actix_web::dev::ServiceResponse,
        Error = actix_web::Error,
    > {
        let config = Config::from_env().expect("Failed to load config");

        test::init_service(
            App::new()
                .app_data(web::Data::new(pool))
                .app_data(web::Data::new(config))
                .service(
                    web::scope("/api/v1/posts")
                        .route("/{id}", web::get().to(handlers::get_post_request)),
                ),
        )
        .await
    }

    // ============================================
    // Test 1: Get Published Post (Happy Path)
    // ============================================

    #[actix_web::test]
    async fn test_get_published_post() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        // Create test user and post
        let user = fixtures::create_test_user(&pool).await;
        let (post, _images) = fixtures::create_test_post_with_images(
            &pool,
            user.id,
            Some("My first post!"),
            "published",
            "completed",
        )
        .await;

        // Update metadata with engagement stats
        fixtures::update_post_metadata(&pool, post.id, 42, 5, 128).await;

        let app = setup_test_app(pool.clone()).await;

        let req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", post.id))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let body: PostResponse = test::read_body_json(resp).await;
        assert_eq!(body.id, post.id.to_string());
        assert_eq!(body.user_id, user.id.to_string());
        assert_eq!(body.caption, Some("My first post!".to_string()));
        assert_eq!(body.like_count, 42);
        assert_eq!(body.comment_count, 5);
        assert_eq!(body.view_count, 128);
        assert_eq!(body.status, "published");
        assert!(body.thumbnail_url.is_some());
        assert!(body.medium_url.is_some());
        assert!(body.original_url.is_some());

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 2: Get Post with All Engagement Metrics
    // ============================================

    #[actix_web::test]
    async fn test_get_post_with_all_metrics() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let user = fixtures::create_test_user(&pool).await;
        let (post, _) = fixtures::create_test_post_with_images(
            &pool,
            user.id,
            Some("Popular post"),
            "published",
            "completed",
        )
        .await;

        // Set high engagement
        fixtures::update_post_metadata(&pool, post.id, 9999, 500, 50000).await;

        let app = setup_test_app(pool.clone()).await;

        let req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", post.id))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let body: PostResponse = test::read_body_json(resp).await;
        assert_eq!(body.like_count, 9999);
        assert_eq!(body.comment_count, 500);
        assert_eq!(body.view_count, 50000);

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 3: Get Soft-Deleted Post (Should Return 404)
    // ============================================

    #[actix_web::test]
    async fn test_get_soft_deleted_post() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let user = fixtures::create_test_user(&pool).await;
        let (post, _) = fixtures::create_test_post_with_images(
            &pool,
            user.id,
            Some("Deleted post"),
            "published",
            "completed",
        )
        .await;

        // Soft delete the post
        fixtures::soft_delete_post(&pool, post.id).await;

        let app = setup_test_app(pool.clone()).await;

        let req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", post.id))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 404);

        let body: ErrorResponse = test::read_body_json(resp).await;
        assert_eq!(body.error, "Post not found");

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 4: Get Non-Existent Post (Should Return 404)
    // ============================================

    #[actix_web::test]
    async fn test_get_nonexistent_post() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let app = setup_test_app(pool.clone()).await;

        // Use a random UUID that doesn't exist
        let fake_id = Uuid::new_v4();

        let req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", fake_id))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 404);

        let body: ErrorResponse = test::read_body_json(resp).await;
        assert_eq!(body.error, "Post not found");

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 5: Invalid UUID Format (Should Return 400)
    // ============================================

    #[actix_web::test]
    async fn test_get_post_invalid_uuid() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let app = setup_test_app(pool.clone()).await;

        let req = test::TestRequest::get()
            .uri("/api/v1/posts/not-a-valid-uuid")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 400);

        let body: ErrorResponse = test::read_body_json(resp).await;
        assert_eq!(body.error, "Invalid post ID format");

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 6: Get Post in Pending State
    // ============================================

    #[actix_web::test]
    async fn test_get_post_pending_state() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let user = fixtures::create_test_user(&pool).await;
        let (post, _) = fixtures::create_test_post_with_images(
            &pool,
            user.id,
            Some("Pending upload"),
            "pending",
            "pending",
        )
        .await;

        let app = setup_test_app(pool.clone()).await;

        let req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", post.id))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let body: PostResponse = test::read_body_json(resp).await;
        assert_eq!(body.status, "pending");
        // Images may not have URLs yet
        assert!(body.id == post.id.to_string());

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 7: Get Post in Processing State
    // ============================================

    #[actix_web::test]
    async fn test_get_post_processing_state() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let user = fixtures::create_test_user(&pool).await;
        let (post, _) = fixtures::create_test_post_with_images(
            &pool,
            user.id,
            Some("Processing images"),
            "processing",
            "processing",
        )
        .await;

        let app = setup_test_app(pool.clone()).await;

        let req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", post.id))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let body: PostResponse = test::read_body_json(resp).await;
        assert_eq!(body.status, "processing");

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 8: Get Post Without Caption
    // ============================================

    #[actix_web::test]
    async fn test_get_post_without_caption() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let user = fixtures::create_test_user(&pool).await;
        let (post, _) = fixtures::create_test_post_with_images(
            &pool,
            user.id,
            None, // No caption
            "published",
            "completed",
        )
        .await;

        let app = setup_test_app(pool.clone()).await;

        let req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", post.id))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let body: PostResponse = test::read_body_json(resp).await;
        assert_eq!(body.caption, None);

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 9: Get Post with Zero Engagement
    // ============================================

    #[actix_web::test]
    async fn test_get_post_zero_engagement() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let user = fixtures::create_test_user(&pool).await;
        let (post, _) = fixtures::create_test_post_with_images(
            &pool,
            user.id,
            Some("Brand new post"),
            "published",
            "completed",
        )
        .await;

        // Default metadata should be all zeros
        let app = setup_test_app(pool.clone()).await;

        let req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", post.id))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let body: PostResponse = test::read_body_json(resp).await;
        assert_eq!(body.like_count, 0);
        assert_eq!(body.comment_count, 0);
        assert_eq!(body.view_count, 0);

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 10: Multiple Posts Creation and Retrieval
    // ============================================

    #[actix_web::test]
    async fn test_multiple_posts_retrieval() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let user = fixtures::create_test_user(&pool).await;

        // Create 3 posts
        let mut post_ids = Vec::new();
        for i in 1..=3 {
            let (post, _) = fixtures::create_test_post_with_images(
                &pool,
                user.id,
                Some(&format!("Post {}", i)),
                "published",
                "completed",
            )
            .await;
            post_ids.push(post.id);
        }

        let app = setup_test_app(pool.clone()).await;

        // Retrieve each post and verify
        for (i, post_id) in post_ids.iter().enumerate() {
            let req = test::TestRequest::get()
                .uri(&format!("/api/v1/posts/{}", post_id))
                .to_request();

            let resp = test::call_service(&app, req).await;
            assert!(resp.status().is_success());

            let body: PostResponse = test::read_body_json(resp).await;
            assert_eq!(body.caption, Some(format!("Post {}", i + 1)));
        }

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 11: Pagination Test (Bonus)
    // ============================================

    #[actix_web::test]
    async fn test_pagination_batch_creation() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let user = fixtures::create_test_user(&pool).await;

        // Create 25 posts using batch helper
        let posts = fixtures::create_test_posts_batch(&pool, user.id, 25).await;
        assert_eq!(posts.len(), 25);

        let app = setup_test_app(pool.clone()).await;

        // Verify we can retrieve first and last post
        let first_req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", posts[0].id))
            .to_request();

        let first_resp = test::call_service(&app, first_req).await;
        assert!(first_resp.status().is_success());

        let last_req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", posts[24].id))
            .to_request();

        let last_resp = test::call_service(&app, last_req).await;
        assert!(last_resp.status().is_success());

        fixtures::cleanup_test_data(&pool).await;
    }

    // ============================================
    // Test 12: Get Post with Maximum Caption Length
    // ============================================

    #[actix_web::test]
    async fn test_get_post_max_caption() {
        let pool = fixtures::create_test_pool().await;
        fixtures::cleanup_test_data(&pool).await;

        let user = fixtures::create_test_user(&pool).await;

        // Create caption at max length (2200 chars)
        let long_caption = "a".repeat(2200);
        let (post, _) = fixtures::create_test_post_with_images(
            &pool,
            user.id,
            Some(&long_caption),
            "published",
            "completed",
        )
        .await;

        let app = setup_test_app(pool.clone()).await;

        let req = test::TestRequest::get()
            .uri(&format!("/api/v1/posts/{}", post.id))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let body: PostResponse = test::read_body_json(resp).await;
        assert_eq!(body.caption.as_ref().unwrap().len(), 2200);

        fixtures::cleanup_test_data(&pool).await;
    }
}
