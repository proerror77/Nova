//! Photo Analysis API endpoints
//!
//! POST /api/v2/photo-analysis/upload - Upload iOS Vision photo analysis results
//! POST /api/v2/photo-analysis/onboarding - Upload onboarding interest selections
//!
//! These endpoints forward photo analysis data to ranking-service for user profile building

use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info, warn};

use crate::clients::proto::ranking::{
    PhotoAnalysisSource, PhotoTheme, UploadOnboardingInterestsRequest, UploadPhotoAnalysisRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

// MARK: - Request/Response Models

/// Photo theme detected by iOS Vision
#[derive(Debug, Deserialize)]
pub struct PhotoThemeRequest {
    pub theme: String,
    pub confidence: f32,
    pub photo_count: i32,
    #[serde(default)]
    pub sub_categories: Vec<String>,
}

/// Request to upload photo analysis results
#[derive(Debug, Deserialize)]
pub struct UploadPhotoAnalysisHttpRequest {
    /// List of detected photo themes
    pub detected_themes: Vec<PhotoThemeRequest>,
    /// ISO 8601 timestamp of when analysis was performed
    #[serde(default)]
    pub analyzed_at: Option<String>,
    /// Total number of photos analyzed
    pub photo_count: i32,
    /// Source of the analysis (default: ios_vision)
    #[serde(default = "default_source")]
    pub source: String,
}

fn default_source() -> String {
    "ios_vision".to_string()
}

/// Response from photo analysis upload
#[derive(Debug, Serialize)]
pub struct UploadPhotoAnalysisHttpResponse {
    pub success: bool,
    pub interests_created: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_message: Option<String>,
}

/// Request to upload onboarding interests
#[derive(Debug, Deserialize)]
pub struct UploadOnboardingInterestsHttpRequest {
    /// List of selected channel/interest IDs
    pub selected_channels: Vec<String>,
    /// ISO 8601 timestamp of when selection was made
    #[serde(default)]
    pub selected_at: Option<String>,
}

/// Response from onboarding interests upload
#[derive(Debug, Serialize)]
pub struct UploadOnboardingInterestsHttpResponse {
    pub success: bool,
    pub interests_created: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_message: Option<String>,
}

// MARK: - API Handlers

/// POST /api/v2/photo-analysis/upload
/// Upload iOS Vision photo analysis results to build user interest profile
pub async fn upload_photo_analysis(
    req: HttpRequest,
    body: web::Json<UploadPhotoAnalysisHttpRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    // Extract user ID from JWT token
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            warn!("POST /api/v2/photo-analysis/upload: Missing user context");
            return Ok(HttpResponse::Unauthorized().json(serde_json::json!({
                "error": "Missing user context",
                "code": 401
            })));
        }
    };

    info!(
        user_id = %user_id,
        theme_count = body.detected_themes.len(),
        photo_count = body.photo_count,
        "POST /api/v2/photo-analysis/upload"
    );

    // Convert source string to enum
    let source = match body.source.as_str() {
        "ios_vision" => PhotoAnalysisSource::IosVision,
        "server_ml" => PhotoAnalysisSource::ServerMl,
        "combined" => PhotoAnalysisSource::Combined,
        _ => PhotoAnalysisSource::IosVision,
    };

    // Convert photo themes to protobuf format
    let detected_themes: Vec<PhotoTheme> = body
        .detected_themes
        .iter()
        .map(|t| PhotoTheme {
            theme: t.theme.clone(),
            confidence: t.confidence,
            photo_count: t.photo_count,
            sub_categories: t.sub_categories.clone(),
        })
        .collect();

    // Build gRPC request
    let grpc_request = UploadPhotoAnalysisRequest {
        user_id: user_id.clone(),
        detected_themes,
        analyzed_at: body
            .analyzed_at
            .clone()
            .unwrap_or_else(|| chrono::Utc::now().to_rfc3339()),
        photo_count: body.photo_count,
        source: source.into(),
    };

    // Call ranking-service via gRPC with circuit breaker
    let mut client = clients.ranking_client();
    match clients
        .call_ranking(|| async { client.upload_photo_analysis(grpc_request.clone()).await })
        .await
    {
        Ok(response) => {
            info!(
                user_id = %user_id,
                interests_created = response.interests_created,
                "Photo analysis uploaded successfully"
            );

            Ok(HttpResponse::Ok().json(UploadPhotoAnalysisHttpResponse {
                success: response.success,
                interests_created: response.interests_created,
                error_message: if response.error_message.is_empty() {
                    None
                } else {
                    Some(response.error_message)
                },
            }))
        }
        Err(e) => {
            error!(
                user_id = %user_id,
                error = %e,
                "Failed to upload photo analysis"
            );

            Ok(HttpResponse::BadGateway().json(serde_json::json!({
                "error": "Failed to process photo analysis",
                "message": format!("{}", e),
                "code": 502
            })))
        }
    }
}

/// POST /api/v2/photo-analysis/onboarding
/// Upload onboarding interest selections
pub async fn upload_onboarding_interests(
    req: HttpRequest,
    body: web::Json<UploadOnboardingInterestsHttpRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    // Extract user ID from JWT token
    let user_id = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(AuthenticatedUser(id)) => id.to_string(),
        None => {
            warn!("POST /api/v2/photo-analysis/onboarding: Missing user context");
            return Ok(HttpResponse::Unauthorized().json(serde_json::json!({
                "error": "Missing user context",
                "code": 401
            })));
        }
    };

    info!(
        user_id = %user_id,
        channels_count = body.selected_channels.len(),
        "POST /api/v2/photo-analysis/onboarding"
    );

    // Build gRPC request
    let grpc_request = UploadOnboardingInterestsRequest {
        user_id: user_id.clone(),
        selected_channels: body.selected_channels.clone(),
        selected_at: body
            .selected_at
            .clone()
            .unwrap_or_else(|| chrono::Utc::now().to_rfc3339()),
    };

    // Call ranking-service via gRPC with circuit breaker
    let mut client = clients.ranking_client();
    match clients
        .call_ranking(|| async { client.upload_onboarding_interests(grpc_request.clone()).await })
        .await
    {
        Ok(response) => {
            info!(
                user_id = %user_id,
                interests_created = response.interests_created,
                "Onboarding interests uploaded successfully"
            );

            Ok(HttpResponse::Ok().json(UploadOnboardingInterestsHttpResponse {
                success: response.success,
                interests_created: response.interests_created,
                error_message: if response.error_message.is_empty() {
                    None
                } else {
                    Some(response.error_message)
                },
            }))
        }
        Err(e) => {
            error!(
                user_id = %user_id,
                error = %e,
                "Failed to upload onboarding interests"
            );

            Ok(HttpResponse::BadGateway().json(serde_json::json!({
                "error": "Failed to process onboarding interests",
                "message": format!("{}", e),
                "code": 502
            })))
        }
    }
}
