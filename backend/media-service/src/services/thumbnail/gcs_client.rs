//! GCS Client for thumbnail operations
//!
//! Provides download/upload functionality using GCS REST API with service account authentication.

use crate::config::GcsConfig;
use crate::error::{AppError, Result};
use bytes::Bytes;
use chrono::Utc;
use percent_encoding::{utf8_percent_encode, AsciiSet, NON_ALPHANUMERIC};
use reqwest::Client;
use rsa::pkcs1v15::SigningKey;
use rsa::pkcs8::DecodePrivateKey;
use rsa::signature::{SignatureEncoding, Signer};
use rsa::RsaPrivateKey;
use sha2::{Digest, Sha256};
use std::fs;
use std::time::Duration;
use tracing::{debug, info};

/// Characters that must be percent-encoded in the path component
const PATH_SET: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'/')
    .remove(b'-')
    .remove(b'_')
    .remove(b'.')
    .remove(b'~');

/// GCS client for downloading and uploading objects with signed URLs
pub struct GcsClient {
    client_email: String,
    private_key: RsaPrivateKey,
    bucket: String,
    host: String,
    http_client: Client,
}

impl GcsClient {
    /// Create a new GCS client from raw parameters
    pub fn new(service_account_json: &str, bucket: &str, host: &str) -> Result<Self> {
        #[derive(serde::Deserialize)]
        struct Sa {
            client_email: String,
            private_key: String,
        }
        let sa: Sa = serde_json::from_str(service_account_json)
            .map_err(|e| AppError::Internal(format!("Invalid service account JSON: {e}")))?;

        let private_key = RsaPrivateKey::from_pkcs8_pem(&sa.private_key).map_err(|e| {
            AppError::Internal(format!("Failed to parse service account private key: {e}"))
        })?;

        let http_client = Client::builder()
            .timeout(Duration::from_secs(300))
            .build()
            .map_err(|e| AppError::Internal(format!("Failed to create HTTP client: {e}")))?;

        info!(bucket = %bucket, "GCS client initialized");

        Ok(Self {
            client_email: sa.client_email,
            private_key,
            bucket: bucket.to_string(),
            host: host.to_string(),
            http_client,
        })
    }

    /// Create a new GCS client from configuration
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

        let http_client = Client::builder()
            .timeout(Duration::from_secs(300))
            .build()
            .map_err(|e| AppError::Internal(format!("Failed to create HTTP client: {e}")))?;

        info!(bucket = %cfg.bucket, "GCS client initialized");

        Ok(Self {
            client_email: sa.client_email,
            private_key,
            bucket: cfg.bucket.clone(),
            host: cfg.host.clone(),
            http_client,
        })
    }

    /// Generate a V4 signed URL for GET (download)
    pub fn sign_get_url(&self, object_path: &str, expires_in: Duration) -> Result<String> {
        self.sign_url("GET", object_path, expires_in, None)
    }

    /// Generate a V4 signed URL for PUT (upload)
    pub fn sign_put_url(
        &self,
        object_path: &str,
        expires_in: Duration,
        content_type: Option<&str>,
    ) -> Result<String> {
        self.sign_url("PUT", object_path, expires_in, content_type)
    }

    fn sign_url(
        &self,
        method: &str,
        object_path: &str,
        expires_in: Duration,
        _content_type: Option<&str>,
    ) -> Result<String> {
        let now = Utc::now();
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

    /// Download an object from GCS
    pub async fn download(&self, object_path: &str) -> Result<Bytes> {
        let signed_url = self.sign_get_url(object_path, Duration::from_secs(300))?;

        debug!(object_path = %object_path, "Downloading from GCS");

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

        let bytes = response
            .bytes()
            .await
            .map_err(|e| AppError::Internal(format!("Failed to read GCS response: {e}")))?;

        debug!(object_path = %object_path, size = bytes.len(), "Downloaded from GCS");
        Ok(bytes)
    }

    /// Upload an object to GCS
    pub async fn upload(&self, object_path: &str, data: Bytes, content_type: &str) -> Result<()> {
        let signed_url =
            self.sign_put_url(object_path, Duration::from_secs(300), Some(content_type))?;

        debug!(object_path = %object_path, size = data.len(), "Uploading to GCS");

        let response = self
            .http_client
            .put(&signed_url)
            .header("Content-Type", content_type)
            .body(data.clone())
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

        info!(object_path = %object_path, size = data.len(), "Uploaded to GCS");
        Ok(())
    }

    /// Get the public URL for an object
    pub fn public_url(&self, object_path: &str) -> String {
        format!(
            "https://storage.googleapis.com/{}/{}",
            self.bucket, object_path
        )
    }

    /// Get the bucket name
    pub fn bucket(&self) -> &str {
        &self.bucket
    }
}
