use actix_web::{delete, get, post, web, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

// ===========================================================================
// Request/Response DTOs
// ===========================================================================

#[derive(Debug, Deserialize)]
pub struct CreatePollRequest {
    pub title: String,
    pub description: Option<String>,
    pub cover_image_url: Option<String>,
    pub poll_type: Option<String>, // "single_choice", "multiple_choice", "ranking"
    pub candidates: Vec<CandidateInput>,
    pub tags: Option<Vec<String>>,
    pub ends_at: Option<String>, // ISO8601 timestamp
}

#[derive(Debug, Deserialize)]
pub struct CandidateInput {
    pub name: String,
    pub avatar_url: Option<String>,
    pub description: Option<String>,
    pub user_id: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct VoteRequest {
    pub candidate_id: String,
}

#[derive(Debug, Deserialize)]
pub struct AddCandidateRequest {
    pub name: String,
    pub avatar_url: Option<String>,
    pub description: Option<String>,
    pub user_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PollResponse {
    pub id: String,
    pub title: String,
    pub description: String,
    pub cover_image_url: String,
    pub creator_id: String,
    pub poll_type: String,
    pub status: String,
    pub total_votes: i64,
    pub candidate_count: i32,
    pub tags: Vec<String>,
    pub created_at: String,
    pub ends_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct CandidateResponse {
    pub id: String,
    pub name: String,
    pub avatar_url: String,
    pub description: String,
    pub user_id: Option<String>,
    pub vote_count: i64,
    pub rank: i32,
    pub rank_change: i32,
    pub vote_percentage: f64,
}

#[derive(Debug, Serialize)]
pub struct GetPollResponse {
    pub poll: PollResponse,
    pub candidates: Vec<CandidateResponse>,
    pub my_voted_candidate_id: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct VoteResponse {
    pub success: bool,
    pub updated_candidate: CandidateResponse,
    pub total_votes: i64,
}

#[derive(Debug, Serialize)]
pub struct RankingsResponse {
    pub rankings: Vec<CandidateResponse>,
    pub total_candidates: i32,
    pub total_votes: i64,
}

#[derive(Debug, Serialize)]
pub struct PollSummaryResponse {
    pub id: String,
    pub title: String,
    pub cover_image_url: String,
    pub poll_type: String,
    pub status: String,
    pub total_votes: i64,
    pub candidate_count: i32,
    pub top_candidates: Vec<CandidatePreviewResponse>,
    pub tags: Vec<String>,
    pub ends_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct CandidatePreviewResponse {
    pub id: String,
    pub name: String,
    pub avatar_url: String,
    pub rank: i32,
}

#[derive(Debug, Serialize)]
pub struct CheckVotedResponse {
    pub has_voted: bool,
    pub voted_candidate_id: Option<String>,
    pub voted_at: Option<String>,
}

// ===========================================================================
// REST API Handlers
// ===========================================================================

/// POST /api/v2/polls - Create a new poll
#[post("/api/v2/polls")]
pub async fn create_poll(
    http_req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<CreatePollRequest>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    info!("Creating poll for user {}: {}", user_id, body.title);

    // TODO: Call poll-service gRPC
    // For now, return a mock response indicating the feature is not yet implemented
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed",
        "message": "The poll-service backend is being set up. Please try again later."
    }))
}

/// GET /api/v2/polls/{poll_id} - Get poll details
#[get("/api/v2/polls/{poll_id}")]
pub async fn get_poll(
    http_req: HttpRequest,
    poll_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
    query: web::Query<GetPollQuery>,
) -> HttpResponse {
    let user_id = http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .map(|u| u.0.to_string());

    info!("Getting poll: {}", poll_id);

    // TODO: Call poll-service gRPC
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed"
    }))
}

#[derive(Debug, Deserialize)]
pub struct GetPollQuery {
    pub include_candidates: Option<bool>,
}

/// POST /api/v2/polls/{poll_id}/vote - Vote on a poll
#[post("/api/v2/polls/{poll_id}/vote")]
pub async fn vote_on_poll(
    http_req: HttpRequest,
    poll_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
    body: web::Json<VoteRequest>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    info!(
        "User {} voting on poll {} for candidate {}",
        user_id, poll_id, body.candidate_id
    );

    // TODO: Call poll-service gRPC
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed"
    }))
}

/// DELETE /api/v2/polls/{poll_id}/vote - Unvote
#[delete("/api/v2/polls/{poll_id}/vote")]
pub async fn unvote(
    http_req: HttpRequest,
    poll_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    info!("User {} unvoting from poll {}", user_id, poll_id);

    // TODO: Call poll-service gRPC
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed"
    }))
}

/// GET /api/v2/polls/{poll_id}/voted - Check if user voted
#[get("/api/v2/polls/{poll_id}/voted")]
pub async fn check_voted(
    http_req: HttpRequest,
    poll_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    // TODO: Call poll-service gRPC
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed"
    }))
}

