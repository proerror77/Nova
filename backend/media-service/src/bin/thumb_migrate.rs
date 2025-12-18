use image::imageops::FilterType;
use image::GenericImageView;
use image::ImageOutputFormat;
use media_service::config::GcsConfig;
use media_service::services::video::GcsStorageClient;
use sqlx::{postgres::PgPoolOptions, Row};
use std::io::Cursor;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::sleep;
use uuid::Uuid;

/// Simple thumbnail backfill tool.
///
/// - Finds original images in post_images without a completed thumbnail variant.
/// - Downloads from GCS, resizes (max 600px), uploads to GCS under thumbnails/{post_id}/{id}.jpg.
/// - Inserts post_images row size_variant='thumbnail' with status 'completed'.
///
/// Env vars:
/// DATABASE_URL, GCS_BUCKET, GCS_SERVICE_ACCOUNT_JSON or GCS_SERVICE_ACCOUNT_JSON_PATH
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let database_url = std::env::var("DATABASE_URL")?;
    let bucket = std::env::var("GCS_BUCKET")?;

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await?;

    // Initialize GCS client
    let gcs_config = GcsConfig {
        bucket: bucket.clone(),
        service_account_json: std::env::var("GCS_SERVICE_ACCOUNT_JSON").ok(),
        service_account_json_path: std::env::var("GCS_SERVICE_ACCOUNT_JSON_PATH").ok(),
        host: std::env::var("GCS_HOST").unwrap_or_else(|_| "storage.googleapis.com".to_string()),
    };

    let gcs = Arc::new(
        GcsStorageClient::from_config(&gcs_config)
            .map_err(|e| format!("Failed to create GCS client: {}", e))?,
    );

    // Process in small batches to avoid overloading DB/GCS.
    const BATCH_SIZE: i64 = 20;
    loop {
        let rows = sqlx::query(
            r#"
            SELECT pi.id, pi.post_id, pi.s3_key
            FROM post_images pi
            WHERE pi.size_variant = 'original'
              AND pi.status = 'completed'
              AND NOT EXISTS (
                SELECT 1 FROM post_images t
                WHERE t.post_id = pi.post_id
                  AND t.size_variant = 'thumbnail'
                  AND t.status = 'completed'
              )
            ORDER BY pi.created_at ASC
            LIMIT $1
            "#,
        )
        .bind(BATCH_SIZE)
        .fetch_all(&pool)
        .await?;

        if rows.is_empty() {
            println!("No more images missing thumbnails. Done.");
            break;
        }

        for row in rows {
            let record_id: Uuid = row.get("id");
            let post_id: Uuid = row.get("post_id");
            let storage_key: String = row.get("s3_key"); // Legacy column name, now GCS key

            println!("Processing post {} original {}", post_id, storage_key);

            // Download original from GCS
            let data = gcs
                .download(&storage_key)
                .await
                .map_err(|e| format!("Failed to download {}: {}", storage_key, e))?;

            // Decode & resize
            let img = image::load_from_memory(&data)?;
            let (w, h) = img.dimensions();
            let max_dim = 600u32;
            let (new_w, new_h) = if w > h {
                let ratio = max_dim as f32 / w as f32;
                (max_dim, ((h as f32) * ratio).round() as u32)
            } else {
                let ratio = max_dim as f32 / h as f32;
                (((w as f32) * ratio).round() as u32, max_dim)
            };
            let resized = img.resize_exact(new_w.max(1), new_h.max(1), FilterType::Triangle);

            let mut buf = Vec::new();
            let mut cursor = Cursor::new(&mut buf);
            resized.write_to(&mut cursor, ImageOutputFormat::Jpeg(85))?;

            let thumb_key = format!("thumbnails/{}/{}.jpg", post_id, record_id);

            // Upload thumbnail to GCS
            gcs.upload(&thumb_key, bytes::Bytes::from(buf.clone()), "image/jpeg")
                .await
                .map_err(|e| format!("Failed to upload {}: {}", thumb_key, e))?;

            // Generate public URL for the thumbnail
            let thumb_url = gcs.public_url(&thumb_key);

            // Insert thumbnail row (id auto-generated)
            sqlx::query(
                r#"
                INSERT INTO post_images (post_id, s3_key, status, size_variant, file_size, width, height, url)
                SELECT $1, $2, 'completed', 'thumbnail', $3, $4, $5, $6
                WHERE NOT EXISTS (
                    SELECT 1 FROM post_images
                    WHERE post_id = $1 AND size_variant = 'thumbnail' AND status = 'completed'
                )
                "#,
            )
            .bind(post_id)
            .bind(&thumb_key)
            .bind(buf.len() as i32)
            .bind(new_w as i32)
            .bind(new_h as i32)
            .bind(thumb_url)
            .execute(&pool)
            .await?;

            // Small pause to avoid GCS throttling burst.
            sleep(Duration::from_millis(50)).await;
        }
    }

    Ok(())
}
