/// GCP Transcoder API client for video transcoding
///
/// This module integrates with Google Cloud Transcoder API to perform
/// actual video transcoding instead of mock processing.
///
/// ## Environment Variables
/// - `GCP_PROJECT_ID`: GCP project ID
/// - `GCP_TRANSCODER_LOCATION`: Transcoder location (default: us-central1)
/// - `GCS_BUCKET`: GCS bucket for input/output videos
/// - `GCS_SERVICE_ACCOUNT_JSON_PATH`: Path to service account JSON
/// - `MEDIA_TRANSCODE_ENABLE_MOCK`: Set to "false" to enable real transcoding
use crate::error::{AppError, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info, warn};
use uuid::Uuid;

/// GCP Transcoder client configuration
#[derive(Clone, Debug)]
pub struct TranscoderConfig {
    pub project_id: String,
    pub location: String,
    pub gcs_bucket: String,
    pub cdn_base_url: String,
}

impl TranscoderConfig {
    /// Load configuration from environment variables
    pub fn from_env() -> Option<Self> {
        let project_id = std::env::var("GCP_PROJECT_ID").ok()?;
        let gcs_bucket = std::env::var("GCS_BUCKET").ok()?;

        Some(Self {
            project_id,
            location: std::env::var("GCP_TRANSCODER_LOCATION")
                .unwrap_or_else(|_| "us-central1".to_string()),
            gcs_bucket,
            cdn_base_url: std::env::var("MEDIA_CDN_BASE_URL")
                .unwrap_or_else(|_| "https://cdn.nova.local".to_string()),
        })
    }
}

/// Quality profile for transcoding
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TranscodeProfile {
    pub name: String,
    pub width: i32,
    pub height: i32,
    pub bitrate_kbps: i32,
    pub frame_rate: f32,
    pub codec: String,
}

impl TranscodeProfile {
    /// Default quality profiles for Nova reels
    pub fn default_profiles() -> Vec<Self> {
        vec![
            Self {
                name: "1080p".to_string(),
                width: 1920,
                height: 1080,
                bitrate_kbps: 8000,
                frame_rate: 30.0,
                codec: "h264".to_string(),
            },
            Self {
                name: "720p".to_string(),
                width: 1280,
                height: 720,
                bitrate_kbps: 5000,
                frame_rate: 30.0,
                codec: "h264".to_string(),
            },
            Self {
                name: "480p".to_string(),
                width: 854,
                height: 480,
                bitrate_kbps: 2500,
                frame_rate: 30.0,
                codec: "h264".to_string(),
            },
            Self {
                name: "360p".to_string(),
                width: 640,
                height: 360,
                bitrate_kbps: 1000,
                frame_rate: 30.0,
                codec: "h264".to_string(),
            },
        ]
    }
}

/// Transcoding job status
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub enum TranscodeJobStatus {
    Pending,
    Processing,
    Succeeded,
    Failed,
}

/// Transcoding job result
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TranscodeJobResult {
    pub job_id: String,
    pub status: TranscodeJobStatus,
    pub progress: i32,
    pub output_uris: Vec<TranscodeOutput>,
    pub error_message: Option<String>,
}

/// Transcoded output information
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TranscodeOutput {
    pub quality: String,
    pub gcs_uri: String,
    pub cdn_url: String,
    pub file_size_bytes: Option<i64>,
}

/// GCP Transcoder API client
pub struct GcpTranscoderClient {
    config: TranscoderConfig,
    http_client: reqwest::Client,
    access_token: Option<String>,
}

impl GcpTranscoderClient {
    /// Create a new GCP Transcoder client
    pub async fn new(config: TranscoderConfig) -> Result<Self> {
        let http_client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(60))
            .build()
            .map_err(|e| AppError::Internal(format!("HTTP client error: {e}")))?;

        let mut client = Self {
            config,
            http_client,
            access_token: None,
        };

        // Get initial access token
        client.refresh_access_token().await?;

