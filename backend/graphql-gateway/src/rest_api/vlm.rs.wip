//! VLM (Vision Language Model) API endpoints
//!
//! POST /api/v2/vlm/analyze - Analyze image and get tags + channel suggestions
//! GET /api/v2/posts/{id}/tags - Get tags for a post
//! PUT /api/v2/posts/{id}/tags - Update tags for a post
//!
//! Uses Google Cloud Vision API for image analysis and generates
//! tags for automatic channel classification.

use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use std::collections::HashMap;
use std::env;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;

// ============================================
// Configuration
// ============================================

const VISION_API_URL: &str = "https://vision.googleapis.com/v1/images:annotate";
const CACHE_TTL_SECONDS: u64 = 3600; // 1 hour
const CACHE_MAX_ENTRIES: usize = 500;

/// Tags that are too generic to be useful
const TAG_BLOCKLIST: &[&str] = &[
    "image", "photo", "picture", "screenshot", "snapshot", "photography",
    "person", "people", "human", "man", "woman", "adult", "child", "face",
    "day", "night", "indoor", "outdoor", "daytime",
    "close-up", "closeup", "background", "foreground",
];

// ============================================
// Cache
// ============================================

static VLM_CACHE: once_cell::sync::Lazy<Arc<RwLock<VlmCache>>> =
    once_cell::sync::Lazy::new(|| Arc::new(RwLock::new(VlmCache::new())));

struct CacheEntry {
    response: VlmAnalyzeResponse,
    created_at: Instant,
}

struct VlmCache {
    entries: HashMap<String, CacheEntry>,
}

impl VlmCache {
    fn new() -> Self {
        Self {
            entries: HashMap::new(),
        }
    }

    fn get(&self, key: &str) -> Option<&VlmAnalyzeResponse> {
        self.entries.get(key).and_then(|entry| {
            if entry.created_at.elapsed() < Duration::from_secs(CACHE_TTL_SECONDS) {
                Some(&entry.response)
            } else {
                None
            }
        })
    }

    fn insert(&mut self, key: String, response: VlmAnalyzeResponse) {
        // Evict old entries if needed
        if self.entries.len() >= CACHE_MAX_ENTRIES {
            self.evict_expired();
            if self.entries.len() >= CACHE_MAX_ENTRIES {
                if let Some(oldest_key) = self
                    .entries
                    .iter()
                    .min_by_key(|(_, v)| v.created_at)
                    .map(|(k, _)| k.clone())
                {
                    self.entries.remove(&oldest_key);
                }
            }
        }

        self.entries.insert(
            key,
            CacheEntry {
                response,
                created_at: Instant::now(),
            },
        );
    }

    fn evict_expired(&mut self) {
        let now = Instant::now();
        self.entries.retain(|_, entry| {
            now.duration_since(entry.created_at) < Duration::from_secs(CACHE_TTL_SECONDS)
        });
    }
}

// ============================================
// Request/Response Models
// ============================================

#[derive(Debug, Deserialize)]
pub struct VlmAnalyzeRequest {
    /// Image URL (GCS or CDN URL)
    pub image_url: String,
    /// Include channel suggestions
    #[serde(default = "default_true")]
    pub include_channels: bool,
    /// Maximum tags to return
    #[serde(default = "default_max_tags")]
    pub max_tags: usize,
}

fn default_true() -> bool {
    true
}

fn default_max_tags() -> usize {
    15
}

#[derive(Debug, Serialize, Clone)]
pub struct VlmAnalyzeResponse {
    pub tags: Vec<TagSuggestion>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub channels: Option<Vec<ChannelSuggestion>>,
    pub processing_time_ms: u64,
}

#[derive(Debug, Serialize, Clone)]
pub struct TagSuggestion {
    pub tag: String,
    pub confidence: f32,
    pub source: String, // "vlm", "alice", "user"
}

