/// Feed API Integration Tests
///
/// Tests for the /api/v2/feed endpoints including bookmark_count field validation.
use serde::Deserialize;

/// FeedPost response model for testing
#[derive(Debug, Deserialize)]
struct FeedPost {
    id: String,
    user_id: String,
    content: String,
    created_at: i64,
    ranking_score: f64,
    like_count: u32,
    comment_count: u32,
    share_count: u32,
    bookmark_count: u32,
    media_urls: Vec<String>,
    media_type: Option<String>,
    author_username: Option<String>,
    author_display_name: Option<String>,
    author_avatar: Option<String>,
    /// Account type when post was created: "primary" or "alias" (Issue #259)
    #[serde(default = "default_author_account_type")]
    author_account_type: String,
}

fn default_author_account_type() -> String {
    "primary".to_string()
}

/// GetFeedResponse model for testing
#[derive(Debug, Deserialize)]
struct GetFeedResponse {
    posts: Vec<FeedPost>,
    next_cursor: Option<String>,
    has_more: bool,
}

/// ErrorResponse model for testing
#[derive(Debug, Deserialize)]
struct ErrorResponse {
    error: String,
    message: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Test that FeedPost deserialization includes bookmark_count field
    #[test]
    fn test_feed_post_deserializes_bookmark_count() {
        let json = r#"{
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test content",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 7,
            "media_urls": [],
            "media_type": null,
            "author_username": "testuser",
            "author_display_name": "Test User",
            "author_avatar": "https://example.com/avatar.jpg"
        }"#;

        let post: FeedPost = serde_json::from_str(json).expect("Failed to deserialize FeedPost");

        assert_eq!(post.id, "post-123");
        assert_eq!(post.bookmark_count, 7);
        assert_eq!(post.like_count, 10);
        assert_eq!(post.comment_count, 5);
        assert_eq!(post.share_count, 2);
    }

    /// Test that FeedPost handles zero bookmark_count
    #[test]
    fn test_feed_post_zero_bookmark_count() {
        let json = r#"{
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test content",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 0,
            "comment_count": 0,
            "share_count": 0,
            "bookmark_count": 0,
            "media_urls": [],
            "media_type": null
        }"#;

        let post: FeedPost = serde_json::from_str(json).expect("Failed to deserialize FeedPost");

        assert_eq!(post.bookmark_count, 0);
    }

    /// Test GetFeedResponse deserialization with multiple posts
    #[test]
    fn test_get_feed_response_deserializes() {
        let json = r#"{
            "posts": [
                {
                    "id": "post-1",
                    "user_id": "user-1",
                    "content": "First post",
                    "created_at": 1703116800,
                    "ranking_score": 0.9,
                    "like_count": 100,
                    "comment_count": 10,
                    "share_count": 5,
                    "bookmark_count": 20,
                    "media_urls": [],
                    "media_type": null
                },
                {
                    "id": "post-2",
                    "user_id": "user-2",
                    "content": "Second post",
                    "created_at": 1703116900,
                    "ranking_score": 0.8,
                    "like_count": 50,
                    "comment_count": 5,
                    "share_count": 2,
                    "bookmark_count": 8,
                    "media_urls": ["https://example.com/img.jpg"],
                    "media_type": "image"
                }
            ],
            "next_cursor": "cursor-abc123",
            "has_more": true
        }"#;

        let response: GetFeedResponse =
            serde_json::from_str(json).expect("Failed to deserialize GetFeedResponse");

        assert_eq!(response.posts.len(), 2);
        assert_eq!(response.posts[0].bookmark_count, 20);
        assert_eq!(response.posts[1].bookmark_count, 8);
        assert_eq!(response.next_cursor, Some("cursor-abc123".to_string()));
        assert!(response.has_more);
    }

    /// Test GetFeedResponse with empty posts
    #[test]
    fn test_get_feed_response_empty_posts() {
        let json = r#"{
            "posts": [],
            "next_cursor": null,
            "has_more": false
        }"#;

        let response: GetFeedResponse =
            serde_json::from_str(json).expect("Failed to deserialize GetFeedResponse");

        assert!(response.posts.is_empty());
        assert!(response.next_cursor.is_none());
        assert!(!response.has_more);
    }

    /// Test author information parsing
    #[test]
    fn test_feed_post_author_information() {
        let json = r#"{
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test content",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 7,
            "media_urls": [],
            "media_type": null,
            "author_username": "johndoe",
            "author_display_name": "John Doe",
            "author_avatar": "https://cdn.example.com/avatars/johndoe.jpg"
        }"#;

        let post: FeedPost = serde_json::from_str(json).expect("Failed to deserialize FeedPost");

        assert_eq!(post.author_username, Some("johndoe".to_string()));
        assert_eq!(post.author_display_name, Some("John Doe".to_string()));
        assert_eq!(
            post.author_avatar,
            Some("https://cdn.example.com/avatars/johndoe.jpg".to_string())
        );
    }

    /// Test missing author information (all fields None)
    #[test]
    fn test_feed_post_missing_author_information() {
        let json = r#"{
            "id": "post-123",
            "user_id": "user-456",
            "content": "Test content",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 7,
            "media_urls": [],
            "media_type": null,
            "author_username": null,
            "author_display_name": null,
            "author_avatar": null
        }"#;

        let post: FeedPost = serde_json::from_str(json).expect("Failed to deserialize FeedPost");

        assert!(post.author_username.is_none());
        assert!(post.author_display_name.is_none());
        assert!(post.author_avatar.is_none());
    }

    /// Test media URLs parsing
    #[test]
    fn test_feed_post_media_urls() {
        let json = r#"{
            "id": "post-123",
            "user_id": "user-456",
            "content": "Multi-image post",
            "created_at": 1703116800,
            "ranking_score": 0.85,
            "like_count": 10,
            "comment_count": 5,
            "share_count": 2,
            "bookmark_count": 7,
            "media_urls": [
                "https://cdn.example.com/image1.jpg",
                "https://cdn.example.com/image2.jpg",
                "https://cdn.example.com/image3.jpg"
            ],
            "media_type": "image"
        }"#;

        let post: FeedPost = serde_json::from_str(json).expect("Failed to deserialize FeedPost");

        assert_eq!(post.media_urls.len(), 3);
        assert_eq!(post.media_type, Some("image".to_string()));
    }
}

