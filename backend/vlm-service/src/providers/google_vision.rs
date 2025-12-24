//! Google Cloud Vision API integration for image labeling
use anyhow::{Context, Result};
use gcp_auth::TokenProvider;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
use tracing::{debug, error, info};

const VISION_API_URL: &str = "https://vision.googleapis.com/v1/images:annotate";
const VISION_API_SCOPES: &[&str] = &["https://www.googleapis.com/auth/cloud-vision"];

/// Authentication mode for Vision API
#[derive(Debug, Clone)]
pub enum AuthMode {
    /// Use API key authentication
    ApiKey(String),
    /// Use Application Default Credentials (Workload Identity)
    Adc,
}

/// Google Cloud Vision API client
pub struct GoogleVisionClient {
    client: Client,
    auth_mode: AuthMode,
    /// Cached token provider for ADC
    token_provider: Arc<RwLock<Option<Arc<dyn TokenProvider>>>>,
}

// ============================================
// Request types
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
    /// GCS URL (gs://bucket/path) or HTTPS URL
    image_uri: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Feature {
    #[serde(rename = "type")]
    feature_type: String,
    max_results: i32,
}

// ============================================
// Response types
// ============================================

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

#[derive(Debug, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct EntityAnnotation {
    pub description: String,
    pub score: f32,
    /// Knowledge Graph MID (Machine ID)
    pub mid: Option<String>,
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
// Result types
// ============================================

/// Result from image analysis
#[derive(Debug, Clone)]
pub struct ImageAnalysisResult {
    /// Labels detected in the image
    pub labels: Vec<Label>,
    /// Objects detected with bounding boxes
    pub objects: Vec<Label>,
    /// Web entities (similar content on the web)
    pub web_entities: Vec<Label>,
    /// Best guess labels from web detection
    pub best_guess_labels: Vec<String>,
}

/// A single label with confidence score
#[derive(Debug, Clone)]
pub struct Label {
    pub name: String,
    pub confidence: f32,
    /// Knowledge Graph MID (optional)
    pub mid: Option<String>,
}

impl GoogleVisionClient {
    /// Create a new Google Vision API client with API key
    pub fn new(api_key: String) -> Self {
        Self::with_auth_mode(AuthMode::ApiKey(api_key))
    }

    /// Create a new Google Vision API client with specified auth mode
    pub fn with_auth_mode(auth_mode: AuthMode) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("Failed to create HTTP client");

        Self {
            client,
            auth_mode,
            token_provider: Arc::new(RwLock::new(None)),
        }
    }

    /// Create a client using Application Default Credentials
    pub fn with_adc() -> Self {
        Self::with_auth_mode(AuthMode::Adc)
    }

    /// Get an access token for ADC authentication
    async fn get_access_token(&self) -> Result<String> {
        let mut provider_guard = self.token_provider.write().await;

        // Initialize token provider if not already done
        if provider_guard.is_none() {
            let provider = gcp_auth::provider().await
                .context("Failed to initialize GCP authentication")?;
            *provider_guard = Some(provider);
        }

        let provider = provider_guard.as_ref().unwrap();
        let token = provider
            .token(VISION_API_SCOPES)
            .await
            .context("Failed to get access token")?;

        Ok(token.as_str().to_string())
    }

    /// Analyze an image from a URL (GCS or HTTPS)
    ///
    /// # Arguments
    /// * `image_url` - URL of the image to analyze (gs:// or https://)
    ///
    /// # Returns
    /// * `ImageAnalysisResult` containing labels, objects, and web entities
    pub async fn analyze_image(&self, image_url: &str) -> Result<ImageAnalysisResult> {
        info!(image_url = %image_url, "Analyzing image with Google Vision");

        let request = VisionRequest {
            requests: vec![AnnotateImageRequest {
                image: Image {
                    source: ImageSource {
                        image_uri: image_url.to_string(),
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

        let start = std::time::Instant::now();

        // Build request based on auth mode
        let response = match &self.auth_mode {
            AuthMode::ApiKey(api_key) => {
                let url = format!("{}?key={}", VISION_API_URL, api_key);
                self.client
                    .post(&url)
                    .json(&request)
                    .send()
                    .await
                    .context("Failed to call Vision API")?
            }
            AuthMode::Adc => {
                let token = self.get_access_token().await?;
                self.client
                    .post(VISION_API_URL)
                    .bearer_auth(&token)
                    .json(&request)
                    .send()
                    .await
                    .context("Failed to call Vision API")?
            }
        };

        let status = response.status();
        if !status.is_success() {
            let error_text = response.text().await.unwrap_or_default();
            error!(status = %status, error = %error_text, "Vision API request failed");
            anyhow::bail!("Vision API error ({}): {}", status, error_text);
        }

        let vision_response: VisionResponse = response
            .json()
            .await
            .context("Failed to parse Vision API response")?;

        let elapsed = start.elapsed();
        debug!(elapsed_ms = elapsed.as_millis(), "Vision API response received");

        // Process first response
        let annotate_response = vision_response
            .responses
            .into_iter()
            .next()
            .unwrap_or_default();

        if let Some(error) = annotate_response.error {
            error!(
                code = error.code,
                message = %error.message,
                "Vision API returned error"
            );
            anyhow::bail!("Vision API error {}: {}", error.code, error.message);
        }

        // Convert to our result format
        let labels: Vec<Label> = annotate_response
            .label_annotations
            .unwrap_or_default()
            .into_iter()
            .map(|a| Label {
                name: a.description,
                confidence: a.score,
                mid: a.mid,
            })
            .collect();

        let objects: Vec<Label> = annotate_response
            .localized_object_annotations
            .unwrap_or_default()
            .into_iter()
            .map(|a| Label {
                name: a.name,
                confidence: a.score,
                mid: None,
            })
            .collect();

        let web_detection = annotate_response.web_detection.unwrap_or_default();

        let web_entities: Vec<Label> = web_detection
            .web_entities
            .unwrap_or_default()
            .into_iter()
            .filter_map(|e| {
                e.description.map(|d| Label {
                    name: d,
                    confidence: e.score,
                    mid: None,
                })
            })
            .collect();

        let best_guess_labels: Vec<String> = web_detection
            .best_guess_labels
            .unwrap_or_default()
            .into_iter()
            .map(|l| l.label)
            .collect();

        let label_count = labels.len();
        let object_count = objects.len();

        info!(
            labels = label_count,
            objects = object_count,
            elapsed_ms = elapsed.as_millis(),
            "Image analysis complete"
        );

        Ok(ImageAnalysisResult {
            labels,
            objects,
            web_entities,
            best_guess_labels,
        })
    }

    /// Check if authentication is configured
    pub fn is_configured(&self) -> bool {
        match &self.auth_mode {
            AuthMode::ApiKey(key) => !key.is_empty(),
            AuthMode::Adc => true, // ADC is always available in GCP environment
        }
    }

    /// Get the current auth mode
    pub fn auth_mode(&self) -> &AuthMode {
        &self.auth_mode
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_client_not_configured() {
        let client = GoogleVisionClient::new(String::new());
        assert!(!client.is_configured());
    }

    #[test]
    fn test_client_configured() {
        let client = GoogleVisionClient::new("test-api-key".to_string());
        assert!(client.is_configured());
    }
}
