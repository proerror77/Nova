use crate::config::GcsConfig;
use crate::error::{AppError, Result};
use percent_encoding::{utf8_percent_encode, AsciiSet, NON_ALPHANUMERIC};
use rsa::pkcs1v15::SigningKey;
use rsa::pkcs8::DecodePrivateKey;
use rsa::signature::{SignatureEncoding, Signer};
use rsa::RsaPrivateKey;
use sha2::{Digest, Sha256};
use std::fs;
use std::time::Duration;

/// Characters that must be percent-encoded in the path component
const PATH_SET: &AsciiSet = &NON_ALPHANUMERIC
    .remove(b'/')
    .remove(b'-')
    .remove(b'_')
    .remove(b'.')
    .remove(b'~');

/// Simple signer for GCS V4 signed URLs using service account JSON.
pub struct GcsSigner {
    client_email: String,
    private_key: RsaPrivateKey,
    host: String,
}

impl GcsSigner {
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
                "GCS signing requested but no service account JSON provided".into(),
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

        Ok(Self {
            client_email: sa.client_email,
            private_key,
            host: cfg.host.clone(),
        })
    }

    /// Generate a V4 signed URL for PUT upload.
    pub fn sign_put_url(
        &self,
        bucket: &str,
        object_path: &str,
        _content_type: &str,
        expires_in: Duration,
    ) -> Result<String> {
        // Timestamp
        let now = chrono::Utc::now();
        let datestamp = now.format("%Y%m%d").to_string();
        let timestamp = now.format("%Y%m%dT%H%M%SZ").to_string();

        // Scope
        let credential_scope = format!("{datestamp}/auto/storage/goog4_request");
        let credential = format!("{}/{}", self.client_email, credential_scope);

        // Canonical URI and host
        let encoded_object = utf8_percent_encode(object_path, PATH_SET).to_string();
        let canonical_uri = format!(
            "/{}{}",
            bucket,
            if encoded_object.starts_with('/') {
                encoded_object
            } else {
                format!("/{}", encoded_object)
            }
        );

        // Signed headers: only host (simplest, avoids content-type mismatch)
        let canonical_headers = format!("host:{}\n", self.host);
        let signed_headers = "host";

        // Query params (unordered, will be sorted as we format)
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

        // Canonical query string (sorted by key)
        query_items.sort_by(|a, b| a.0.cmp(b.0));
        let canonical_query = query_items
            .iter()
            .map(|(k, v)| format!("{}={}", k, v))
            .collect::<Vec<_>>()
            .join("&");

        // Canonical request
        let canonical_request = format!(
            "PUT\n{canonical_uri}\n{canonical_query}\n{canonical_headers}\n{signed_headers}\nUNSIGNED-PAYLOAD"
        );
        let canonical_hash = hex::encode(Sha256::digest(canonical_request.as_bytes()));

        // String to sign
        let string_to_sign =
            format!("GOOG4-RSA-SHA256\n{timestamp}\n{credential_scope}\n{canonical_hash}");

        // RSA SHA256 signature
        let signing_key = SigningKey::<Sha256>::new(self.private_key.clone());
        let signature = signing_key.sign(string_to_sign.as_bytes()).to_bytes();
        let signature_hex = hex::encode(signature);

        // Final URL
        let query_with_sig = format!("{canonical_query}&X-Goog-Signature={signature_hex}");
        let url = format!(
            "https://{host}{canonical_uri}?{query_with_sig}",
            host = self.host
        );
        Ok(url)
    }
}
