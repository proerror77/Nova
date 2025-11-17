use serde::Deserialize;
use tracing::{info, warn};

/// MediaUploaded-style payload as produced by media-service.
///
/// For now we only parse the fields we know we emit from media-service.
#[derive(Debug, Deserialize)]
pub struct MediaUploadedEvent {
    pub media_id: String,
    pub user_id: String,
    pub size_bytes: i64,
    pub file_name: String,
    // uploaded_at is kept as a generic JSON value to avoid tight coupling
    // to a specific timestamp format at this stage.
    pub uploaded_at: serde_json::Value,
}

/// Handle MediaUploaded events.
///
/// Current implementation只做解析與 log, 未真正修改資料庫。
/// 未來可以在這裡:
/// - attach_media_to_post(post_id, media_id)
/// - 或建立暫存關聯, 等 user 建立貼文時再綁定。
pub async fn handle_media_uploaded(event: MediaUploadedEvent) {
    info!(
        "Received MediaUploaded event: media_id={}, user_id={}, size_bytes={}",
        event.media_id, event.user_id, event.size_bytes
    );

    // TODO: 將 media_id 與 content-service 的 post 做關聯:
    // 1. 如果 event 中包含 post_id, 可直接更新 posts_medias 關聯表
    // 2. 否則可暫存 pending_media:{user_id} → [media_id] 等待後續貼文建立

    warn!(
        "MediaUploaded handler is currently a NO-OP (media_id={}, user_id={}), \
         attach_media_to_post is not implemented yet",
        event.media_id, event.user_id
    );
}

