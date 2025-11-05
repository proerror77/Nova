use std::time::Duration;

use aws_sdk_s3::config::{Credentials, Region};
use aws_sdk_s3::presigning::PresigningConfig;
use aws_sdk_s3::Client;

use crate::config::S3Config;
use crate::error::AppError;

/// Build an AWS S3 client from the provided configuration.
pub async fn build_s3_client(config: &S3Config) -> Result<Client, AppError> {
    let credentials = Credentials::new(
        &config.aws_access_key_id,
        &config.aws_secret_access_key,
        None,
        None,
        "user-service",
    );

    let shared_config = aws_config::defaults(aws_config::BehaviorVersion::latest())
        .region(Region::new(config.region.clone()))
        .credentials_provider(credentials)
        .load()
        .await;

    let mut builder = aws_sdk_s3::config::Builder::from(&shared_config);
    if let Some(endpoint) = &config.endpoint {
        if !endpoint.trim().is_empty() {
            builder = builder.endpoint_url(endpoint);
        }
    }

    Ok(Client::from_conf(builder.build()))
}

/// Generate a presigned URL for uploading content to S3.
pub async fn generate_presigned_put_url(
    client: &Client,
    config: &S3Config,
    s3_key: &str,
    content_type: &str,
    expires_in: Duration,
) -> Result<String, AppError> {
    let presign_cfg = PresigningConfig::builder()
        .expires_in(expires_in)
        .build()
        .map_err(|e| AppError::Internal(format!("Failed to create presign config: {e}")))?;

    let presigned = client
        .put_object()
        .bucket(&config.bucket_name)
        .key(s3_key)
        .content_type(content_type)
        .presigned(presign_cfg)
        .await
        .map_err(|e| AppError::Internal(format!("Failed to generate presigned URL: {e}")))?;

    Ok(presigned.uri().to_string())
}
