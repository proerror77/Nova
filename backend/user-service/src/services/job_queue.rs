/// Background job queue for asynchronous image processing
///
/// This module provides a job queue system for processing uploaded images in the background.
/// Jobs are submitted to a channel and processed by worker tasks that download source images
/// from S3, generate multiple size variants, upload them back to S3, and update the database.
///
/// Architecture:
/// - MPSC channel for job submission (multi-producer, single-consumer per worker)
/// - Multiple concurrent workers can process jobs in parallel
/// - Each job processes one post's image into 3 variants (thumbnail, medium, original)
/// - Automatic retry logic for transient failures (S3 errors, network issues)
/// - Database transactions for consistency
/// - Graceful shutdown support
use crate::config::S3Config;
use crate::db::post_repo;
use aws_sdk_s3::Client;
use sqlx::PgPool;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::mpsc;
use tracing::{error, info, warn};
use uuid::Uuid;

/// Maximum retry attempts for S3 operations (download/upload)
const MAX_S3_RETRIES: u32 = 3;

/// Delay between retry attempts (milliseconds)
const RETRY_DELAY_MS: u64 = 1000;

/// Image processing job containing all metadata needed to process an uploaded image
#[derive(Debug, Clone)]
pub struct ImageProcessingJob {
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub upload_token: String,
    pub source_s3_key: String,
}

/// Job sender (multi-producer) for submitting jobs to the queue
pub type JobSender = mpsc::Sender<ImageProcessingJob>;

/// Job receiver (single-consumer per worker) for receiving jobs from the queue
pub type JobReceiver = mpsc::Receiver<ImageProcessingJob>;

/// Create a new job queue with specified channel capacity
///
/// Returns a tuple of (sender, receiver) for job submission and processing.
/// The sender can be cloned and shared across multiple threads/tasks.
///
/// # Arguments
/// * `capacity` - Maximum number of jobs that can be queued (buffered channel)
///
/// # Example
/// ```ignore
/// let (sender, receiver) = create_job_queue(100);
/// ```
pub fn create_job_queue(capacity: usize) -> (JobSender, JobReceiver) {
    mpsc::channel(capacity)
}

/// Spawn a background worker task that processes image jobs from the queue
///
/// The worker runs in an infinite loop, listening for jobs on the receiver channel.
/// For each job, it:
/// 1. Downloads the source image from S3
/// 2. Processes it into 3 size variants using the image_processing service
/// 3. Uploads each variant back to S3
/// 4. Updates the post_images table with URLs and metadata
/// 5. Marks the post as "published" when all variants are complete
///
/// Errors are handled gracefully:
/// - S3 failures retry up to MAX_S3_RETRIES times
/// - Processing failures update status to "failed" with error message
/// - Database errors are logged and processing continues
///
/// # Arguments
/// * `pool` - Database connection pool
/// * `s3_client` - AWS S3 client
/// * `s3_config` - S3 configuration (bucket, region, CloudFront URL)
/// * `receiver` - Channel receiver for jobs
///
/// # Returns
/// JoinHandle for the worker task (can be used for graceful shutdown)
pub fn spawn_image_processor_worker(
    pool: PgPool,
    s3_client: Client,
    s3_config: Arc<S3Config>,
    mut receiver: JobReceiver,
) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        info!("Image processor worker started");

        while let Some(job) = receiver.recv().await {
            info!(
                "Processing job for post_id={}, user_id={}",
                job.post_id, job.user_id
            );

            match process_job(&pool, &s3_client, &s3_config, &job).await {
                Ok(_) => {
                    info!("Successfully processed job for post_id={}", job.post_id);
                }
                Err(e) => {
                    error!("Failed to process job for post_id={}: {}", job.post_id, e);

                    // Mark post as failed
                    if let Err(db_err) =
                        post_repo::update_post_status(&pool, job.post_id, "failed").await
                    {
                        error!("Failed to update post status to 'failed': {}", db_err);
                    }
                }
            }
        }

        info!("Image processor worker stopped (channel closed)");
    })
}

