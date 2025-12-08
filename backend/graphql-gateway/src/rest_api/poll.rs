// Poll endpoints - connected to social-service gRPC

use actix_web::{delete, get, post, web, HttpMessage, HttpRequest, HttpResponse};
use serde::{Deserialize, Serialize};
use tonic::Request;
use tracing::{error, info};

use crate::clients::proto::social::{
    AddPollCandidateRequest as GrpcAddPollCandidateRequest, CheckPollVotedRequest,
    ClosePollRequest as GrpcClosePollRequest, CreatePollCandidateInput,
    CreatePollRequest as GrpcCreatePollRequest, DeletePollRequest as GrpcDeletePollRequest,
    GetActivePollsRequest, GetPollRankingsRequest, GetPollRequest as GrpcGetPollRequest,
    GetTrendingPollsRequest, RemovePollCandidateRequest as GrpcRemovePollCandidateRequest,
    UnvotePollRequest as GrpcUnvotePollRequest, VoteOnPollRequest as GrpcVoteOnPollRequest,
};
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

#[allow(dead_code)]
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

    let body = body.into_inner();

    // Parse ends_at timestamp if provided
    let ends_at = body.ends_at.as_ref().and_then(|s| {
        chrono::DateTime::parse_from_rfc3339(s)
            .ok()
            .map(|dt| pbjson_types::Timestamp {
                seconds: dt.timestamp(),
                nanos: dt.timestamp_subsec_nanos() as i32,
            })
    });

    // Convert candidate inputs to gRPC format
    let initial_candidates: Vec<CreatePollCandidateInput> = body
        .candidates
        .into_iter()
        .map(|c| CreatePollCandidateInput {
            name: c.name,
            avatar_url: c.avatar_url.unwrap_or_default(),
            description: c.description.unwrap_or_default(),
            user_id: c.user_id.unwrap_or_default(),
        })
        .collect();

    let req = GrpcCreatePollRequest {
        title: body.title,
        description: body.description.unwrap_or_default(),
        cover_image_url: body.cover_image_url.unwrap_or_default(),
        poll_type: body.poll_type.unwrap_or_else(|| "ranking".to_string()),
        tags: body.tags.unwrap_or_default(),
        ends_at,
        initial_candidates,
    };

    // Create request with user_id in metadata
    let mut grpc_req = Request::new(req);
    grpc_req
        .metadata_mut()
        .insert("x-user-id", user_id.parse().unwrap());

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            let r = grpc_req;
            async move { social.create_poll(r).await }
        })
        .await
    {
        Ok(resp) => {
            let poll = match resp.poll {
                Some(p) => PollResponse {
                    id: p.id,
                    title: p.title,
                    description: p.description,
                    cover_image_url: p.cover_image_url,
                    creator_id: p.creator_id,
                    poll_type: p.poll_type,
                    status: p.status,
                    total_votes: p.total_votes,
                    candidate_count: p.candidate_count,
                    tags: p.tags,
                    created_at: p
                        .created_at
                        .map(|ts| {
                            chrono::DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                                .map(|dt| dt.to_rfc3339())
                                .unwrap_or_default()
                        })
                        .unwrap_or_default(),
                    ends_at: p.ends_at.map(|ts| {
                        chrono::DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                            .map(|dt| dt.to_rfc3339())
                            .unwrap_or_default()
                    }),
                },
                None => {
                    return HttpResponse::InternalServerError()
                        .json(serde_json::json!({"error": "Poll creation failed"}))
                }
            };

            let candidates: Vec<CandidateResponse> = resp
                .candidates
                .into_iter()
                .map(|c| CandidateResponse {
                    id: c.id,
                    name: c.name,
                    avatar_url: c.avatar_url,
                    description: c.description,
                    user_id: if c.user_id.is_empty() {
                        None
                    } else {
                        Some(c.user_id)
                    },
                    vote_count: c.vote_count,
                    rank: c.rank,
                    rank_change: c.rank_change,
                    vote_percentage: c.vote_percentage,
                })
                .collect();

            HttpResponse::Created().json(serde_json::json!({
                "poll": poll,
                "candidates": candidates
            }))
        }
        Err(e) => {
            error!("create_poll failed: {}", e);
            HttpResponse::ServiceUnavailable()
                .json(serde_json::json!({"error": "Failed to create poll"}))
        }
    }
}

