use crate::services::{ClickHouseClient, ElasticsearchClient, RedisCache};
use chrono::Utc;
use std::sync::Arc;
use std::time::Instant;
use tonic::{Request, Response, Status};
use tracing::{error, info, warn};
use uuid::Uuid;

pub mod nova {
    pub mod search_service {
        pub mod v2 {
            tonic::include_proto!("nova.search_service.v2");
        }
        pub use v2::*;
    }
}

use nova::search_service::v2::search_service_server::SearchService;
use nova::search_service::v2::*;

#[derive(Clone)]
pub struct SearchServiceImpl {
    es_client: Arc<ElasticsearchClient>,
    ch_client: Arc<ClickHouseClient>,
    redis: Arc<RedisCache>,
}

impl SearchServiceImpl {
    pub fn new(
        es_client: ElasticsearchClient,
        ch_client: ClickHouseClient,
        redis: RedisCache,
    ) -> Self {
        Self {
            es_client: Arc::new(es_client),
            ch_client: Arc::new(ch_client),
            redis: Arc::new(redis),
        }
    }
}

#[tonic::async_trait]
impl SearchService for SearchServiceImpl {
    async fn full_text_search(
        &self,
        request: Request<FullTextSearchRequest>,
    ) -> Result<Response<FullTextSearchResponse>, Status> {
        let start_time = Instant::now();
        let req = request.into_inner();

        let query = req.query.trim();
        if query.is_empty() {
            return Err(Status::invalid_argument("Query cannot be empty"));
        }

        let limit = req.limit.max(1).min(100) as i64;
        let offset = req.offset.max(0) as i64;

        // Try cache first
        let cache_key = format!("{}:{}:{}", query, limit, offset);
        if let Ok(cached) = self.redis.get_search_results_cache(&cache_key).await {
            info!("Cache hit for query: {}", query);
            return Ok(Response::new(FullTextSearchResponse {
                results: vec![], // TODO: reconstruct from cached IDs
                total_count: cached.total_count,
                search_time_ms: "0".to_string(),
            }));
        }

        // Perform search with fallback
        let search_result = match self.es_client.full_text_search(query, limit, offset).await {
            Ok(results) => results,
            Err(e) => {
                error!("Elasticsearch error: {}", e);
                // Fallback to cached results if available
                if let Ok(cached) = self.redis.get_search_results_cache(&cache_key).await {
                    warn!("Using fallback cache for query: {}", query);
                    return Ok(Response::new(FullTextSearchResponse {
                        results: vec![],
                        total_count: cached.total_count,
                        search_time_ms: "0".to_string(),
                    }));
                }
                return Err(Status::internal("Search service unavailable"));
            }
        };

        let mut results = Vec::new();

        // Add post results
        for post in search_result.posts.iter().take(limit as usize) {
            results.push(SearchResult {
                id: post.id.to_string(),
                r#type: "post".to_string(),
                title: post.title.clone().unwrap_or_default(),
                description: post.content.clone().unwrap_or_default(),
                thumbnail_url: String::new(),
                relevance_score: 1.0,
                created_at: post.created_at.timestamp(),
                url_slug: format!("/posts/{}", post.id),
            });
        }

        // Add user results
        for user in search_result.users.iter().take(10) {
            results.push(SearchResult {
                id: user.user_id.to_string(),
                r#type: "user".to_string(),
                title: user.username.clone(),
                description: user.bio.clone().unwrap_or_default(),
                thumbnail_url: String::new(),
                relevance_score: 0.9,
                created_at: 0,
                url_slug: format!("/users/{}", user.username),
            });
        }

        // Add hashtag results
        for tag in search_result.hashtags.iter().take(5) {
            results.push(SearchResult {
                id: tag.clone(),
                r#type: "hashtag".to_string(),
                title: format!("#{}", tag),
                description: String::new(),
                thumbnail_url: String::new(),
                relevance_score: 0.8,
                created_at: 0,
                url_slug: format!("/hashtags/{}", tag),
            });
        }

        let total_count = results.len() as i32;
        let search_time_ms = start_time.elapsed().as_millis().to_string();

        // Cache results asynchronously
        let redis_clone = self.redis.clone();
        let cache_key_clone = cache_key.clone();
        tokio::spawn(async move {
            let _ = redis_clone
                .set_search_results_cache(
                    &cache_key_clone,
                    &crate::services::redis_cache::CachedSearchResults {
                        post_ids: vec![],
                        user_ids: vec![],
                        hashtags: vec![],
                        total_count,
                    },
                )
                .await;
        });

        Ok(Response::new(FullTextSearchResponse {
            results,
            total_count,
            search_time_ms,
        }))
    }