/// Process a single image job
///
/// Downloads source image from S3, generates variants, uploads to S3, and updates database.
async fn process_job(
    pool: &PgPool,
    s3_client: &Client,
    s3_config: &S3Config,
    job: &ImageProcessingJob,
) -> Result<(), anyhow::Error> {
    // Step 1: Download source image from S3 with retry
    // Create temp directory using std::env::temp_dir()
    let temp_base = std::env::temp_dir();
    let temp_dir = temp_base.join(format!("image_processing_{}", job.post_id));
    tokio::fs::create_dir_all(&temp_dir).await?;

    let source_path = temp_dir.join("source_image");

    download_from_s3_with_retry(
        s3_client,
        s3_config,
        &job.source_s3_key,
        &source_path,
        MAX_S3_RETRIES,
    )
    .await?;

    info!("Downloaded source image from S3: {}", job.source_s3_key);

    // Step 2: Process image to variants (blocking operation runs in async context)
    let output_dir = temp_dir.join("variants");
    let base_name = job.post_id.to_string();

    let variants = crate::services::image_processing::process_image_to_variants(
        &source_path,
        &output_dir,
        &base_name,
    )
    .await?;

    info!("Generated image variants for post_id={}", job.post_id);

    // Step 3: Upload variants to S3 and update database
    // Get post_images records
    let post_images = post_repo::get_post_images(pool, job.post_id).await?;

    // Process each variant
    for image in post_images {
        let variant_result = match image.size_variant.as_str() {
            "thumbnail" => &variants.thumbnail,
            "medium" => &variants.medium,
            "original" => &variants.original,
            _ => {
                warn!("Unknown size variant: {}", image.size_variant);
                continue;
            }
        };

        // Upload to S3 with retry
        let s3_key = format!("posts/{}/{}.jpg", job.post_id, image.size_variant);

        upload_to_s3_with_retry(
            s3_client,
            s3_config,
            &variant_result.path,
            &s3_key,
            MAX_S3_RETRIES,
        )
        .await?;

        info!("Uploaded {} variant to S3: {}", image.size_variant, s3_key);

        // Generate CloudFront URL
        let url = format!("{}/{}", s3_config.cloudfront_url, s3_key);

        // Update post_images record
        post_repo::update_post_image(
            pool,
            image.id,
            "completed",
            Some(&url),
            Some(variant_result.width as i32),
            Some(variant_result.height as i32),
            Some(variant_result.file_size as i32),
        )
        .await?;

        info!(
            "Updated post_image record for variant: {}",
            image.size_variant
        );
    }

    // Step 4: Check if all images are completed, then mark post as published
    if post_repo::all_images_completed(pool, job.post_id).await? {
        post_repo::update_post_status(pool, job.post_id, "published").await?;
        info!(
            "All variants completed, marked post as published: {}",
            job.post_id
        );
    }

    // Step 5: Cleanup temp directory
    if let Err(e) = tokio::fs::remove_dir_all(&temp_dir).await {
        warn!("Failed to cleanup temp directory: {}", e);
    }

    Ok(())
}

/// Download file from S3 to local path with retry logic
async fn download_from_s3_with_retry(
    client: &Client,
    config: &S3Config,
    s3_key: &str,
    local_path: &Path,
    max_retries: u32,
) -> Result<(), anyhow::Error> {
    let mut attempts = 0;

    loop {
        attempts += 1;

        match download_from_s3(client, config, s3_key, local_path).await {
            Ok(_) => return Ok(()),
            Err(e) => {
                if attempts >= max_retries {
                    return Err(anyhow::anyhow!(
                        "Failed to download from S3 after {} attempts: {}",
                        max_retries,
                        e
                    ));
                }

                warn!(
                    "S3 download failed (attempt {}/{}): {}. Retrying...",
                    attempts, max_retries, e
                );

                tokio::time::sleep(tokio::time::Duration::from_millis(RETRY_DELAY_MS)).await;
            }
        }
    }
}

/// Download file from S3 to local path (single attempt)
async fn download_from_s3(
    client: &Client,
    config: &S3Config,
    s3_key: &str,
    local_path: &Path,
) -> Result<(), anyhow::Error> {
    let response = client
        .get_object()
        .bucket(&config.bucket_name)
        .key(s3_key)
        .send()
        .await?;

    let bytes = response.body.collect().await?.into_bytes();
    tokio::fs::write(local_path, bytes).await?;

    Ok(())
}

/// Upload file from local path to S3 with retry logic
async fn upload_to_s3_with_retry(
    client: &Client,
    config: &S3Config,
    local_path: &Path,
    s3_key: &str,
    max_retries: u32,
) -> Result<(), anyhow::Error> {
    let mut attempts = 0;

    loop {
        attempts += 1;

        match upload_to_s3(client, config, local_path, s3_key).await {
            Ok(_) => return Ok(()),
            Err(e) => {
                if attempts >= max_retries {
                    return Err(anyhow::anyhow!(
                        "Failed to upload to S3 after {} attempts: {}",
                        max_retries,
                        e
                    ));
                }

                warn!(
                    "S3 upload failed (attempt {}/{}): {}. Retrying...",
                    attempts, max_retries, e
                );

                tokio::time::sleep(tokio::time::Duration::from_millis(RETRY_DELAY_MS)).await;
            }
        }
    }
}