/// Integration tests that require running services
/// These are marked as #[ignore] and can be run with `cargo test -- --ignored`
#[cfg(test)]
mod integration_tests {
    use super::*;

    /// Test GET /api/v2/feed returns bookmark_count in response
    /// Requires: auth-service, feed-service, social-service running
    #[tokio::test]
    #[ignore = "Requires running services"]
    async fn test_feed_api_returns_bookmark_count() {
        // This test would make actual HTTP requests to the API
        // For now, it's marked as ignored and serves as documentation

        // 1. Authenticate to get JWT token
        // 2. GET /api/v2/feed with Authorization header
        // 3. Verify response contains bookmark_count field

        // Example:
        // let client = reqwest::Client::new();
        // let response = client
        //     .get("http://localhost:8080/api/v2/feed")
        //     .header("Authorization", format!("Bearer {}", jwt_token))
        //     .send()
        //     .await
        //     .unwrap();
        //
        // let feed: GetFeedResponse = response.json().await.unwrap();
        // for post in feed.posts {
        //     // bookmark_count should be present (even if 0)
        //     assert!(post.bookmark_count >= 0);
        // }
    }

    /// Test bookmark count increments when user bookmarks a post
    #[tokio::test]
    #[ignore = "Requires running services"]
    async fn test_bookmark_count_increments() {
        // 1. Get a post's current bookmark_count
        // 2. POST /api/v2/bookmarks to bookmark the post
        // 3. Get the post again
        // 4. Verify bookmark_count increased by 1
    }

    /// Test bookmark count decrements when user unbookmarks a post
    #[tokio::test]
    #[ignore = "Requires running services"]
    async fn test_bookmark_count_decrements() {
        // 1. Bookmark a post
        // 2. Get bookmark_count
        // 3. DELETE /api/v2/bookmarks to unbookmark
        // 4. Get bookmark_count again
        // 5. Verify it decreased by 1
    }
}
