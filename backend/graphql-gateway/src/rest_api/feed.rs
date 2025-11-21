/// Feed API endpoints
///
/// GET /api/v2/feed - Get personalized feed for current user
use actix_web::{web, HttpRequest, HttpResponse, Result};
use tracing::{error, info};

use super::models::{ErrorResponse, FeedPost, GetFeedResponse};
use crate::clients::proto::feed::GetFeedRequest as ProtoGetFeedRequest;
use crate::clients::ServiceClients;

/// GET /api/v2/feed
/// Returns personalized feed for the authenticated user
/// Query parameters:
///   - user_id: The user ID to fetch feed for (required)
///   - limit: Number of posts to return (default: 20, max: 100)
///   - cursor: Pagination cursor for next page (optional)
///   - algorithm: Algorithm variant - "ch", "v2", "hybrid" (default: "v2")
pub async fn get_feed(
    _req: HttpRequest,
    clients: web::Data<ServiceClients>,
    query: web::Query<FeedQueryParams>,
) -> Result<HttpResponse> {
    let user_id = query.user_id.clone();
    let limit = query.limit.unwrap_or(20).min(100);
    let cursor = query.cursor.clone().unwrap_or_default();
    let algorithm = query.algorithm.clone().unwrap_or_else(|| "v2".to_string());

    info!(
        user_id = %user_id,
        limit = %limit,
        cursor = %cursor,
        algorithm = %algorithm,
        "GET /api/v2/feed"
    );

    // Call feed-service via gRPC
    let mut feed_client = clients.feed_client();

    let grpc_request = tonic::Request::new(ProtoGetFeedRequest {
        user_id: user_id.clone(),
        limit: limit as u32,
        cursor,
        algorithm,
    });

    match feed_client.get_feed(grpc_request).await {
        Ok(response) => {
            let grpc_response = response.into_inner();
            let post_count = grpc_response.posts.len();
            let next_cursor = grpc_response.next_cursor;
            let has_more = grpc_response.has_more;

            // Convert gRPC FeedPost to REST FeedPost
            let posts = grpc_response
                .posts
                .into_iter()
                .map(|post| FeedPost {
                    id: post.id,
                    user_id: post.user_id,
                    content: post.content,
                    created_at: post.created_at,
                    ranking_score: post.ranking_score,
                    like_count: post.like_count,
                    comment_count: post.comment_count,
                    share_count: post.share_count,
                })
                .collect();

            info!(
                user_id = %user_id,
                post_count = post_count,
                "Feed retrieved successfully"
            );

            Ok(HttpResponse::Ok().json(GetFeedResponse {
                posts,
                next_cursor: if next_cursor.is_empty() {
                    None
                } else {
                    Some(next_cursor)
                },
                has_more,
            }))
        }
        Err(status) => {
            error!(
                user_id = %user_id,
                error = %status,
                "Failed to get feed from feed-service"
            );

            let error_response = match status.code() {
                tonic::Code::NotFound => {
                    HttpResponse::NotFound().json(ErrorResponse::new("User not found"))
                }
                tonic::Code::Unauthenticated => {
                    HttpResponse::Unauthorized().json(ErrorResponse::new("Unauthorized"))
                }
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid request", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Internal server error",
                    status.message(),
                )),
            };

            Ok(error_response)
        }
    }
}

#[derive(Debug, serde::Deserialize)]
pub struct FeedQueryParams {
    pub user_id: String,
    pub limit: Option<u32>,
    pub cursor: Option<String>,
    pub algorithm: Option<String>,
}
