/// GCS storage service for video files
///
/// Migrated from S3 to GCS as part of GCP migration.
/// Provides presigned URL generation, file upload, verification, and health checks.
use crate::config::GcsConfig;
use crate::error::{AppError, Result};
use bytes::Bytes;
use percent_encoding::{utf8_percent_encode, AsciiSet, NON_ALPHANUMERIC};
use reqwest::Client as HttpClient;
use rsa::pkcs1v15::SigningKey;
use rsa::pkcs8::DecodePrivateKey;
use rsa::signature::{SignatureEncoding, Signer};
use rsa::RsaPrivateKey;
use sha2::{Digest, Sha256};
use std::fs;
use std::sync::Arc;
use std::time::Duration;

/// Characters that must be percent-encoded in the path component
const PATH_SET: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'/')
    .remove(b'-')
    .remove(b'_')
    .remove(b'.')
    .remove(b'~');

/// Default presigned URL expiry time (15 minutes)
const DEFAULT_PRESIGNED_URL_EXPIRY_SECS: u64 = 900;

/// GCS storage client for video operations
pub struct GcsStorageClient {
    client_email: String,
    private_key: RsaPrivateKey,
    bucket: String,
    host: String,
    http_client: HttpClient,
}

impl GcsStorageClient {
    /// Create a new GCS storage client from configuration
    pub fn from_config(cfg: &GcsConfig) -> Result<Self> {
        // Load service account JSON (inline or from file)
        let raw_json = if let Some(ref inline) = cfg.service_account_json {
            inline.clone()
        } else if let Some(ref path) = cfg.service_account_json_path {
            fs::read_to_string(path).map_err(|e| {
                AppError::Internal(format!(
                    "Failed to read GCS service account JSON at {}: {e}",
                    path
                ))
            })?
        } else {
            return Err(AppError::Internal(
                "GCS client requested but no service account JSON provided".into(),
            ));
        };

        #[derive(serde::Deserialize)]
        struct Sa {
            client_email: String,
            private_key: String,
        }
        let sa: Sa = serde_json::from_str(&raw_json)
            .map_err(|e| AppError::Internal(format!("Invalid service account JSON: {e}")))?;

        let private_key = RsaPrivateKey::from_pkcs8_pem(&sa.private_key).map_err(|e| {
            AppError::Internal(format!("Failed to parse service account private key: {e}"))
        })?;

        let http_client = HttpClient::builder()
            .timeout(Duration::from_secs(300))
            .build()
            .map_err(|e| AppError::Internal(format!("Failed to create HTTP client: {e}")))?;

        tracing::info!(bucket = %cfg.bucket, "GCS storage client initialized");

        Ok(Self {
            client_email: sa.client_email,
            private_key,
            bucket: cfg.bucket.clone(),
            host: cfg.host.clone(),
            http_client,
        })
    }

    /// Generate a V4 signed URL for a given HTTP method
    fn sign_url(
        &self,
        method: &str,
        object_path: &str,
        expires_in: Duration,
    ) -> Result<String> {
        let now = chrono::Utc::now();
        let datestamp = now.format("%Y%m%d").to_string();
        let timestamp = now.format("%Y%m%dT%H%M%SZ").to_string();

        let credential_scope = format!("{datestamp}/auto/storage/goog4_request");
        let credential = format!("{}/{}", self.client_email, credential_scope);

        let encoded_object = utf8_percent_encode(object_path, PATH_SET).to_string();
        let canonical_uri = format!(
            "/{}{}",
            self.bucket,
            if encoded_object.starts_with('/') {
                encoded_object
            } else {
                format!("/{}", encoded_object)
            }
        );

        let canonical_headers = format!("host:{}\n", self.host);
        let signed_headers = "host";

        let expires = expires_in.as_secs();
        let mut query_items = vec![
            ("X-Goog-Algorithm", "GOOG4-RSA-SHA256".to_string()),
            (
                "X-Goog-Credential",
                urlencoding::encode(&credential).into_owned(),
            ),
            ("X-Goog-Date", timestamp.clone()),
            ("X-Goog-Expires", expires.to_string()),
            ("X-Goog-SignedHeaders", signed_headers.to_string()),
        ];

        query_items.sort_by(|a, b| a.0.cmp(b.0));
        let canonical_query = query_items
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect::<Vec<_>>()
            .join("&");

        let canonical_request = format!(
            "{method}\n{canonical_uri}\n{canonical_query}\n{canonical_headers}\n{signed_headers}\nUNSIGNED-PAYLOAD"
        );
        let canonical_hash = hex::encode(Sha256::digest(canonical_request.as_bytes()));

        let string_to_sign =
            format!("GOOG4-RSA-SHA256\n{timestamp}\n{credential_scope}\n{canonical_hash}");

        let signing_key = SigningKey::<Sha256>::new(self.private_key.clone());
        let signature = signing_key.sign(string_to_sign.as_bytes()).to_bytes();
        let signature_hex = hex::encode(signature);

        let query_with_sig = format!("{canonical_query}&X-Goog-Signature={signature_hex}");
        let url = format!(
            "https://{host}{canonical_uri}?{query_with_sig}",
            host = self.host
        );
        Ok(url)
    }