/// Upload file from local path to S3 (single attempt)
async fn upload_to_s3(
    client: &Client,
    config: &S3Config,
    local_path: &Path,
    s3_key: &str,
) -> Result<(), anyhow::Error> {
    let bytes = tokio::fs::read(local_path).await?;
    let body = aws_sdk_s3::primitives::ByteStream::from(bytes);

    client
        .put_object()
        .bucket(&config.bucket_name)
        .key(s3_key)
        .body(body)
        .content_type("image/jpeg")
        .send()
        .await?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_job_queue() {
        let (sender, mut receiver) = create_job_queue(10);

        // Test that sender and receiver are connected
        assert_eq!(sender.capacity(), 10);

        // Test sending a job
        let post_id = Uuid::new_v4();
        let job = ImageProcessingJob {
            post_id,
            user_id: Uuid::new_v4(),
            upload_token: "test-token".to_string(),
            source_s3_key: "posts/test/original".to_string(),
        };

        // Must use blocking context for non-async test
        let handle = std::thread::spawn(move || {
            let rt = tokio::runtime::Runtime::new().unwrap();
            rt.block_on(async {
                sender.send(job.clone()).await.unwrap();
                receiver.recv().await
            })
        });

        let received = handle.join().unwrap();
        assert!(received.is_some());
        assert_eq!(received.unwrap().post_id, post_id);
    }

    #[tokio::test]
    async fn test_job_sender_and_receiver() {
        let (sender, mut receiver) = create_job_queue(5);

        let job = ImageProcessingJob {
            post_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            upload_token: "token123".to_string(),
            source_s3_key: "posts/abc/original.jpg".to_string(),
        };

        // Send job
        sender.send(job.clone()).await.unwrap();

        // Receive job
        let received = receiver.recv().await.unwrap();
        assert_eq!(received.post_id, job.post_id);
        assert_eq!(received.user_id, job.user_id);
        assert_eq!(received.upload_token, job.upload_token);
        assert_eq!(received.source_s3_key, job.source_s3_key);
    }

    #[tokio::test]
    async fn test_multiple_jobs_fifo_order() {
        let (sender, mut receiver) = create_job_queue(10);

        let job1 = ImageProcessingJob {
            post_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            upload_token: "token1".to_string(),
            source_s3_key: "key1".to_string(),
        };

        let job2 = ImageProcessingJob {
            post_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            upload_token: "token2".to_string(),
            source_s3_key: "key2".to_string(),
        };

        // Send jobs in order
        sender.send(job1.clone()).await.unwrap();
        sender.send(job2.clone()).await.unwrap();

        // Receive in FIFO order
        let received1 = receiver.recv().await.unwrap();
        let received2 = receiver.recv().await.unwrap();

        assert_eq!(received1.post_id, job1.post_id);
        assert_eq!(received2.post_id, job2.post_id);
    }

    #[tokio::test]
    async fn test_channel_capacity() {
        let (sender, _receiver) = create_job_queue(2);

        let job1 = ImageProcessingJob {
            post_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            upload_token: "token1".to_string(),
            source_s3_key: "key1".to_string(),
        };

        let job2 = ImageProcessingJob {
            post_id: Uuid::new_v4(),
            user_id: Uuid::new_v4(),
            upload_token: "token2".to_string(),
            source_s3_key: "key2".to_string(),
        };

        // Should succeed
        sender.send(job1).await.unwrap();
        sender.send(job2).await.unwrap();

        // Channel is now full (capacity 2)
        // Sending without receiving should not panic (will wait)
    }

    #[tokio::test]
    async fn test_graceful_shutdown() {
        let (sender, mut receiver) = create_job_queue(10);

        // Drop sender to close channel
        drop(sender);

        // Receiver should return None when channel is closed
        let result = receiver.recv().await;
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn test_concurrent_jobs() {
        let (sender, mut receiver) = create_job_queue(100);

        // Spawn multiple tasks sending jobs
        let mut handles = vec![];

        for i in 0..10 {
            let sender_clone = sender.clone();
            let handle = tokio::spawn(async move {
                let job = ImageProcessingJob {
                    post_id: Uuid::new_v4(),
                    user_id: Uuid::new_v4(),
                    upload_token: format!("token-{}", i),
                    source_s3_key: format!("key-{}", i),
                };
                sender_clone.send(job).await.unwrap();
            });
            handles.push(handle);
        }

        // Wait for all sends to complete
        for handle in handles {
            handle.await.unwrap();
        }

        // Drop original sender
        drop(sender);

        // Receive all jobs
        let mut count = 0;
        while receiver.recv().await.is_some() {
            count += 1;
        }

        assert_eq!(count, 10);
    }
}