#[derive(Debug, Serialize, Clone)]
pub struct ChannelSuggestion {
    pub id: String,
    pub name: String,
    pub slug: String,
    pub confidence: f32,
    pub matched_keywords: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct UpdatePostTagsRequest {
    /// Tags to set
    pub tags: Vec<String>,
    /// Selected channel IDs
    #[serde(default)]
    pub channel_ids: Vec<String>,
}

#[derive(Debug, Serialize)]
pub struct PostTagsResponse {
    pub post_id: String,
    pub tags: Vec<TagSuggestion>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub channel_ids: Option<Vec<String>>,
}

// ============================================
// Google Vision API Types
// ============================================

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct VisionRequest {
    requests: Vec<AnnotateImageRequest>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AnnotateImageRequest {
    image: Image,
    features: Vec<Feature>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Image {
    source: ImageSource,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ImageSource {
    image_uri: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Feature {
    #[serde(rename = "type")]
    feature_type: String,
    max_results: i32,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct VisionResponse {
    responses: Vec<AnnotateImageResponse>,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct AnnotateImageResponse {
    label_annotations: Option<Vec<EntityAnnotation>>,
    localized_object_annotations: Option<Vec<LocalizedObjectAnnotation>>,
    web_detection: Option<WebDetection>,
    error: Option<VisionError>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct EntityAnnotation {
    description: String,
    score: f32,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LocalizedObjectAnnotation {
    name: String,
    score: f32,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase", default)]
struct WebDetection {
    web_entities: Option<Vec<WebEntity>>,
    best_guess_labels: Option<Vec<BestGuessLabel>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WebEntity {
    description: Option<String>,
    score: f32,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BestGuessLabel {
    label: String,
}

#[derive(Debug, Deserialize)]
struct VisionError {
    code: i32,
    message: String,
}

// ============================================
// Channel Data (loaded from database)
// ============================================

#[derive(Debug, Clone)]
struct ChannelWithKeywords {
    id: Uuid,
    name: String,
    slug: String,
    vlm_keywords: Vec<KeywordWeight>,
}

#[derive(Debug, Clone, Deserialize)]
struct KeywordWeight {
    keyword: String,
    weight: f32,
}

// ============================================
// Helpers
// ============================================

/// Generate cache key from image URL
fn generate_cache_key(image_url: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(image_url.as_bytes());
    format!("vlm:{:x}", hasher.finalize())
}

/// Get Google Vision API key from environment
fn get_vision_api_key() -> Option<String> {
    env::var("GOOGLE_VISION_API_KEY").ok().filter(|k| !k.is_empty())
}

/// Normalize a tag string
fn normalize_tag(tag: &str) -> String {
    tag.to_lowercase()
        .trim()
        .replace(['_', '-'], " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

/// Check if a tag is valid
fn is_valid_tag(tag: &str) -> bool {
    if tag.len() < 2 || tag.len() > 50 {
        return false;
    }
    !TAG_BLOCKLIST.contains(&tag)
}

/// Load channels with VLM keywords from database
async fn load_channels_with_keywords(pool: &PgPool) -> Vec<ChannelWithKeywords> {
    let rows = sqlx::query!(
        r#"
        SELECT id, name, slug, vlm_keywords
        FROM channels
        WHERE is_enabled = true AND vlm_keywords IS NOT NULL AND vlm_keywords != '[]'::jsonb
        ORDER BY display_order
        "#
    )
    .fetch_all(pool)
    .await;

    match rows {
        Ok(rows) => rows
            .into_iter()
            .filter_map(|row| {
                let vlm_keywords: Vec<KeywordWeight> = row
                    .vlm_keywords
                    .and_then(|v| serde_json::from_value(v).ok())
                    .unwrap_or_default();

                if vlm_keywords.is_empty() {
                    return None;
                }

                Some(ChannelWithKeywords {
                    id: row.id,
                    name: row.name,
                    slug: row.slug.unwrap_or_default(),
                    vlm_keywords,
                })
            })
            .collect(),
        Err(e) => {
            error!("Failed to load channels: {}", e);
            vec![]
        }
    }
}

/// Match tags to channels
fn match_channels(
    tags: &[TagSuggestion],
    channels: &[ChannelWithKeywords],
    max_channels: usize,
    min_confidence: f32,
) -> Vec<ChannelSuggestion> {
    let mut matches: Vec<ChannelSuggestion> = Vec::new();

    for channel in channels {
        let mut total_score = 0.0f32;
        let mut matched_keywords: Vec<String> = Vec::new();

        for tag in tags {
            let tag_lower = tag.tag.to_lowercase();

            for kw in &channel.vlm_keywords {
                let kw_lower = kw.keyword.to_lowercase();

                let match_score = if tag_lower == kw_lower {
                    1.0
                } else if tag_lower.contains(&kw_lower) || kw_lower.contains(&tag_lower) {
                    0.6
                } else {
                    0.0
                };

                if match_score > 0.0 {
                    let weighted = match_score * kw.weight * tag.confidence;
                    total_score += weighted;
                    if !matched_keywords.contains(&kw.keyword) {
                        matched_keywords.push(kw.keyword.clone());
                    }
                }
            }
        }

        if !matched_keywords.is_empty() {
            let keyword_count = channel.vlm_keywords.len() as f32;
            let base_score = (total_score / keyword_count).min(1.0);
            let match_boost = (matched_keywords.len() as f32 * 0.1).min(0.3);
            let confidence = (base_score + match_boost).min(1.0);

            if confidence >= min_confidence {
                matches.push(ChannelSuggestion {
                    id: channel.id.to_string(),
                    name: channel.name.clone(),
                    slug: channel.slug.clone(),
                    confidence,
                    matched_keywords,
                });
            }
        }
    }

    matches.sort_by(|a, b| {
        b.confidence
            .partial_cmp(&a.confidence)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    matches.truncate(max_channels);

    matches
}

// ============================================
// API Handlers
// ============================================

/// POST /api/v2/vlm/analyze
/// Analyze image and return tags + channel suggestions
pub async fn analyze_image(
    req: HttpRequest,
    body: web::Json<VlmAnalyzeRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let start = Instant::now();
    info!(image_url = %body.image_url, "POST /api/v2/vlm/analyze");

    // Check authentication
    let _user = match req.extensions().get::<AuthenticatedUser>() {
        Some(user) => user.clone(),
        None => {
            return Ok(HttpResponse::Unauthorized().json(serde_json::json!({
                "error": "Authentication required"
            })));
        }
    };

    // Check cache
    let cache_key = generate_cache_key(&body.image_url);
    {
        let cache = VLM_CACHE.read().await;
        if let Some(cached) = cache.get(&cache_key) {
            info!(
                elapsed_ms = start.elapsed().as_millis(),
                "VLM cache hit"
            );
            return Ok(HttpResponse::Ok().json(cached.clone()));
        }
    }

    // Get API key
    let api_key = match get_vision_api_key() {
        Some(key) => key,
        None => {
            warn!("GOOGLE_VISION_API_KEY not configured");
            return Ok(HttpResponse::ServiceUnavailable().json(serde_json::json!({
                "error": "VLM service not configured",
                "message": "Google Vision API key not set"
            })));
        }
    };

    // Call Google Vision API
    let vision_request = VisionRequest {
        requests: vec![AnnotateImageRequest {
            image: Image {
                source: ImageSource {
                    image_uri: body.image_url.clone(),
                },
            },
            features: vec![
                Feature {
                    feature_type: "LABEL_DETECTION".to_string(),
                    max_results: 20,
                },
                Feature {
                    feature_type: "OBJECT_LOCALIZATION".to_string(),
                    max_results: 10,
                },
                Feature {
                    feature_type: "WEB_DETECTION".to_string(),
                    max_results: 10,
                },
            ],
        }],
    };

    let client = Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .unwrap_or_else(|_| Client::new());

    let url = format!("{}?key={}", VISION_API_URL, api_key);

    let response = match client.post(&url).json(&vision_request).send().await {
        Ok(resp) => resp,
        Err(e) => {
            error!("Failed to call Vision API: {}", e);
            return Ok(HttpResponse::BadGateway().json(serde_json::json!({
                "error": "VLM service unavailable",
                "message": e.to_string()
            })));
        }
    };

    let status = response.status();
    if !status.is_success() {
        let error_text = response.text().await.unwrap_or_default();
        error!(status = %status, error = %error_text, "Vision API error");
        return Ok(HttpResponse::BadGateway().json(serde_json::json!({
            "error": "Vision API error",
            "status": status.as_u16(),
            "message": error_text
        })));
    }

    let vision_response: VisionResponse = match response.json().await {
        Ok(resp) => resp,
        Err(e) => {
            error!("Failed to parse Vision API response: {}", e);
            return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Failed to parse VLM response"
            })));
        }
    };

    // Process response
    let annotate = vision_response.responses.into_iter().next().unwrap_or_default();

    if let Some(error) = annotate.error {
        error!(code = error.code, message = %error.message, "Vision API returned error");
        return Ok(HttpResponse::BadGateway().json(serde_json::json!({
            "error": "Vision API error",
            "code": error.code,
            "message": error.message
        })));
    }

    // Generate tags
    let mut tag_map: HashMap<String, TagSuggestion> = HashMap::new();
    let min_confidence = 0.3f32;

    // Process labels
    for label in annotate.label_annotations.unwrap_or_default() {
        if label.score < min_confidence {
            continue;
        }
        let normalized = normalize_tag(&label.description);
        if is_valid_tag(&normalized) {
            let entry = tag_map.entry(normalized.clone()).or_insert(TagSuggestion {
                tag: normalized,
                confidence: 0.0,
                source: "vlm".to_string(),
            });
            entry.confidence = entry.confidence.max(label.score);
        }
    }

    // Process objects
    for obj in annotate.localized_object_annotations.unwrap_or_default() {
        if obj.score < min_confidence {
            continue;
        }
        let normalized = normalize_tag(&obj.name);
        if is_valid_tag(&normalized) && !tag_map.contains_key(&normalized) {
            tag_map.insert(
                normalized.clone(),
                TagSuggestion {
                    tag: normalized,
                    confidence: obj.score * 0.9,
                    source: "vlm".to_string(),
                },
            );
        }
    }

    // Process web entities
    let web = annotate.web_detection.unwrap_or_default();
    for entity in web.web_entities.unwrap_or_default() {
        if let Some(desc) = entity.description {
            if entity.score < min_confidence {
                continue;
            }
            let normalized = normalize_tag(&desc);
            if is_valid_tag(&normalized) && !tag_map.contains_key(&normalized) {
                tag_map.insert(
                    normalized.clone(),
                    TagSuggestion {
                        tag: normalized,
                        confidence: entity.score * 0.8,
                        source: "vlm".to_string(),
                    },
                );
            }
        }
    }

    // Process best guess labels
    for label in web.best_guess_labels.unwrap_or_default() {
        let normalized = normalize_tag(&label.label);
        if is_valid_tag(&normalized) && !tag_map.contains_key(&normalized) {
            tag_map.insert(
                normalized.clone(),
                TagSuggestion {
                    tag: normalized,
                    confidence: 0.7,
                    source: "vlm".to_string(),
                },
            );
        }
    }

    // Sort and limit tags
    let mut tags: Vec<TagSuggestion> = tag_map.into_values().collect();
    tags.sort_by(|a, b| {
        b.confidence
            .partial_cmp(&a.confidence)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    tags.truncate(body.max_tags);

    debug!(tag_count = tags.len(), "Generated tags");

    // Match channels if requested
    let channels = if body.include_channels {
        let pool = clients.db_pool();
        let channel_data = load_channels_with_keywords(pool).await;
        let matched = match_channels(&tags, &channel_data, 3, 0.25);
        debug!(channel_count = matched.len(), "Matched channels");
        Some(matched)
    } else {
        None
    };

    let processing_time_ms = start.elapsed().as_millis() as u64;

    let response = VlmAnalyzeResponse {
        tags,
        channels,
        processing_time_ms,
    };

    // Cache response
    {
        let mut cache = VLM_CACHE.write().await;
        cache.insert(cache_key, response.clone());
    }

    info!(
        elapsed_ms = processing_time_ms,
        tag_count = response.tags.len(),
        "VLM analysis complete"
    );

    Ok(HttpResponse::Ok().json(response))
}

/// GET /api/v2/posts/{id}/tags
/// Get tags for a specific post
pub async fn get_post_tags(
    path: web::Path<Uuid>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let post_id = path.into_inner();
    info!(post_id = %post_id, "GET /api/v2/posts/{id}/tags");

    let pool = clients.db_pool();

    let tags = sqlx::query!(
        r#"
        SELECT tag, confidence, source
        FROM post_tags
        WHERE post_id = $1
        ORDER BY confidence DESC
        "#,
        post_id
    )
    .fetch_all(pool)
    .await;

    match tags {
        Ok(rows) => {
            let tags: Vec<TagSuggestion> = rows
                .into_iter()
                .map(|r| TagSuggestion {
                    tag: r.tag,
                    confidence: r.confidence.unwrap_or(1.0) as f32,
                    source: r.source.unwrap_or_else(|| "vlm".to_string()),
                })
                .collect();

            Ok(HttpResponse::Ok().json(PostTagsResponse {
                post_id: post_id.to_string(),
                tags,
                channel_ids: None,
            }))
        }
        Err(e) => {
            error!("Failed to get post tags: {}", e);
            Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Failed to get post tags"
            })))
        }
    }
}

/// PUT /api/v2/posts/{id}/tags
/// Update tags for a post (user-provided tags)
pub async fn update_post_tags(
    req: HttpRequest,
    path: web::Path<Uuid>,
    body: web::Json<UpdatePostTagsRequest>,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let post_id = path.into_inner();
    info!(post_id = %post_id, "PUT /api/v2/posts/{id}/tags");

    // Check authentication
    let user = match req.extensions().get::<AuthenticatedUser>() {
        Some(user) => user.clone(),
        None => {
            return Ok(HttpResponse::Unauthorized().json(serde_json::json!({
                "error": "Authentication required"
            })));
        }
    };

    let pool = clients.db_pool();

    // Verify post ownership
    let post = sqlx::query!(
        r#"
        SELECT user_id FROM posts WHERE id = $1 AND soft_delete IS NULL
        "#,
        post_id
    )
    .fetch_optional(pool)
    .await;

    match post {
        Ok(Some(p)) if p.user_id == user.0 => {
            // User owns this post
        }
        Ok(Some(_)) => {
            return Ok(HttpResponse::Forbidden().json(serde_json::json!({
                "error": "Not authorized to modify this post"
            })));
        }
        Ok(None) => {
            return Ok(HttpResponse::NotFound().json(serde_json::json!({
                "error": "Post not found"
            })));
        }
        Err(e) => {
            error!("Failed to get post: {}", e);
            return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Database error"
            })));
        }
    }

    // Delete existing user tags and insert new ones
    let mut tx = match pool.begin().await {
        Ok(tx) => tx,
        Err(e) => {
            error!("Failed to start transaction: {}", e);
            return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Database error"
            })));
        }
    };

    // Delete user-provided tags (keep VLM tags)
    if let Err(e) = sqlx::query!(
        r#"DELETE FROM post_tags WHERE post_id = $1 AND source = 'user'"#,
        post_id
    )
    .execute(&mut *tx)
    .await
    {
        error!("Failed to delete old tags: {}", e);
        return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": "Failed to update tags"
        })));
    }

    // Insert new tags
    for tag in &body.tags {
        let normalized = normalize_tag(tag);
        if is_valid_tag(&normalized) {
            let _ = sqlx::query!(
                r#"
                INSERT INTO post_tags (post_id, tag, confidence, source)
                VALUES ($1, $2, 1.0, 'user')
                ON CONFLICT (post_id, tag) DO UPDATE SET source = 'user', confidence = 1.0
                "#,
                post_id,
                normalized
            )
            .execute(&mut *tx)
            .await;
        }
    }

    // Update post channels if provided
    if !body.channel_ids.is_empty() {
        // Delete existing channel associations
        let _ = sqlx::query!(
            r#"DELETE FROM post_channels WHERE post_id = $1"#,
            post_id
        )
        .execute(&mut *tx)
        .await;

        // Insert new channel associations
        for channel_id in &body.channel_ids {
            if let Ok(cid) = Uuid::parse_str(channel_id) {
                let _ = sqlx::query!(
                    r#"
                    INSERT INTO post_channels (post_id, channel_id, confidence, tagged_by)
                    VALUES ($1, $2, 1.0, 'author')
                    ON CONFLICT DO NOTHING
                    "#,
                    post_id,
                    cid
                )
                .execute(&mut *tx)
                .await;
            }
        }
    }

    if let Err(e) = tx.commit().await {
        error!("Failed to commit transaction: {}", e);
        return Ok(HttpResponse::InternalServerError().json(serde_json::json!({
            "error": "Failed to save changes"
        })));
    }

    // Return updated tags
    let updated_tags: Vec<TagSuggestion> = body
        .tags
        .iter()
        .map(|t| TagSuggestion {
            tag: normalize_tag(t),
            confidence: 1.0,
            source: "user".to_string(),
        })
        .collect();

    Ok(HttpResponse::Ok().json(PostTagsResponse {
        post_id: post_id.to_string(),
        tags: updated_tags,
        channel_ids: Some(body.channel_ids.clone()),
    }))
}
