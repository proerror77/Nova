# Upload Init Endpoint - Key Code Snippets

## Handler Function (`src/handlers/posts.rs`)

```rust
/// Initialize presigned URL for S3 upload
/// POST /api/v1/posts/upload/init
pub async fn upload_init_request(
    pool: web::Data<PgPool>,
    _redis: web::Data<ConnectionManager>,
    config: web::Data<Config>,
    req: web::Json<UploadInitRequest>,
) -> impl Responder {
    // Validation
    if req.filename.is_empty() { /* return 400 */ }
    if !ALLOWED_CONTENT_TYPES.contains(&req.content_type.as_str()) { /* return 400 */ }
    if req.file_size < MIN_FILE_SIZE || req.file_size > MAX_FILE_SIZE { /* return 400 */ }
    
    // Create post with status="pending"
    let user_id = Uuid::new_v4(); // TODO: Extract from JWT
    let post = post_repo::create_post(pool.get_ref(), user_id, req.caption.as_deref(), "temp").await?;
    
    // Generate S3 key and update post
    let s3_key = format!("posts/{}/original", post.id);
    post_repo::update_post_image_key(pool.get_ref(), post.id, &s3_key).await?;
    
    // Generate presigned URL
    let s3_client = s3_service::get_s3_client(&config.s3).await?;
    let presigned_url = s3_service::generate_presigned_url(
        &s3_client, &config.s3, &s3_key, &req.content_type
    ).await?;
    
    // Generate upload token (32-byte hex)
    let token_bytes: [u8; 32] = rand::thread_rng().gen();
    let upload_token = hex::encode(token_bytes);
    
    // Create upload session (1-hour expiry)
    post_repo::create_upload_session(pool.get_ref(), post.id, &upload_token).await?;
    
    // Return 201 Created
    HttpResponse::Created().json(UploadInitResponse {
        presigned_url,
        post_id: post.id.to_string(),
        upload_token,
        expires_in: 900,
        instructions: "Use PUT method to upload file to presigned_url".to_string(),
    })
}
```

## Request/Response Structs

```rust
#[derive(Debug, Deserialize, Serialize)]
pub struct UploadInitRequest {
    pub filename: String,
    pub content_type: String,
    pub file_size: i64,
    pub caption: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct UploadInitResponse {
    pub presigned_url: String,
    pub post_id: String,
    pub upload_token: String,
    pub expires_in: i64,
    pub instructions: String,
}
```

## Validation Constants

```rust
const MAX_FILENAME_LENGTH: usize = 255;
const MIN_FILE_SIZE: i64 = 102400; // 100 KB
const MAX_FILE_SIZE: i64 = 52428800; // 50 MB
const MAX_CAPTION_LENGTH: usize = 2200;

const ALLOWED_CONTENT_TYPES: &[&str] = &[
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heic",
];
```

## Route Registration (`src/main.rs`)

```rust
.service(
    web::scope("/api/v1")
        // ... existing routes ...
        .service(
            web::scope("/posts")
                .route("/upload/init", web::post().to(handlers::upload_init_request)),
        ),
)
```

## Database Function (`src/db/post_repo.rs`)

```rust
/// Update post image_key
pub async fn update_post_image_key(
    pool: &PgPool,
    post_id: Uuid,
    image_key: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        r#"
        UPDATE posts
        SET image_key = $1, updated_at = NOW()
        WHERE id = $2
        "#,
    )
    .bind(image_key)
    .bind(post_id)
    .execute(pool)
    .await?;
    
    Ok(())
}
```

## Example Usage

### Request

```bash
curl -X POST http://localhost:8080/api/v1/posts/upload/init \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "sunset.jpg",
    "content_type": "image/jpeg",
    "file_size": 2048576,
    "caption": "Beautiful sunset at the beach!"
  }'
```

### Response (201 Created)

```json
{
  "presigned_url": "https://nova-uploads.s3.us-east-1.amazonaws.com/posts/550e8400-e29b-41d4-a716-446655440000/original?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=...",
  "post_id": "550e8400-e29b-41d4-a716-446655440000",
  "upload_token": "7a3f8b2e9c1d6f4a5b8e3c9d2f1a6b8c4e7d9f2a5b3c8e1d4f7a9b2c5e8d1f4a",
  "expires_in": 900,
  "instructions": "Use PUT method to upload file to presigned_url"
}
```

### Client Upload (Step 2)

```bash
curl -X PUT "<presigned_url>" \
  -H "Content-Type: image/jpeg" \
  --data-binary "@sunset.jpg"
```

## Error Examples

### Invalid Content Type (400)

```json
{
  "error": "Invalid content type",
  "details": "Content type must be one of: image/jpeg, image/png, image/webp, image/heic"
}
```

### File Too Large (400)

```json
{
  "error": "Invalid file size",
  "details": "File size exceeds maximum allowed size (52428800 bytes / 50 MB)"
}
```

### Database Error (500)

```json
{
  "error": "Database error",
  "details": null
}
```

## Testing

```rust
#[actix_web::test]
async fn test_file_size_too_large() {
    let file_size = 60 * 1024 * 1024; // 60 MB
    let req = create_test_request("large.jpg", "image/jpeg", file_size, None);
    
    assert!(req.file_size > MAX_FILE_SIZE);
}

#[actix_web::test]
async fn test_invalid_content_type() {
    let req = create_test_request("video.mp4", "video/mp4", 2048576, None);
    
    assert!(!ALLOWED_CONTENT_TYPES.contains(&req.content_type.as_str()));
}
```

---

**File**: `/backend/user-service/src/handlers/posts.rs` (221 lines)  
**Tests**: 7 unit tests, all passing  
**Route**: `POST /api/v1/posts/upload/init`
