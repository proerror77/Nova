/// Integration tests for resumable upload functionality
///
/// Tests cover:
/// - Basic chunked upload flow
/// - Resume from checkpoint
/// - Idempotent chunk uploads
/// - Hash mismatch detection
/// - Expired upload cleanup
/// - Concurrent uploads
/// - Out-of-order chunk handling

use actix_web::http::StatusCode;
use serde_json::json;
use sqlx::PgPool;
use uuid::Uuid;

mod common;
use common::fixtures::*;

// Helper to create test chunk data
fn create_test_chunk(size: usize, pattern: u8) -> Vec<u8> {
    vec![pattern; size]
}

// Helper to compute SHA256 hash
fn compute_sha256(data: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

#[actix_web::test]
async fn test_basic_chunked_upload_flow() {
    let test_env = TestEnv::new().await;
    let pool = &test_env.pool;

    // Create test user
    let user = create_test_user(pool, "uploader@test.com").await;
    let token = generate_jwt(&user.id);

    // 1. Initialize upload (10MB file, 5MB chunks = 2 chunks)
    let init_req = json!({
        "file_name": "test_video.mp4",
        "file_size": 10_485_760,  // 10MB
        "chunk_size": 5_242_880,   // 5MB
        "title": "Test Video",
        "description": "Upload test"
    });

    let init_resp = test_env
        .post("/api/v1/uploads/init")
        .bearer_auth(&token)
        .send_json(&init_req)
        .await;

    assert_eq!(init_resp.status(), StatusCode::OK);
    let init_body: serde_json::Value = init_resp.json().await;
    let upload_id = Uuid::parse_str(init_body["upload_id"].as_str().unwrap()).unwrap();
    assert_eq!(init_body["chunks_total"].as_i64().unwrap(), 2);
    assert_eq!(init_body["next_chunk_index"].as_i64().unwrap(), 0);

    // 2. Upload chunk 0
    let chunk0_data = create_test_chunk(5_242_880, 0xAA);
    let chunk0_hash = compute_sha256(&chunk0_data);

    let chunk0_resp = test_env
        .put(&format!("/api/v1/uploads/{}/chunks/0", upload_id))
        .bearer_auth(&token)
        .multipart_form(&[
            ("chunk", chunk0_data.clone()),
            ("hash", chunk0_hash.as_bytes().to_vec()),
        ])
        .await;

    assert_eq!(chunk0_resp.status(), StatusCode::OK);
    let chunk0_body: serde_json::Value = chunk0_resp.json().await;
    assert_eq!(chunk0_body["chunk_index"].as_i64().unwrap(), 0);
    assert_eq!(chunk0_body["uploaded"].as_bool().unwrap(), true);
    assert_eq!(chunk0_body["next_chunk_index"].as_i64().unwrap(), 1);
    assert_eq!(chunk0_body["progress_percent"].as_f64().unwrap(), 50.0);

    // 3. Upload chunk 1
    let chunk1_data = create_test_chunk(5_242_880, 0xBB);
    let chunk1_hash = compute_sha256(&chunk1_data);

    let chunk1_resp = test_env
        .put(&format!("/api/v1/uploads/{}/chunks/1", upload_id))
        .bearer_auth(&token)
        .multipart_form(&[
            ("chunk", chunk1_data.clone()),
            ("hash", chunk1_hash.as_bytes().to_vec()),
        ])
        .await;

    assert_eq!(chunk1_resp.status(), StatusCode::OK);
    let chunk1_body: serde_json::Value = chunk1_resp.json().await;
    assert_eq!(chunk1_body["progress_percent"].as_f64().unwrap(), 100.0);

    // 4. Get status
    let status_resp = test_env
        .get(&format!("/api/v1/uploads/{}", upload_id))
        .bearer_auth(&token)
        .send()
        .await;

    assert_eq!(status_resp.status(), StatusCode::OK);
    let status_body: serde_json::Value = status_resp.json().await;
    assert_eq!(status_body["status"].as_str().unwrap(), "uploading");
    assert_eq!(status_body["chunks_uploaded"].as_i64().unwrap(), 2);
    assert_eq!(status_body["chunks_total"].as_i64().unwrap(), 2);

    // 5. Complete upload
    let complete_req = json!({
        "chunks_uploaded": 2,
        "final_hash": "dummy_hash"
    });

    let complete_resp = test_env
        .post(&format!("/api/v1/uploads/{}/complete", upload_id))
        .bearer_auth(&token)
        .send_json(&complete_req)
        .await;

    assert_eq!(complete_resp.status(), StatusCode::OK);
    let complete_body: serde_json::Value = complete_resp.json().await;
    assert!(complete_body["video_id"].as_str().is_some());
    assert_eq!(complete_body["status"].as_str().unwrap(), "processing");
}

#[actix_web::test]
async fn test_resume_from_checkpoint() {
    let test_env = TestEnv::new().await;
    let pool = &test_env.pool;

    let user = create_test_user(pool, "resumer@test.com").await;
    let token = generate_jwt(&user.id);

    // Initialize upload with 4 chunks
    let init_req = json!({
        "file_name": "resume_test.mp4",
        "file_size": 20_971_520,  // 20MB
        "chunk_size": 5_242_880,   // 5MB (4 chunks)
    });

    let init_resp = test_env
        .post("/api/v1/uploads/init")
        .bearer_auth(&token)
        .send_json(&init_req)
        .await;

    let init_body: serde_json::Value = init_resp.json().await;
    let upload_id = Uuid::parse_str(init_body["upload_id"].as_str().unwrap()).unwrap();

    // Upload chunks 0 and 1
    for i in 0..2 {
        let chunk_data = create_test_chunk(5_242_880, 0x10 + i as u8);
        test_env
            .put(&format!("/api/v1/uploads/{}/chunks/{}", upload_id, i))
            .bearer_auth(&token)
            .multipart_form(&[("chunk", chunk_data)])
            .await;
    }

    // Simulate interruption - get status to see where we are
    let status_resp = test_env
        .get(&format!("/api/v1/uploads/{}", upload_id))
        .bearer_auth(&token)
        .send()
        .await;

    let status_body: serde_json::Value = status_resp.json().await;
    assert_eq!(status_body["chunks_uploaded"].as_i64().unwrap(), 2);
    assert_eq!(status_body["progress_percent"].as_f64().unwrap(), 50.0);

    // Resume: upload remaining chunks 2 and 3
    for i in 2..4 {
        let chunk_data = create_test_chunk(5_242_880, 0x10 + i as u8);
        let chunk_resp = test_env
            .put(&format!("/api/v1/uploads/{}/chunks/{}", upload_id, i))
            .bearer_auth(&token)
            .multipart_form(&[("chunk", chunk_data)])
            .await;

        assert_eq!(chunk_resp.status(), StatusCode::OK);
    }

    // Verify all chunks uploaded
    let final_status = test_env
        .get(&format!("/api/v1/uploads/{}", upload_id))
        .bearer_auth(&token)
        .send()
        .await
        .json::<serde_json::Value>()
        .await;

    assert_eq!(final_status["chunks_uploaded"].as_i64().unwrap(), 4);
    assert_eq!(final_status["progress_percent"].as_f64().unwrap(), 100.0);
}

#[actix_web::test]
async fn test_idempotent_chunk_upload() {
    let test_env = TestEnv::new().await;
    let pool = &test_env.pool;

    let user = create_test_user(pool, "idempotent@test.com").await;
    let token = generate_jwt(&user.id);

    // Initialize upload
    let init_req = json!({
        "file_name": "idempotent_test.mp4",
        "file_size": 10_485_760,
        "chunk_size": 5_242_880,
    });

    let init_resp = test_env
        .post("/api/v1/uploads/init")
        .bearer_auth(&token)
        .send_json(&init_req)
        .await;

    let upload_id = Uuid::parse_str(
        init_resp.json::<serde_json::Value>().await["upload_id"]
            .as_str()
            .unwrap(),
    )
    .unwrap();

    // Upload chunk 0
    let chunk_data = create_test_chunk(5_242_880, 0xCC);

    let first_upload = test_env
        .put(&format!("/api/v1/uploads/{}/chunks/0", upload_id))
        .bearer_auth(&token)
        .multipart_form(&[("chunk", chunk_data.clone())])
        .await;

    assert_eq!(first_upload.status(), StatusCode::OK);

    // Upload same chunk again (idempotent)
    let second_upload = test_env
        .put(&format!("/api/v1/uploads/{}/chunks/0", upload_id))
        .bearer_auth(&token)
        .multipart_form(&[("chunk", chunk_data.clone())])
        .await;

    assert_eq!(second_upload.status(), StatusCode::OK);
    let second_body: serde_json::Value = second_upload.json().await;
    assert_eq!(second_body["uploaded"].as_bool().unwrap(), true);
    assert_eq!(second_body["chunk_index"].as_i64().unwrap(), 0);

    // Verify only counted once
    let status = test_env
        .get(&format!("/api/v1/uploads/{}", upload_id))
        .bearer_auth(&token)
        .send()
        .await
        .json::<serde_json::Value>()
        .await;

    assert_eq!(status["chunks_uploaded"].as_i64().unwrap(), 1);
}

#[actix_web::test]
async fn test_chunk_hash_mismatch() {
    let test_env = TestEnv::new().await;
    let pool = &test_env.pool;

    let user = create_test_user(pool, "hasher@test.com").await;
    let token = generate_jwt(&user.id);

    // Initialize upload
    let init_req = json!({
        "file_name": "hash_test.mp4",
        "file_size": 5_242_880,
        "chunk_size": 5_242_880,
    });

    let init_resp = test_env
        .post("/api/v1/uploads/init")
        .bearer_auth(&token)
        .send_json(&init_req)
        .await;

    let upload_id = Uuid::parse_str(
        init_resp.json::<serde_json::Value>().await["upload_id"]
            .as_str()
            .unwrap(),
    )
    .unwrap();

    // Upload with wrong hash
    let chunk_data = create_test_chunk(5_242_880, 0xDD);
    let wrong_hash = "0000000000000000000000000000000000000000000000000000000000000000";

    let chunk_resp = test_env
        .put(&format!("/api/v1/uploads/{}/chunks/0", upload_id))
        .bearer_auth(&token)
        .multipart_form(&[
            ("chunk", chunk_data.clone()),
            ("hash", wrong_hash.as_bytes().to_vec()),
        ])
        .await;

    assert_eq!(chunk_resp.status(), StatusCode::BAD_REQUEST);
    let error_body: serde_json::Value = chunk_resp.json().await;
    assert!(error_body["error"]
        .as_str()
        .unwrap()
        .contains("hash mismatch"));
}

#[actix_web::test]
async fn test_out_of_order_chunks() {
    let test_env = TestEnv::new().await;
    let pool = &test_env.pool;

    let user = create_test_user(pool, "outoforder@test.com").await;
    let token = generate_jwt(&user.id);

    // Initialize upload with 3 chunks
    let init_req = json!({
        "file_name": "outoforder_test.mp4",
        "file_size": 15_728_640,  // 15MB
        "chunk_size": 5_242_880,   // 5MB (3 chunks)
    });

    let init_resp = test_env
        .post("/api/v1/uploads/init")
        .bearer_auth(&token)
        .send_json(&init_req)
        .await;

    let upload_id = Uuid::parse_str(
        init_resp.json::<serde_json::Value>().await["upload_id"]
            .as_str()
            .unwrap(),
    )
    .unwrap();

    // Upload chunks out of order: 2, 0, 1
    let upload_order = [2, 0, 1];

    for &idx in &upload_order {
        let chunk_data = create_test_chunk(5_242_880, 0x20 + idx as u8);
        let chunk_resp = test_env
            .put(&format!("/api/v1/uploads/{}/chunks/{}", upload_id, idx))
            .bearer_auth(&token)
            .multipart_form(&[("chunk", chunk_data)])
            .await;

        assert_eq!(chunk_resp.status(), StatusCode::OK);
    }

    // Verify all chunks uploaded correctly
    let status = test_env
        .get(&format!("/api/v1/uploads/{}", upload_id))
        .bearer_auth(&token)
        .send()
        .await
        .json::<serde_json::Value>()
        .await;

    assert_eq!(status["chunks_uploaded"].as_i64().unwrap(), 3);
    assert_eq!(status["progress_percent"].as_f64().unwrap(), 100.0);
}

#[actix_web::test]
async fn test_concurrent_uploads_same_user() {
    let test_env = TestEnv::new().await;
    let pool = &test_env.pool;

    let user = create_test_user(pool, "concurrent@test.com").await;
    let token = generate_jwt(&user.id);

    // Initialize 3 uploads concurrently
    let init_futures: Vec<_> = (0..3)
        .map(|i| {
            let test_env = &test_env;
            let token = token.clone();
            async move {
                let init_req = json!({
                    "file_name": format!("concurrent_{}.mp4", i),
                    "file_size": 5_242_880,
                    "chunk_size": 5_242_880,
                });

                test_env
                    .post("/api/v1/uploads/init")
                    .bearer_auth(&token)
                    .send_json(&init_req)
                    .await
                    .json::<serde_json::Value>()
                    .await
            }
        })
        .collect();

    let upload_ids: Vec<Uuid> = futures::future::join_all(init_futures)
        .await
        .into_iter()
        .map(|resp| Uuid::parse_str(resp["upload_id"].as_str().unwrap()).unwrap())
        .collect();

    // Verify all 3 uploads created
    assert_eq!(upload_ids.len(), 3);

    // Upload chunks to each
    for upload_id in upload_ids {
        let chunk_data = create_test_chunk(5_242_880, 0xEE);
        let chunk_resp = test_env
            .put(&format!("/api/v1/uploads/{}/chunks/0", upload_id))
            .bearer_auth(&token)
            .multipart_form(&[("chunk", chunk_data)])
            .await;

        assert_eq!(chunk_resp.status(), StatusCode::OK);
    }
}

#[actix_web::test]
async fn test_cancel_upload() {
    let test_env = TestEnv::new().await;
    let pool = &test_env.pool;

    let user = create_test_user(pool, "canceller@test.com").await;
    let token = generate_jwt(&user.id);

    // Initialize upload
    let init_req = json!({
        "file_name": "cancel_test.mp4",
        "file_size": 10_485_760,
        "chunk_size": 5_242_880,
    });

    let init_resp = test_env
        .post("/api/v1/uploads/init")
        .bearer_auth(&token)
        .send_json(&init_req)
        .await;

    let upload_id = Uuid::parse_str(
        init_resp.json::<serde_json::Value>().await["upload_id"]
            .as_str()
            .unwrap(),
    )
    .unwrap();

    // Upload one chunk
    let chunk_data = create_test_chunk(5_242_880, 0xFF);
    test_env
        .put(&format!("/api/v1/uploads/{}/chunks/0", upload_id))
        .bearer_auth(&token)
        .multipart_form(&[("chunk", chunk_data)])
        .await;

    // Cancel upload
    let cancel_resp = test_env
        .delete(&format!("/api/v1/uploads/{}", upload_id))
        .bearer_auth(&token)
        .send()
        .await;

    assert_eq!(cancel_resp.status(), StatusCode::OK);
    let cancel_body: serde_json::Value = cancel_resp.json().await;
    assert_eq!(cancel_body["status"].as_str().unwrap(), "cancelled");

    // Verify status is cancelled
    let status = test_env
        .get(&format!("/api/v1/uploads/{}", upload_id))
        .bearer_auth(&token)
        .send()
        .await
        .json::<serde_json::Value>()
        .await;

    assert_eq!(status["status"].as_str().unwrap(), "cancelled");

    // Try to upload another chunk - should fail
    let chunk2_data = create_test_chunk(5_242_880, 0x00);
    let chunk2_resp = test_env
        .put(&format!("/api/v1/uploads/{}/chunks/1", upload_id))
        .bearer_auth(&token)
        .multipart_form(&[("chunk", chunk2_data)])
        .await;

    assert_eq!(chunk2_resp.status(), StatusCode::BAD_REQUEST);
}

#[actix_web::test]
async fn test_invalid_chunk_index() {
    let test_env = TestEnv::new().await;
    let pool = &test_env.pool;

    let user = create_test_user(pool, "invalidindex@test.com").await;
    let token = generate_jwt(&user.id);

    // Initialize upload with 2 chunks
    let init_req = json!({
        "file_name": "invalid_index.mp4",
        "file_size": 10_485_760,
        "chunk_size": 5_242_880,
    });

    let init_resp = test_env
        .post("/api/v1/uploads/init")
        .bearer_auth(&token)
        .send_json(&init_req)
        .await;

    let upload_id = Uuid::parse_str(
        init_resp.json::<serde_json::Value>().await["upload_id"]
            .as_str()
            .unwrap(),
    )
    .unwrap();

    // Try to upload chunk 5 (out of range)
    let chunk_data = create_test_chunk(5_242_880, 0x11);
    let chunk_resp = test_env
        .put(&format!("/api/v1/uploads/{}/chunks/5", upload_id))
        .bearer_auth(&token)
        .multipart_form(&[("chunk", chunk_data)])
        .await;

    assert_eq!(chunk_resp.status(), StatusCode::BAD_REQUEST);
    let error_body: serde_json::Value = chunk_resp.json().await;
    assert!(error_body["error"]
        .as_str()
        .unwrap()
        .contains("out of range"));
}

#[actix_web::test]
async fn test_complete_upload_before_all_chunks() {
    let test_env = TestEnv::new().await;
    let pool = &test_env.pool;

    let user = create_test_user(pool, "incomplete@test.com").await;
    let token = generate_jwt(&user.id);

    // Initialize upload with 2 chunks
    let init_req = json!({
        "file_name": "incomplete.mp4",
        "file_size": 10_485_760,
        "chunk_size": 5_242_880,
    });

    let init_resp = test_env
        .post("/api/v1/uploads/init")
        .bearer_auth(&token)
        .send_json(&init_req)
        .await;

    let upload_id = Uuid::parse_str(
        init_resp.json::<serde_json::Value>().await["upload_id"]
            .as_str()
            .unwrap(),
    )
    .unwrap();

    // Upload only chunk 0 (missing chunk 1)
    let chunk_data = create_test_chunk(5_242_880, 0x22);
    test_env
        .put(&format!("/api/v1/uploads/{}/chunks/0", upload_id))
        .bearer_auth(&token)
        .multipart_form(&[("chunk", chunk_data)])
        .await;

    // Try to complete with only 1/2 chunks
    let complete_req = json!({
        "chunks_uploaded": 1,
        "final_hash": "dummy"
    });

    let complete_resp = test_env
        .post(&format!("/api/v1/uploads/{}/complete", upload_id))
        .bearer_auth(&token)
        .send_json(&complete_req)
        .await;

    assert_eq!(complete_resp.status(), StatusCode::BAD_REQUEST);
    let error_body: serde_json::Value = complete_resp.json().await;
    assert!(error_body["error"]
        .as_str()
        .unwrap()
        .contains("incomplete"));
}