        Ok(client)
    }

    /// Refresh the OAuth2 access token using application default credentials
    async fn refresh_access_token(&mut self) -> Result<()> {
        // Try to get token from metadata server (GKE/Cloud Run) or ADC
        let token = self
            .get_access_token_from_metadata()
            .await
            .or_else(|_| self.get_access_token_from_adc())
            .map_err(|e| AppError::Internal(format!("Failed to get GCP access token: {e}")))?;

        self.access_token = Some(token);
        Ok(())
    }

    /// Get access token from GCE metadata server
    async fn get_access_token_from_metadata(&self) -> std::result::Result<String, String> {
        let url = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token";

        let response = self
            .http_client
            .get(url)
            .header("Metadata-Flavor", "Google")
            .send()
            .await
            .map_err(|e| format!("Metadata request failed: {e}"))?;

        if !response.status().is_success() {
            return Err("Metadata server not available".to_string());
        }

        #[derive(Deserialize)]
        struct TokenResponse {
            access_token: String,
        }

        let token_response: TokenResponse = response
            .json()
            .await
            .map_err(|e| format!("Failed to parse token response: {e}"))?;

        Ok(token_response.access_token)
    }

    /// Get access token from Application Default Credentials
    fn get_access_token_from_adc(&self) -> std::result::Result<String, String> {
        // This would typically use google-cloud-auth crate
        // For now, return placeholder - in production this should use proper ADC
        Err(
            "ADC not implemented - use metadata server or set GOOGLE_APPLICATION_CREDENTIALS"
                .to_string(),
        )
    }

    /// Create a transcoding job for a reel
    ///
    /// ## Arguments
    /// * `reel_id` - UUID of the reel to transcode
    /// * `input_gcs_uri` - GCS URI of the source video (gs://bucket/path/video.mp4)
    /// * `profiles` - Quality profiles to transcode to
    pub async fn create_transcode_job(
        &mut self,
        reel_id: Uuid,
        input_gcs_uri: &str,
        profiles: &[TranscodeProfile],
    ) -> Result<String> {
        let access_token = self
            .access_token
            .as_ref()
            .ok_or_else(|| AppError::Internal("No access token available".to_string()))?;

        let job_id = format!("reel-{}-{}", reel_id, chrono::Utc::now().timestamp_millis());
        let output_uri = format!("gs://{}/reels/{}/", self.config.gcs_bucket, reel_id);

        // Build elementary streams and mux streams for each profile
        let mut elementary_streams = Vec::new();
        let mut mux_streams = Vec::new();

        for (i, profile) in profiles.iter().enumerate() {
            // Video stream
            elementary_streams.push(serde_json::json!({
                "key": format!("video-{}", profile.name),
                "videoStream": {
                    "h264": {
                        "widthPixels": profile.width,
                        "heightPixels": profile.height,
                        "bitrateBps": profile.bitrate_kbps * 1000,
                        "frameRate": profile.frame_rate,
                        "profile": "high",
                        "preset": "medium"
                    }
                }
            }));

            // Audio stream (shared)
            if i == 0 {
                elementary_streams.push(serde_json::json!({
                    "key": "audio-aac",
                    "audioStream": {
                        "codec": "aac",
                        "bitrateBps": 128000,
                        "channelCount": 2,
                        "sampleRateHertz": 44100
                    }
                }));
            }

            // Mux stream for this quality
            mux_streams.push(serde_json::json!({
                "key": format!("mux-{}", profile.name),
                "fileName": format!("{}.mp4", profile.name),
                "container": "mp4",
                "elementaryStreams": [
                    format!("video-{}", profile.name),
                    "audio-aac"
                ]
            }));
        }

        let job_config = serde_json::json!({
            "inputUri": input_gcs_uri,
            "outputUri": output_uri,
            "config": {
                "elementaryStreams": elementary_streams,
                "muxStreams": mux_streams
            }
        });

        let url = format!(
            "https://transcoder.googleapis.com/v1/projects/{}/locations/{}/jobs",
            self.config.project_id, self.config.location
        );

        info!(
            "Creating GCP Transcoder job for reel {}: input={}, output={}",
            reel_id, input_gcs_uri, output_uri
        );

        let response = self
            .http_client
            .post(&url)
            .header("Authorization", format!("Bearer {}", access_token))
            .header("Content-Type", "application/json")
            .json(&job_config)
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("Transcoder API request failed: {e}")))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            error!("GCP Transcoder API error: {}", error_text);
            return Err(AppError::Internal(format!(
                "Transcoder job creation failed: {}",
                error_text
            )));
        }

        #[derive(Deserialize)]
        struct JobResponse {
            name: String,
        }

        let job_response: JobResponse = response
            .json()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to parse job response: {e}")))?;

        // Extract job ID from resource name (projects/.../jobs/JOB_ID)
        let gcp_job_id = job_response
            .name
            .split('/')
            .last()
            .unwrap_or(&job_id)
            .to_string();

        info!(
            "GCP Transcoder job created: reel={}, job_id={}",
            reel_id, gcp_job_id
        );

        Ok(gcp_job_id)
    }

    /// Get the status of a transcoding job
    pub async fn get_job_status(&mut self, job_id: &str) -> Result<TranscodeJobResult> {
        let access_token = self
            .access_token
            .as_ref()
            .ok_or_else(|| AppError::Internal("No access token available".to_string()))?;

        let url = format!(
            "https://transcoder.googleapis.com/v1/projects/{}/locations/{}/jobs/{}",
            self.config.project_id, self.config.location, job_id
        );

        let response = self
            .http_client
            .get(&url)
            .header("Authorization", format!("Bearer {}", access_token))
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("Transcoder API request failed: {e}")))?;

        if !response.status().is_success() {
            let error_text = response.text().await.unwrap_or_default();
            return Err(AppError::Internal(format!(
                "Failed to get job status: {}",
                error_text
            )));
        }

        #[derive(Deserialize)]
        struct GcpJobResponse {
            state: String,
            #[serde(default)]
            progress: Option<GcpProgress>,
            #[serde(default)]
            error: Option<GcpError>,
            config: Option<GcpJobConfig>,
        }

        #[derive(Deserialize, Default)]
        struct GcpProgress {
            #[serde(default)]
            progress: f64,
        }

        #[derive(Deserialize)]
        struct GcpError {
            message: String,
        }

        #[derive(Deserialize)]
        struct GcpJobConfig {
            #[serde(default)]
            output: Option<GcpOutput>,
        }

        #[derive(Deserialize)]
        struct GcpOutput {
            uri: String,
        }

        let job: GcpJobResponse = response
            .json()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to parse job response: {e}")))?;

        let status = match job.state.as_str() {
            "PENDING" => TranscodeJobStatus::Pending,
            "RUNNING" => TranscodeJobStatus::Processing,
            "SUCCEEDED" => TranscodeJobStatus::Succeeded,
            "FAILED" => TranscodeJobStatus::Failed,
            _ => TranscodeJobStatus::Processing,
        };

        let progress = job
            .progress
            .map(|p| (p.progress * 100.0) as i32)
            .unwrap_or(0);

        // Build output URIs from the output configuration
        let mut output_uris = Vec::new();
        if status == TranscodeJobStatus::Succeeded {
            for profile in TranscodeProfile::default_profiles() {
                let gcs_uri = format!(
                    "gs://{}/reels/{}/{}.mp4",
                    self.config.gcs_bucket,
                    job_id
                        .replace("reel-", "")
                        .split('-')
                        .next()
                        .unwrap_or(job_id),
                    profile.name
                );
                let cdn_url = format!(
                    "{}/reels/{}/{}.mp4",
                    self.config.cdn_base_url.trim_end_matches('/'),
                    job_id
                        .replace("reel-", "")
                        .split('-')
                        .next()
                        .unwrap_or(job_id),
                    profile.name
                );
                output_uris.push(TranscodeOutput {
                    quality: profile.name,
                    gcs_uri,
                    cdn_url,
                    file_size_bytes: None, // Would need to query GCS for this
                });
            }
        }

        Ok(TranscodeJobResult {
            job_id: job_id.to_string(),
            status,
            progress,
            output_uris,
            error_message: job.error.map(|e| e.message),
        })
    }

    /// Poll a job until completion
    pub async fn wait_for_job(
        &mut self,
        job_id: &str,
        poll_interval: std::time::Duration,
        max_wait: std::time::Duration,
    ) -> Result<TranscodeJobResult> {
        let start = std::time::Instant::now();

        loop {
            let result = self.get_job_status(job_id).await?;

            match result.status {
                TranscodeJobStatus::Succeeded => {
                    info!("Transcoder job {} completed successfully", job_id);
                    return Ok(result);
                }
                TranscodeJobStatus::Failed => {
                    error!(
                        "Transcoder job {} failed: {:?}",
                        job_id, result.error_message
                    );
                    return Ok(result);
                }
                _ => {
                    if start.elapsed() > max_wait {
                        warn!("Transcoder job {} timed out after {:?}", job_id, max_wait);
                        return Ok(result);
                    }
                    tokio::time::sleep(poll_interval).await;
                }
            }
        }
    }
}

/// Check if real transcoding is enabled
pub fn is_transcoding_enabled() -> bool {
    let mock_enabled = std::env::var("MEDIA_TRANSCODE_ENABLE_MOCK")
        .map(|val| val == "1" || val.eq_ignore_ascii_case("true"))
        .unwrap_or(true);

    !mock_enabled && TranscoderConfig::from_env().is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_profiles() {
        let profiles = TranscodeProfile::default_profiles();
        assert_eq!(profiles.len(), 4);
        assert_eq!(profiles[0].name, "1080p");
        assert_eq!(profiles[0].width, 1920);
        assert_eq!(profiles[0].height, 1080);
    }

    #[test]
    fn test_is_transcoding_enabled_default() {
        // By default, mock is enabled (transcoding disabled)
        // This test depends on env vars not being set
        std::env::remove_var("MEDIA_TRANSCODE_ENABLE_MOCK");
        std::env::remove_var("GCP_PROJECT_ID");
        assert!(!is_transcoding_enabled());
    }
}
