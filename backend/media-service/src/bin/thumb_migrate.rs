use aws_config::meta::region::RegionProviderChain;
use aws_config::BehaviorVersion;
use aws_sdk_s3::{primitives::ByteStream, Client as S3Client};
use image::imageops::FilterType;
use image::GenericImageView;
use image::ImageOutputFormat;
use sqlx::{postgres::PgPoolOptions, Row};
use std::io::Cursor;
use std::time::Duration;
use tokio::time::sleep;
use uuid::Uuid;

/// Simple thumbnail backfill tool.
///
/// - Finds original images in post_images without a completed thumbnail variant.
/// - Downloads from S3, resizes (max 600px), uploads to S3 under thumbnails/{post_id}/{id}.jpg.
/// - Inserts post_images row size_variant='thumbnail' with status 'completed'.
///
/// Env vars reused from media-service:
/// DATABASE_URL, S3_BUCKET, AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, S3_ENDPOINT (optional).
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let database_url = std::env::var("DATABASE_URL")?;
    let bucket = std::env::var("S3_BUCKET")?;

    let pool = PgPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await?;

    let region_provider = RegionProviderChain::default_provider().or_else("us-east-1");
    let mut config_loader = aws_config::defaults(BehaviorVersion::latest()).region(region_provider);
    if let Ok(endpoint) = std::env::var("S3_ENDPOINT") {
        config_loader = config_loader.endpoint_url(endpoint);
    }
    let aws_config = config_loader.load().await;
    let s3 = S3Client::new(&aws_config);

    // Process in small batches to avoid overloading DB/S3.
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
            let s3_key: String = row.get("s3_key");

            println!("Processing post {} original {}", post_id, s3_key);

            // Download original
            let obj = s3
                .get_object()
                .bucket(&bucket)
                .key(&s3_key)
                .send()
                .await?;
            let data = obj.body.collect().await?.to_vec();

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
            s3.put_object()
                .bucket(&bucket)
                .key(&thumb_key)
                .body(ByteStream::from(buf.clone()))
                .content_type("image/jpeg")
                .send()
                .await?;

            let thumb_url = if let (Ok(region), false) = (
                std::env::var("AWS_REGION"),
                std::env::var("S3_ENDPOINT").is_ok(),
            ) {
                format!(
                    "https://{}.s3.{}.amazonaws.com/{}",
                    bucket, region, thumb_key
                )
            } else {
                // Custom endpoint (e.g., MinIO); expose raw key for downstream to sign.
                format!("/{thumb_key}")
            };

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

            // Small pause to avoid S3 throttling burst.
            sleep(Duration::from_millis(50)).await;
        }
    }

    Ok(())
}