/// GET /api/v2/polls/{poll_id} - Get poll details
#[get("/api/v2/polls/{poll_id}")]
pub async fn get_poll(
    http_req: HttpRequest,
    poll_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
    query: web::Query<GetPollQuery>,
) -> HttpResponse {
    let _user_id = http_req
        .extensions()
        .get::<AuthenticatedUser>()
        .map(|u| u.0.to_string());

    let poll_id_str = poll_id.into_inner();
    info!("Getting poll: {}", poll_id_str);

    let q = query.into_inner();
    let req = GrpcGetPollRequest {
        poll_id: poll_id_str,
        include_candidates: q.include_candidates.unwrap_or(true),
    };

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.get_poll(req).await }
        })
        .await
    {
        Ok(resp) => {
            let poll = match resp.poll {
                Some(p) => PollResponse {
                    id: p.id,
                    title: p.title,
                    description: p.description,
                    cover_image_url: p.cover_image_url,
                    creator_id: p.creator_id,
                    poll_type: p.poll_type,
                    status: p.status,
                    total_votes: p.total_votes,
                    candidate_count: p.candidate_count,
                    tags: p.tags,
                    created_at: p
                        .created_at
                        .map(|ts| {
                            chrono::DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                                .map(|dt| dt.to_rfc3339())
                                .unwrap_or_default()
                        })
                        .unwrap_or_default(),
                    ends_at: p.ends_at.map(|ts| {
                        chrono::DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                            .map(|dt| dt.to_rfc3339())
                            .unwrap_or_default()
                    }),
                },
                None => {
                    return HttpResponse::NotFound()
                        .json(serde_json::json!({"error": "Poll not found"}))
                }
            };

            let candidates: Vec<CandidateResponse> = resp
                .candidates
                .into_iter()
                .map(|c| CandidateResponse {
                    id: c.id,
                    name: c.name,
                    avatar_url: c.avatar_url,
                    description: c.description,
                    user_id: if c.user_id.is_empty() {
                        None
                    } else {
                        Some(c.user_id)
                    },
                    vote_count: c.vote_count,
                    rank: c.rank,
                    rank_change: c.rank_change,
                    vote_percentage: c.vote_percentage,
                })
                .collect();

            let my_voted = if resp.my_voted_candidate_id.is_empty() {
                None
            } else {
                Some(resp.my_voted_candidate_id)
            };

            HttpResponse::Ok().json(GetPollResponse {
                poll,
                candidates,
                my_voted_candidate_id: my_voted,
            })
        }
        Err(e) => {
            error!("get_poll failed: {}", e);
            HttpResponse::ServiceUnavailable()
                .json(serde_json::json!({"error": "Failed to fetch poll"}))
        }
    }
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

    let poll_id_str = poll_id.into_inner();
    let candidate_id = body.into_inner().candidate_id;

    info!(
        "User {} voting on poll {} for candidate {}",
        user_id, poll_id_str, candidate_id
    );

    let req = GrpcVoteOnPollRequest {
        poll_id: poll_id_str,
        candidate_id,
    };

    // Create request with user_id in metadata
    let mut grpc_req = Request::new(req);
    grpc_req
        .metadata_mut()
        .insert("x-user-id", user_id.parse().unwrap());

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            let r = grpc_req;
            async move { social.vote_on_poll(r).await }
        })
        .await
    {
        Ok(resp) => {
            let updated_candidate = resp.updated_candidate.map(|c| CandidateResponse {
                id: c.id,
                name: c.name,
                avatar_url: c.avatar_url,
                description: c.description,
                user_id: if c.user_id.is_empty() {
                    None
                } else {
                    Some(c.user_id)
                },
                vote_count: c.vote_count,
                rank: c.rank,
                rank_change: c.rank_change,
                vote_percentage: c.vote_percentage,
            });

            HttpResponse::Ok().json(serde_json::json!({
                "success": resp.success,
                "updated_candidate": updated_candidate,
                "total_votes": resp.total_votes
            }))
        }
        Err(e) => {
            let err_str = e.to_string();
            if err_str.contains("already voted") || err_str.contains("AlreadyExists") {
                HttpResponse::Conflict()
                    .json(serde_json::json!({"error": "Already voted on this poll"}))
            } else {
                error!("vote_on_poll failed: {}", e);
                HttpResponse::ServiceUnavailable()
                    .json(serde_json::json!({"error": "Failed to vote"}))
            }
        }
    }
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

    let poll_id_str = poll_id.into_inner();
    info!("User {} unvoting from poll {}", user_id, poll_id_str);

    let req = GrpcUnvotePollRequest {
        poll_id: poll_id_str,
    };

    // Create request with user_id in metadata
    let mut grpc_req = Request::new(req);
    grpc_req
        .metadata_mut()
        .insert("x-user-id", user_id.parse().unwrap());

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            let r = grpc_req;
            async move { social.unvote_poll(r).await }
        })
        .await
    {
        Ok(resp) => HttpResponse::Ok().json(serde_json::json!({
            "success": resp.success,
            "total_votes": resp.total_votes
        })),
        Err(e) => {
            error!("unvote failed: {}", e);
            HttpResponse::ServiceUnavailable()
                .json(serde_json::json!({"error": "Failed to unvote"}))
        }
    }
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

    let poll_id_str = poll_id.into_inner();
    info!("Checking if user {} voted on poll {}", user_id, poll_id_str);

    let req = CheckPollVotedRequest {
        poll_id: poll_id_str,
    };

    // Create request with user_id in metadata
    let mut grpc_req = Request::new(req);
    grpc_req
        .metadata_mut()
        .insert("x-user-id", user_id.parse().unwrap());

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            let r = grpc_req;
            async move { social.check_poll_voted(r).await }
        })
        .await
    {
        Ok(resp) => {
            let voted_at = resp.voted_at.map(|ts| {
                chrono::DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                    .map(|dt| dt.to_rfc3339())
                    .unwrap_or_default()
            });

            HttpResponse::Ok().json(CheckVotedResponse {
                has_voted: resp.has_voted,
                voted_candidate_id: if resp.voted_candidate_id.is_empty() {
                    None
                } else {
                    Some(resp.voted_candidate_id)
                },
                voted_at,
            })
        }
        Err(e) => {
            error!("check_voted failed: {}", e);
            HttpResponse::ServiceUnavailable()
                .json(serde_json::json!({"error": "Failed to check vote status"}))
        }
    }
}