/// GET /api/v2/polls/{poll_id}/rankings - Get poll rankings
#[get("/api/v2/polls/{poll_id}/rankings")]
pub async fn get_rankings(
    poll_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
    query: web::Query<PaginationQuery>,
) -> HttpResponse {
    info!("Getting rankings for poll: {}", poll_id);

    // TODO: Call poll-service gRPC
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed"
    }))
}

#[derive(Debug, Deserialize)]
pub struct PaginationQuery {
    pub limit: Option<i32>,
    pub offset: Option<i32>,
}

/// GET /api/v2/polls/trending - Get trending polls
#[get("/api/v2/polls/trending")]
pub async fn get_trending_polls(
    clients: web::Data<ServiceClients>,
    query: web::Query<TrendingQuery>,
) -> HttpResponse {
    info!("Getting trending polls");

    // TODO: Call poll-service gRPC
    // For now, return mock data for UI development
    let mock_polls = vec![PollSummaryResponse {
        id: "00000000-0000-0000-0000-000000000001".to_string(),
        title: "Hottest Banker".to_string(),
        cover_image_url: "https://images.unsplash.com/photo-1560472355-536de3962603".to_string(),
        poll_type: "ranking".to_string(),
        status: "active".to_string(),
        total_votes: 12543,
        candidate_count: 5,
        top_candidates: vec![
            CandidatePreviewResponse {
                id: "1".to_string(),
                name: "Alex Chen".to_string(),
                avatar_url: "https://randomuser.me/api/portraits/men/1.jpg".to_string(),
                rank: 1,
            },
            CandidatePreviewResponse {
                id: "2".to_string(),
                name: "Sarah Johnson".to_string(),
                avatar_url: "https://randomuser.me/api/portraits/women/2.jpg".to_string(),
                rank: 2,
            },
            CandidatePreviewResponse {
                id: "3".to_string(),
                name: "Michael Wang".to_string(),
                avatar_url: "https://randomuser.me/api/portraits/men/3.jpg".to_string(),
                rank: 3,
            },
        ],
        tags: vec!["finance".to_string(), "trending".to_string()],
        ends_at: None,
    }];

    HttpResponse::Ok().json(serde_json::json!({
        "polls": mock_polls
    }))
}

#[derive(Debug, Deserialize)]
pub struct TrendingQuery {
    pub limit: Option<i32>,
    pub tags: Option<String>, // comma-separated
}

/// GET /api/v2/polls/active - Get active polls
#[get("/api/v2/polls/active")]
pub async fn get_active_polls(
    clients: web::Data<ServiceClients>,
    query: web::Query<ActivePollsQuery>,
) -> HttpResponse {
    info!("Getting active polls");

    // TODO: Call poll-service gRPC
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed"
    }))
}

#[derive(Debug, Deserialize)]
pub struct ActivePollsQuery {
    pub limit: Option<i32>,
    pub cursor: Option<String>,
    pub tags: Option<String>,
}

/// POST /api/v2/polls/{poll_id}/candidates - Add candidate
#[post("/api/v2/polls/{poll_id}/candidates")]
pub async fn add_candidate(
    http_req: HttpRequest,
    poll_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
    body: web::Json<AddCandidateRequest>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    info!("User {} adding candidate to poll {}", user_id, poll_id);

    // TODO: Call poll-service gRPC
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed"
    }))
}

/// DELETE /api/v2/polls/{poll_id}/candidates/{candidate_id} - Remove candidate
#[delete("/api/v2/polls/{poll_id}/candidates/{candidate_id}")]
pub async fn remove_candidate(
    http_req: HttpRequest,
    path: web::Path<(String, String)>,
    clients: web::Data<ServiceClients>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    let (poll_id, candidate_id) = path.into_inner();
    info!(
        "User {} removing candidate {} from poll {}",
        user_id, candidate_id, poll_id
    );

    // TODO: Call poll-service gRPC
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed"
    }))
}

/// POST /api/v2/polls/{poll_id}/close - Close poll
#[post("/api/v2/polls/{poll_id}/close")]
pub async fn close_poll(
    http_req: HttpRequest,
    poll_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    info!("User {} closing poll {}", user_id, poll_id);

    // TODO: Call poll-service gRPC
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed"
    }))
}

/// DELETE /api/v2/polls/{poll_id} - Delete poll
#[delete("/api/v2/polls/{poll_id}")]
pub async fn delete_poll(
    http_req: HttpRequest,
    poll_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
) -> HttpResponse {
    let user_id = match http_req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            return HttpResponse::Unauthorized().json(serde_json::json!({"error": "Unauthorized"}))
        }
    };

    info!("User {} deleting poll {}", user_id, poll_id);

    // TODO: Call poll-service gRPC
    HttpResponse::NotImplemented().json(serde_json::json!({
        "error": "Poll service not yet deployed"
    }))
}
