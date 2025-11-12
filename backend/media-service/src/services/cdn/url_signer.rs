// URL Signing Service - HMAC-SHA256 based URL signing
// Linus philosophy: Simple, no special cases, pure functions

use crate::error::{AppError, Result};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use std::time::{SystemTime, UNIX_EPOCH};

type HmacSha256 = Hmac<Sha256>;

/// URL signer with HMAC-SHA256 signatures
#[derive(Clone)]
pub struct UrlSigner {
    secret_key: String,
    domain: String,
}

impl UrlSigner {
    /// Create new URL signer
    pub fn new(secret_key: String, domain: String) -> Self {
        Self { secret_key, domain }
    }

    /// Sign URL with expiration timestamp
    /// Format: https://{domain}/{asset_key}?exp={timestamp}&sig={hmac_hex}
    pub fn sign_url(&self, asset_key: &str, ttl_seconds: u32) -> Result<String> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| AppError::Internal(format!("Time error: {}", e)))?
            .as_secs();

        let expiration = now + ttl_seconds as u64;

        // Payload: asset_key + expiration
        let payload = format!("{}:{}", asset_key, expiration);

        // HMAC-SHA256 signature
        let signature = self.compute_signature(&payload)?;

        // Build URL
        let url = format!(
            "https://{}/{}?exp={}&sig={}",
            self.domain, asset_key, expiration, signature
        );

        Ok(url)
    }

    /// Verify URL signature and check expiration
    pub fn verify_signature(&self, url: &str) -> Result<()> {
        let parsed = url::Url::parse(url)
            .map_err(|e| AppError::ValidationError(format!("Invalid URL: {}", e)))?;

        // Extract query parameters
        let exp = parsed
            .query_pairs()
            .find(|(k, _)| k == "exp")
            .ok_or_else(|| AppError::ValidationError("Missing exp parameter".into()))?
            .1
            .parse::<u64>()
            .map_err(|_| AppError::ValidationError("Invalid exp format".into()))?;

        let provided_sig = parsed
            .query_pairs()
            .find(|(k, _)| k == "sig")
            .ok_or_else(|| AppError::ValidationError("Missing sig parameter".into()))?
            .1
            .to_string();

        // Check expiration first (fail fast)
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| AppError::Internal(format!("Time error: {}", e)))?
            .as_secs();

        if now > exp {
            return Err(AppError::ValidationError("URL expired".into()));
        }

        // Extract asset key (path without domain and query)
        let asset_key = parsed
            .path()
            .strip_prefix('/')
            .ok_or_else(|| AppError::ValidationError("Invalid path".into()))?;

        // Recompute signature
        let payload = format!("{}:{}", asset_key, exp);
        let expected_sig = self.compute_signature(&payload)?;

        // Constant-time comparison
        if provided_sig != expected_sig {
            return Err(AppError::ValidationError("Invalid signature".into()));
        }

        Ok(())
    }

    /// Get expiration timestamp from URL
    pub fn get_expiration_time(&self, url: &str) -> Result<u64> {
        let parsed = url::Url::parse(url)
            .map_err(|e| AppError::ValidationError(format!("Invalid URL: {}", e)))?;

        let exp = parsed
            .query_pairs()
            .find(|(k, _)| k == "exp")
            .ok_or_else(|| AppError::ValidationError("Missing exp parameter".into()))?
            .1
            .parse::<u64>()
            .map_err(|_| AppError::ValidationError("Invalid exp format".into()))?;

        Ok(exp)
    }

    /// Compute HMAC-SHA256 signature (private helper)
    fn compute_signature(&self, payload: &str) -> Result<String> {
        let mut mac = HmacSha256::new_from_slice(self.secret_key.as_bytes())
            .map_err(|e| AppError::Internal(format!("HMAC error: {}", e)))?;

        mac.update(payload.as_bytes());
        let result = mac.finalize();
        let bytes = result.into_bytes();

        Ok(hex::encode(bytes))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_signer() -> UrlSigner {
        UrlSigner::new("test-secret-key".into(), "cdn.nova.dev".into())
    }

    #[test]
    fn test_sign_url_format() {
        let signer = create_signer();
        let url = signer.sign_url("user123/asset456/file.jpg", 3600).unwrap();

        assert!(url.starts_with("https://cdn.nova.dev/"));
        assert!(url.contains("user123/asset456/file.jpg"));
        assert!(url.contains("?exp="));
        assert!(url.contains("&sig="));
    }

    #[test]
    fn test_verify_valid_signature() {
        let signer = create_signer();
        let url = signer.sign_url("user123/asset456/file.jpg", 3600).unwrap();

        let result = signer.verify_signature(&url);
        assert!(result.is_ok());
    }

    #[test]
    fn test_verify_expired_url() {
        let signer = create_signer();
        let url = signer.sign_url("user123/asset456/file.jpg", 0).unwrap();

        std::thread::sleep(std::time::Duration::from_secs(1));

        let result = signer.verify_signature(&url);
        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), AppError::ValidationError(_)));
    }

    #[test]
    fn test_verify_tampered_signature() {
        let signer = create_signer();
        let mut url = signer.sign_url("user123/asset456/file.jpg", 3600).unwrap();

        // Tamper with signature
        url = url.replace("sig=", "sig=tampered");

        let result = signer.verify_signature(&url);
        assert!(result.is_err());
    }

    #[test]
    fn test_get_expiration_time() {
        let signer = create_signer();
        let url = signer.sign_url("user123/asset456/file.jpg", 3600).unwrap();

        let exp = signer.get_expiration_time(&url).unwrap();
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        assert!(exp > now);
        assert!(exp <= now + 3600);
    }

    #[test]
    fn test_different_keys_produce_different_signatures() {
        let signer1 = UrlSigner::new("key1".into(), "cdn.nova.dev".into());
        let signer2 = UrlSigner::new("key2".into(), "cdn.nova.dev".into());

        let url1 = signer1.sign_url("asset.jpg", 3600).unwrap();
        let url2 = signer2.sign_url("asset.jpg", 3600).unwrap();

        // Different keys = different signatures
        assert_ne!(url1, url2);
    }

    #[test]
    fn test_verify_missing_parameters() {
        let signer = create_signer();

        // Missing exp
        let url = "https://cdn.nova.dev/asset.jpg?sig=abc123";
        assert!(signer.verify_signature(url).is_err());

        // Missing sig
        let url = "https://cdn.nova.dev/asset.jpg?exp=9999999999";
        assert!(signer.verify_signature(url).is_err());
    }
}
