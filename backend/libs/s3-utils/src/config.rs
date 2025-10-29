/// S3 configuration shared across services
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct S3Config {
    /// S3 bucket name
    pub bucket: String,
    /// AWS region
    pub region: String,
    /// Base URL for public access (CDN domain)
    pub base_url: String,
    /// Whether to use path-style URLs (false = virtual-hosted-style)
    pub path_style: bool,
    /// Presigned URL expiration in seconds
    pub presigned_url_expiration_secs: u64,
}

impl S3Config {
    /// Load S3 configuration from environment variables
    pub fn from_env() -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {
            bucket: std::env::var("S3_BUCKET")
                .unwrap_or_else(|_| "nova-media".to_string()),
            region: std::env::var("AWS_REGION")
                .unwrap_or_else(|_| "us-east-1".to_string()),
            base_url: std::env::var("S3_BASE_URL")
                .unwrap_or_else(|_| "https://s3.amazonaws.com".to_string()),
            path_style: std::env::var("S3_PATH_STYLE")
                .unwrap_or_else(|_| "false".to_string())
                .parse()
                .unwrap_or(false),
            presigned_url_expiration_secs: std::env::var("S3_PRESIGNED_URL_EXPIRATION")
                .unwrap_or_else(|_| "3600".to_string())
                .parse()
                .unwrap_or(3600),
        })
    }

    /// Build S3 object URL
    pub fn object_url(&self, key: &str) -> String {
        if self.path_style {
            format!("{}/{}/{}", self.base_url, self.bucket, key)
        } else {
            format!("{}.s3.amazonaws.com/{}", self.bucket, key)
        }
    }

    /// Get CDN URL for object
    pub fn cdn_url(&self, key: &str) -> String {
        format!("{}/{}", self.base_url, key)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_object_url_virtual_hosted_style() {
        let config = S3Config {
            bucket: "test-bucket".to_string(),
            region: "us-east-1".to_string(),
            base_url: "https://s3.amazonaws.com".to_string(),
            path_style: false,
            presigned_url_expiration_secs: 3600,
        };

        let url = config.object_url("test/image.jpg");
        assert!(url.contains("test-bucket.s3.amazonaws.com"));
    }

    #[test]
    fn test_object_url_path_style() {
        let config = S3Config {
            bucket: "test-bucket".to_string(),
            region: "us-east-1".to_string(),
            base_url: "https://s3.amazonaws.com".to_string(),
            path_style: true,
            presigned_url_expiration_secs: 3600,
        };

        let url = config.object_url("test/image.jpg");
        assert_eq!(url, "https://s3.amazonaws.com/test-bucket/test/image.jpg");
    }
}