    async fn search_posts(
        &self,
        request: Request<SearchPostsRequest>,
    ) -> Result<Response<SearchPostsResponse>, Status> {
        let req = request.into_inner();

        let query = req.query.trim();
        if query.is_empty() {
            return Err(Status::invalid_argument("Query cannot be empty"));
        }

        let limit = req.limit.max(1).min(100) as i64;
        let offset = req.offset.max(0) as i64;

        let posts = self
            .es_client
            .search_posts(query, limit, offset)
            .await
            .map_err(|e| {
                error!("Failed to search posts: {}", e);
                Status::internal("Failed to search posts")
            })?;

        let results: Vec<PostSearchResult> = posts
            .into_iter()
            .map(|post| PostSearchResult {
                id: post.id.to_string(),
                author_id: post.user_id.to_string(),
                title: post.title.unwrap_or_default(),
                content: post.content.unwrap_or_default(),
                image_key: String::new(),
                like_count: post.likes_count,
                comment_count: post.comments_count,
                relevance_score: 1.0,
                created_at: post.created_at.timestamp(),
            })
            .collect();

        let total_count = results.len() as i32;

        Ok(Response::new(SearchPostsResponse {
            posts: results,
            total_count,
        }))
    }

    async fn search_users(
        &self,
        request: Request<SearchUsersRequest>,
    ) -> Result<Response<SearchUsersResponse>, Status> {
        let req = request.into_inner();

        let query = req.query.trim();
        if query.is_empty() {
            return Err(Status::invalid_argument("Query cannot be empty"));
        }

        let limit = req.limit.max(1).min(100) as i64;
        let offset = req.offset.max(0) as i64;

        let users = self
            .es_client
            .search_users(query, limit, offset, req.verified_only)
            .await
            .map_err(|e| {
                error!("Failed to search users: {}", e);
                Status::internal("Failed to search users")
            })?;

        let results: Vec<UserSearchResult> = users
            .into_iter()
            .map(|user| UserSearchResult {
                user_id: user.user_id.to_string(),
                username: user.username,
                display_name: user.display_name,
                bio: user.bio.unwrap_or_default(),
                avatar_url: String::new(),
                is_verified: user.is_verified,
                follower_count: user.follower_count,
                relevance_score: 1.0,
            })
            .collect();

        let total_count = results.len() as i32;

        Ok(Response::new(SearchUsersResponse {
            users: results,
            total_count,
        }))
    }

    async fn search_hashtags(
        &self,
        request: Request<SearchHashtagsRequest>,
    ) -> Result<Response<SearchHashtagsResponse>, Status> {
        let req = request.into_inner();

        let query = req.query.trim().trim_start_matches('#');
        if query.is_empty() {
            return Err(Status::invalid_argument("Query cannot be empty"));
        }

        let limit = req.limit.max(1).min(100) as i64;

        let tags = self
            .es_client
            .search_hashtags(query, limit)
            .await
            .map_err(|e| {
                error!("Failed to search hashtags: {}", e);
                Status::internal("Failed to search hashtags")
            })?;

        let results: Vec<HashtagSearchResult> = tags
            .into_iter()
            .map(|tag| HashtagSearchResult {
                id: Uuid::new_v4().to_string(),
                tag: tag.clone(),
                post_count: 0, // TODO: Get from aggregation
                usage_count: 0,
                trending_status: "stable".to_string(),
                created_at: Utc::now().timestamp(),
            })
            .collect();

        let total_count = results.len() as i32;

        Ok(Response::new(SearchHashtagsResponse {
            hashtags: results,
            total_count,
        }))
    }