/// GET /api/v2/polls/{poll_id}/rankings - Get poll rankings
#[get("/api/v2/polls/{poll_id}/rankings")]
pub async fn get_rankings(
    poll_id: web::Path<String>,
    clients: web::Data<ServiceClients>,
    query: web::Query<PaginationQuery>,
) -> HttpResponse {
    let poll_id_str = poll_id.into_inner();
    info!("Getting rankings for poll: {}", poll_id_str);

    let q = query.into_inner();
    let req = GetPollRankingsRequest {
        poll_id: poll_id_str,
        limit: q.limit.unwrap_or(20),
        offset: q.offset.unwrap_or(0),
    };

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.get_poll_rankings(req).await }
        })
        .await
    {
        Ok(resp) => {
            let rankings: Vec<CandidateResponse> = resp
                .rankings
                .into_iter()
                .map(|c| CandidateResponse {
                    id: c.id,
                    name: c.name,
                    avatar_url: c.avatar_url,
                    description: c.description,
                    user_id: if c.user_id.is_empty() {
                        None
                    } else {
                        Some(c.user_id)
                    },
                    vote_count: c.vote_count,
                    rank: c.rank,
                    rank_change: c.rank_change,
                    vote_percentage: c.vote_percentage,
                })
                .collect();

            HttpResponse::Ok().json(RankingsResponse {
                rankings,
                total_candidates: resp.total_candidates,
                total_votes: resp.total_votes,
            })
        }
        Err(e) => {
            error!("get_rankings failed: {}", e);
            HttpResponse::ServiceUnavailable()
                .json(serde_json::json!({"error": "Failed to fetch rankings"}))
        }
    }
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

    let q = query.into_inner();
    let tags: Vec<String> = q
        .tags
        .map(|t| t.split(',').map(|s| s.trim().to_string()).collect())
        .unwrap_or_default();

    let req = GetTrendingPollsRequest {
        limit: q.limit.unwrap_or(10),
        tags,
    };

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.get_trending_polls(req).await }
        })
        .await
    {
        Ok(resp) => {
            // Convert gRPC response to REST response format
            let polls: Vec<PollSummaryResponse> = resp
                .polls
                .into_iter()
                .map(|p| PollSummaryResponse {
                    id: p.id,
                    title: p.title,
                    cover_image_url: p.cover_image_url,
                    poll_type: p.poll_type,
                    status: p.status,
                    total_votes: p.total_votes,
                    candidate_count: p.candidate_count,
                    top_candidates: p
                        .top_candidates
                        .into_iter()
                        .map(|c| CandidatePreviewResponse {
                            id: c.id,
                            name: c.name,
                            avatar_url: c.avatar_url,
                            rank: c.rank,
                        })
                        .collect(),
                    tags: p.tags,
                    ends_at: p.ends_at.map(|ts| {
                        chrono::DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                            .map(|dt| dt.to_rfc3339())
                            .unwrap_or_default()
                    }),
                })
                .collect();

            HttpResponse::Ok().json(serde_json::json!({ "polls": polls }))
        }
        Err(e) => {
            error!("get_trending_polls failed: {}", e);
            HttpResponse::ServiceUnavailable().json(serde_json::json!({
                "error": "Failed to fetch trending polls"
            }))
        }
    }
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

    let q = query.into_inner();
    let tags: Vec<String> = q
        .tags
        .map(|t| t.split(',').map(|s| s.trim().to_string()).collect())
        .unwrap_or_default();

    // Parse cursor as offset (simple implementation)
    let offset = q
        .cursor
        .as_ref()
        .and_then(|c| c.parse::<i32>().ok())
        .unwrap_or(0);

    let req = GetActivePollsRequest {
        limit: q.limit.unwrap_or(20),
        offset,
        tags,
    };

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            async move { social.get_active_polls(req).await }
        })
        .await
    {
        Ok(resp) => {
            let polls: Vec<PollSummaryResponse> = resp
                .polls
                .into_iter()
                .map(|p| PollSummaryResponse {
                    id: p.id,
                    title: p.title,
                    cover_image_url: p.cover_image_url,
                    poll_type: p.poll_type,
                    status: p.status,
                    total_votes: p.total_votes,
                    candidate_count: p.candidate_count,
                    top_candidates: p
                        .top_candidates
                        .into_iter()
                        .map(|c| CandidatePreviewResponse {
                            id: c.id,
                            name: c.name,
                            avatar_url: c.avatar_url,
                            rank: c.rank,
                        })
                        .collect(),
                    tags: p.tags,
                    ends_at: p.ends_at.map(|ts| {
                        chrono::DateTime::from_timestamp(ts.seconds, ts.nanos as u32)
                            .map(|dt| dt.to_rfc3339())
                            .unwrap_or_default()
                    }),
                })
                .collect();

            HttpResponse::Ok().json(serde_json::json!({
                "polls": polls,
                "total": resp.total
            }))
        }
        Err(e) => {
            error!("get_active_polls failed: {}", e);
            HttpResponse::ServiceUnavailable().json(serde_json::json!({
                "error": "Failed to fetch active polls"
            }))
        }
    }
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

    let poll_id_str = poll_id.into_inner();
    let body = body.into_inner();
    info!("User {} adding candidate to poll {}", user_id, poll_id_str);

    let req = GrpcAddPollCandidateRequest {
        poll_id: poll_id_str,
        name: body.name,
        avatar_url: body.avatar_url.unwrap_or_default(),
        description: body.description.unwrap_or_default(),
        user_id: body.user_id.unwrap_or_default(),
    };

    // Create request with user_id in metadata
    let mut grpc_req = Request::new(req);
    grpc_req
        .metadata_mut()
        .insert("x-user-id", user_id.parse().unwrap());

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            let r = grpc_req;
            async move { social.add_poll_candidate(r).await }
        })
        .await
    {
        Ok(resp) => {
            let candidate = resp.candidate.map(|c| CandidateResponse {
                id: c.id,
                name: c.name,
                avatar_url: c.avatar_url,
                description: c.description,
                user_id: if c.user_id.is_empty() {
                    None
                } else {
                    Some(c.user_id)
                },
                vote_count: c.vote_count,
                rank: c.rank,
                rank_change: c.rank_change,
                vote_percentage: c.vote_percentage,
            });

            HttpResponse::Created().json(serde_json::json!({
                "candidate": candidate
            }))
        }
        Err(e) => {
            let err_str = e.to_string();
            if err_str.contains("permission") || err_str.contains("PermissionDenied") {
                HttpResponse::Forbidden()
                    .json(serde_json::json!({"error": "Only poll creator can add candidates"}))
            } else if err_str.contains("not found") || err_str.contains("NotFound") {
                HttpResponse::NotFound().json(serde_json::json!({"error": "Poll not found"}))
            } else {
                error!("add_candidate failed: {}", e);
                HttpResponse::ServiceUnavailable()
                    .json(serde_json::json!({"error": "Failed to add candidate"}))
            }
        }
    }
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

    let req = GrpcRemovePollCandidateRequest {
        poll_id,
        candidate_id,
    };

    let mut grpc_req = Request::new(req);
    grpc_req
        .metadata_mut()
        .insert("x-user-id", user_id.parse().unwrap());

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            let r = grpc_req;
            async move { social.remove_poll_candidate(r).await }
        })
        .await
    {
        Ok(_) => HttpResponse::NoContent().finish(),
        Err(e) => {
            let err_str = e.to_string();
            if err_str.contains("permission") || err_str.contains("PermissionDenied") {
                HttpResponse::Forbidden()
                    .json(serde_json::json!({"error": "Only poll creator can remove candidates"}))
            } else if err_str.contains("not found") || err_str.contains("NotFound") {
                HttpResponse::NotFound()
                    .json(serde_json::json!({"error": "Poll or candidate not found"}))
            } else {
                error!("remove_candidate failed: {}", e);
                HttpResponse::ServiceUnavailable()
                    .json(serde_json::json!({"error": "Failed to remove candidate"}))
            }
        }
    }
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

    let poll_id_str = poll_id.into_inner();
    info!("User {} closing poll {}", user_id, poll_id_str);

    let req = GrpcClosePollRequest {
        poll_id: poll_id_str,
    };

    let mut grpc_req = Request::new(req);
    grpc_req
        .metadata_mut()
        .insert("x-user-id", user_id.parse().unwrap());

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            let r = grpc_req;
            async move { social.close_poll(r).await }
        })
        .await
    {
        Ok(_) => HttpResponse::Ok().json(serde_json::json!({"success": true})),
        Err(e) => {
            let err_str = e.to_string();
            if err_str.contains("permission") || err_str.contains("PermissionDenied") {
                HttpResponse::Forbidden()
                    .json(serde_json::json!({"error": "Only poll creator can close the poll"}))
            } else if err_str.contains("not found") || err_str.contains("NotFound") {
                HttpResponse::NotFound().json(serde_json::json!({"error": "Poll not found"}))
            } else {
                error!("close_poll failed: {}", e);
                HttpResponse::ServiceUnavailable()
                    .json(serde_json::json!({"error": "Failed to close poll"}))
            }
        }
    }
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

    let poll_id_str = poll_id.into_inner();
    info!("User {} deleting poll {}", user_id, poll_id_str);

    let req = GrpcDeletePollRequest {
        poll_id: poll_id_str,
    };

    let mut grpc_req = Request::new(req);
    grpc_req
        .metadata_mut()
        .insert("x-user-id", user_id.parse().unwrap());

    match clients
        .call_social(|| {
            let mut social = clients.social_client();
            let r = grpc_req;
            async move { social.delete_poll(r).await }
        })
        .await
    {
        Ok(_) => HttpResponse::NoContent().finish(),
        Err(e) => {
            let err_str = e.to_string();
            if err_str.contains("permission") || err_str.contains("PermissionDenied") {
                HttpResponse::Forbidden()
                    .json(serde_json::json!({"error": "Only poll creator can delete the poll"}))
            } else if err_str.contains("not found") || err_str.contains("NotFound") {
                HttpResponse::NotFound().json(serde_json::json!({"error": "Poll not found"}))
            } else {
                error!("delete_poll failed: {}", e);
                HttpResponse::ServiceUnavailable()
                    .json(serde_json::json!({"error": "Failed to delete poll"}))
            }
        }
    }
}
