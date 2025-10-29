/// S3 operations for media upload, download, and management
use aws_sdk_s3::Client;
use crate::config::S3Config;
use std::sync::Arc;

#[derive(Clone)]
pub struct S3Operations {
    client: Arc<Client>,
    config: S3Config,
}

impl S3Operations {
    pub fn new(client: Arc<Client>, config: S3Config) -> Self {
        Self { client, config }
    }

    /// Upload file to S3
    pub async fn upload_file(
        &self,
        key: &str,
        body: Vec<u8>,
        content_type: &str,
    ) -> Result<String, Box<dyn std::error::Error>> {
        self.client
            .put_object()
            .bucket(&self.config.bucket)
            .key(key)
            .content_type(content_type)
            .body(aws_sdk_s3::types::ByteStream::from(body))
            .send()
            .await?;

        Ok(self.config.cdn_url(key))
    }

    /// Download file from S3
    pub async fn download_file(
        &self,
        key: &str,
    ) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
        let response = self
            .client
            .get_object()
            .bucket(&self.config.bucket)
            .key(key)
            .send()
            .await?;

        let body = response.body.collect().await?;
        Ok(body.into_bytes().to_vec())
    }

    /// Delete file from S3
    pub async fn delete_file(&self, key: &str) -> Result<(), Box<dyn std::error::Error>> {
        self.client
            .delete_object()
            .bucket(&self.config.bucket)
            .key(key)
            .send()
            .await?;

        Ok(())
    }

    /// Generate presigned URL for downloading
    pub async fn get_presigned_download_url(
        &self,
        key: &str,
        expires_in: u64,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let presigner = self.client.config().presigning_config().ok_or("No presigning config")?;

        let request = self
            .client
            .get_object()
            .bucket(&self.config.bucket)
            .key(key)
            .presigned(presigner)
            .await?;

        Ok(request.uri().to_string())
    }

    /// Generate presigned URL for uploading
    pub async fn get_presigned_upload_url(
        &self,
        key: &str,
        content_type: &str,
    ) -> Result<String, Box<dyn std::error::Error>> {
        let presigner = self.client.config().presigning_config().ok_or("No presigning config")?;

        let request = self
            .client
            .put_object()
            .bucket(&self.config.bucket)
            .key(key)
            .content_type(content_type)
            .presigned(presigner)
            .await?;

        Ok(request.uri().to_string())
    }

    /// Copy object within S3
    pub async fn copy_object(
        &self,
        from_key: &str,
        to_key: &str,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let copy_source = format!("{}/{}", self.config.bucket, from_key);

        self.client
            .copy_object()
            .bucket(&self.config.bucket)
            .copy_source(copy_source)
            .key(to_key)
            .send()
            .await?;

        Ok(())
    }

    /// List objects with prefix
    pub async fn list_objects(
        &self,
        prefix: &str,
    ) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        let response = self
            .client
            .list_objects_v2()
            .bucket(&self.config.bucket)
            .prefix(prefix)
            .send()
            .await?;

        let keys = response
            .contents()
            .iter()
            .filter_map(|obj| obj.key().map(|k| k.to_string()))
            .collect();

        Ok(keys)
    }

    /// Check if object exists
    pub async fn object_exists(&self, key: &str) -> Result<bool, Box<dyn std::error::Error>> {
        match self
            .client
            .head_object()
            .bucket(&self.config.bucket)
            .key(key)
            .send()
            .await
        {
            Ok(_) => Ok(true),
            Err(e) => {
                if e.to_string().contains("NoSuchKey") || e.to_string().contains("404") {
                    Ok(false)
                } else {
                    Err(Box::new(e))
                }
            }
        }
    }

    /// Get object metadata
    pub async fn get_object_metadata(
        &self,
        key: &str,
    ) -> Result<ObjectMetadata, Box<dyn std::error::Error>> {
        let response = self
            .client
            .head_object()
            .bucket(&self.config.bucket)
            .key(key)
            .send()
            .await?;

        Ok(ObjectMetadata {
            size: response.content_length().unwrap_or(0) as u64,
            content_type: response.content_type().map(|s| s.to_string()),
            last_modified: response.last_modified().map(|t| t.to_string()),
            etag: response.e_tag().map(|s| s.to_string()),
        })
    }
}

#[derive(Debug, Clone)]
pub struct ObjectMetadata {
    pub size: u64,
    pub content_type: Option<String>,
    pub last_modified: Option<String>,
    pub etag: Option<String>,
}