    async fn get_posts_by_hashtag(
        &self,
        request: Request<GetPostsByHashtagRequest>,
    ) -> Result<Response<GetPostsByHashtagResponse>, Status> {
        let req = request.into_inner();

        let hashtag = req.hashtag.trim().trim_start_matches('#');
        if hashtag.is_empty() {
            return Err(Status::invalid_argument("Hashtag cannot be empty"));
        }

        let limit = req.limit.max(1).min(100) as i64;
        let offset = req.offset.max(0) as i64;

        // Search posts with exact hashtag match
        let posts = self
            .es_client
            .search_posts(hashtag, limit, offset)
            .await
            .map_err(|e| {
                error!("Failed to get posts by hashtag: {}", e);
                Status::internal("Failed to get posts by hashtag")
            })?;

        let results: Vec<PostSearchResult> = posts
            .into_iter()
            .filter(|post| post.tags.contains(&hashtag.to_string()))
            .map(|post| PostSearchResult {
                id: post.id.to_string(),
                author_id: post.user_id.to_string(),
                title: post.title.unwrap_or_default(),
                content: post.content.unwrap_or_default(),
                image_key: String::new(),
                like_count: post.likes_count,
                comment_count: post.comments_count,
                relevance_score: 1.0,
                created_at: post.created_at.timestamp(),
            })
            .collect();

        let total_count = results.len() as i32;

        Ok(Response::new(GetPostsByHashtagResponse {
            posts: results,
            total_count,
        }))
    }

    async fn get_search_suggestions(
        &self,
        request: Request<GetSearchSuggestionsRequest>,
    ) -> Result<Response<GetSearchSuggestionsResponse>, Status> {
        let req = request.into_inner();

        let partial_query = req.partial_query.trim().to_lowercase();
        if partial_query.is_empty() {
            return Ok(Response::new(GetSearchSuggestionsResponse {
                suggestions: vec![],
            }));
        }

        let limit = req.limit.max(1).min(20);

        // Try cache first
        if let Ok(cached) = self.redis.get_search_suggestions(&partial_query).await {
            let suggestions: Vec<get_search_suggestions_response::Suggestion> = cached
                .into_iter()
                .take(limit as usize)
                .map(|text| get_search_suggestions_response::Suggestion {
                    text,
                    r#type: "query".to_string(),
                    popularity: 0,
                })
                .collect();

            return Ok(Response::new(GetSearchSuggestionsResponse { suggestions }));
        }

        // Get suggestions from Elasticsearch (hashtags)
        let hashtags = self
            .es_client
            .search_hashtags(&partial_query, limit as i64)
            .await
            .unwrap_or_default();

        let suggestions: Vec<get_search_suggestions_response::Suggestion> = hashtags
            .into_iter()
            .map(|tag| get_search_suggestions_response::Suggestion {
                text: tag,
                r#type: "hashtag".to_string(),
                popularity: 0,
            })
            .collect();

        // Cache suggestions asynchronously
        let redis_clone = self.redis.clone();
        let partial_query_clone = partial_query.clone();
        let suggestion_texts: Vec<String> = suggestions.iter().map(|s| s.text.clone()).collect();
        tokio::spawn(async move {
            let _ = redis_clone
                .set_search_suggestions(&partial_query_clone, &suggestion_texts)
                .await;
        });

        Ok(Response::new(GetSearchSuggestionsResponse { suggestions }))
    }