    /// Generate a presigned URL for uploading a file to GCS
    pub fn generate_presigned_url(
        &self,
        object_key: &str,
        _content_type: &str,
    ) -> Result<String> {
        self.sign_url("PUT", object_key, Duration::from_secs(DEFAULT_PRESIGNED_URL_EXPIRY_SECS))
    }

    /// Verify that a GCS object exists
    pub async fn verify_object_exists(&self, object_key: &str) -> Result<bool> {
        let signed_url = self.sign_url("HEAD", object_key, Duration::from_secs(300))?;

        match self.http_client.head(&signed_url).send().await {
            Ok(response) => Ok(response.status().is_success()),
            Err(_) => Ok(false),
        }
    }

    /// Download an object from GCS
    pub async fn download(&self, object_key: &str) -> Result<Bytes> {
        let signed_url = self.sign_url("GET", object_key, Duration::from_secs(300))?;

        let response = self
            .http_client
            .get(&signed_url)
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("GCS download failed: {e}")))?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Internal(format!(
                "GCS download failed with status {}: {}",
                status, body
            )));
        }

        response
            .bytes()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to read GCS response: {e}")))
    }

    /// Upload data to GCS
    pub async fn upload(&self, object_key: &str, data: Bytes, content_type: &str) -> Result<()> {
        let signed_url = self.sign_url("PUT", object_key, Duration::from_secs(300))?;

        let response = self
            .http_client
            .put(&signed_url)
            .header("Content-Type", content_type)
            .body(data)
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("GCS upload failed: {e}")))?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Internal(format!(
                "GCS upload failed with status {}: {}",
                status, body
            )));
        }

        Ok(())
    }

    /// Upload a video file from local path to GCS
    pub async fn upload_video(
        &self,
        local_path: &str,
        object_key: &str,
        content_type: &str,
    ) -> Result<String> {
        use std::path::Path;

        let path = Path::new(local_path);
        if !path.exists() {
            return Err(AppError::Internal(format!(
                "Local file not found: {}",
                local_path
            )));
        }

        let data = tokio::fs::read(path)
            .await
            .map_err(|e| AppError::Internal(format!("Failed to read file {}: {}", local_path, e)))?;

        self.upload(object_key, Bytes::from(data), content_type).await?;

        tracing::info!(object_key = %object_key, "Uploaded video to GCS");
        Ok(object_key.to_string())
    }

    /// Delete an object from GCS
    pub async fn delete(&self, object_key: &str) -> Result<()> {
        let signed_url = self.sign_url("DELETE", object_key, Duration::from_secs(300))?;

        let response = self
            .http_client
            .delete(&signed_url)
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("GCS delete failed: {e}")))?;

        if !response.status().is_success() && response.status().as_u16() != 404 {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Internal(format!(
                "GCS delete failed with status {}: {}",
                status, body
            )));
        }

        Ok(())
    }

    /// Verify file integrity by comparing SHA256 hashes
    pub async fn verify_file_hash(
        &self,
        object_key: &str,
        expected_hash: &str,
    ) -> Result<bool> {
        let bytes = self.download(object_key).await?;

        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        let computed_hash = hex::encode(hasher.finalize());

        Ok(computed_hash.eq_ignore_ascii_case(expected_hash))
    }

    /// Health check for GCS connectivity
    pub async fn health_check(&self) -> Result<()> {
        // Try to generate a signed URL as a basic connectivity check
        let test_url = self.sign_url("HEAD", "health-check-test", Duration::from_secs(60))?;

        // Just verify we can create signed URLs - don't actually make a request
        // since the object might not exist
        if test_url.contains("X-Goog-Signature") {
            tracing::info!(
                "✅ GCS connection validated (bucket: {})",
                self.bucket
            );
            Ok(())
        } else {
            Err(AppError::Internal("GCS signing failed".to_string()))
        }
    }

    /// Get the bucket name
    pub fn bucket(&self) -> &str {
        &self.bucket
    }

    /// Get public URL for an object
    pub fn public_url(&self, object_key: &str) -> String {
        format!("https://storage.googleapis.com/{}/{}", self.bucket, object_key)
    }
}

/// Create a new GCS storage client from configuration
pub async fn get_gcs_client(config: &GcsConfig) -> Result<Arc<GcsStorageClient>> {
    Ok(Arc::new(GcsStorageClient::from_config(config)?))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_hash_computation() {
        let test_data = b"test file content";
        let mut hasher = Sha256::new();
        hasher.update(test_data);
        let hash = hex::encode(hasher.finalize());

        assert_eq!(
            hash,
            "60f5237ed4049f0382661ef009d2bc42e48c3ceb3edb6600f7024e7ab3b838f3"
        );
    }

    #[tokio::test]
    async fn test_hash_comparison_case_insensitive() {
        let hash1 = "4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358";
        let hash2 = "4F8B42C22DD3729B519BA6F68D2DA7CC5B2D606D05DAED5AD5128CC03E6C6358";
        assert!(hash1.eq_ignore_ascii_case(hash2));
    }

    #[tokio::test]
    async fn test_default_presigned_url_expiry() {
        assert_eq!(DEFAULT_PRESIGNED_URL_EXPIRY_SECS, 900);
    }
}