    async fn advanced_search(
        &self,
        _request: Request<AdvancedSearchRequest>,
    ) -> Result<Response<AdvancedSearchResponse>, Status> {
        // TODO: Implement advanced search with filters
        Err(Status::unimplemented("advanced_search not implemented yet"))
    }

    async fn record_search_query(
        &self,
        request: Request<RecordSearchQueryRequest>,
    ) -> Result<Response<RecordSearchQueryResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|_| Status::invalid_argument("Invalid user_id"))?;

        // Record search event to ClickHouse asynchronously
        let ch_clone = self.ch_client.clone();
        let query = req.query.clone();
        let result_count = req.result_count;
        tokio::spawn(async move {
            let event = crate::services::clickhouse::SearchEvent {
                timestamp: Utc::now(),
                user_id,
                query,
                results_count: result_count as u32,
                clicked_type: None,
                clicked_id: None,
                session_id: Uuid::new_v4(),
            };

            if let Err(e) = ch_clone.record_search_event(event).await {
                error!("Failed to record search event: {}", e);
            }
        });

        Ok(Response::new(RecordSearchQueryResponse { success: true }))
    }

    async fn get_trending_searches(
        &self,
        request: Request<GetTrendingSearchesRequest>,
    ) -> Result<Response<GetTrendingSearchesResponse>, Status> {
        let req = request.into_inner();

        let limit = req.limit.max(1).min(50) as u32;
        let time_window = if req.time_window.is_empty() {
            "24h"
        } else {
            &req.time_window
        };

        // Try cache first
        if let Ok(cached) = self.redis.get_trending_searches(time_window).await {
            let searches: Vec<get_trending_searches_response::TrendingSearch> = cached
                .into_iter()
                .take(limit as usize)
                .map(|item| get_trending_searches_response::TrendingSearch {
                    query: item.query,
                    search_count: item.search_count as i32,
                    trend_score: item.trend_score,
                })
                .collect();

            return Ok(Response::new(GetTrendingSearchesResponse { searches }));
        }

        // Get from ClickHouse
        let trending = self
            .ch_client
            .get_trending_searches(limit, time_window)
            .await
            .map_err(|e| {
                error!("Failed to get trending searches: {}", e);
                Status::internal("Failed to get trending searches")
            })?;

        let searches: Vec<get_trending_searches_response::TrendingSearch> = trending
            .iter()
            .map(|item| get_trending_searches_response::TrendingSearch {
                query: item.query.clone(),
                search_count: item.search_count as i32,
                trend_score: item.trend_score,
            })
            .collect();

        // Cache results asynchronously
        let redis_clone = self.redis.clone();
        let time_window_clone = time_window.to_string();
        let cache_data: Vec<crate::services::redis_cache::TrendingSearchCache> = trending
            .into_iter()
            .map(|item| crate::services::redis_cache::TrendingSearchCache {
                query: item.query,
                search_count: item.search_count,
                trend_score: item.trend_score,
            })
            .collect();
        tokio::spawn(async move {
            let _ = redis_clone
                .set_trending_searches(&time_window_clone, &cache_data)
                .await;
        });

        Ok(Response::new(GetTrendingSearchesResponse { searches }))
    }

    async fn get_search_analytics(
        &self,
        request: Request<GetSearchAnalyticsRequest>,
    ) -> Result<Response<GetSearchAnalyticsResponse>, Status> {
        let req = request.into_inner();

        if req.query.is_empty() {
            return Err(Status::invalid_argument("Query cannot be empty"));
        }

        let analytics = self
            .ch_client
            .get_search_analytics(&req.query, 24)
            .await
            .map_err(|e| {
                error!("Failed to get search analytics: {}", e);
                Status::internal("Failed to get search analytics")
            })?;

        Ok(Response::new(GetSearchAnalyticsResponse {
            total_searches: analytics.total_searches as i32,
            avg_results: analytics.avg_results as i32,
            click_through_rate: analytics.click_through_rate as i32,
            popular_filters: vec![],
        }))
    }
}
