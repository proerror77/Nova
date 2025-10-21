use async_trait::async_trait;
use chrono::Utc;
use std::sync::Arc;
use streaming_core::{StreamError, ViewerSession};
use streaming_delivery::session_manager::{SessionManager, ViewerSessionStore};
use tokio::sync::Mutex;
use uuid::Uuid;

struct MockStore {
    sessions: Mutex<Vec<ViewerSession>>,
}

impl MockStore {
    fn new() -> Self {
        Self {
            sessions: Mutex::new(Vec::new()),
        }
    }
}

#[async_trait]
impl ViewerSessionStore for MockStore {
    async fn create_session(
        &self,
        stream_id: Uuid,
        viewer_id: &str,
        quality: Option<&str>,
    ) -> Result<ViewerSession, StreamError> {
        let mut guard = self.sessions.lock().await;
        let session = ViewerSession {
            id: Uuid::new_v4(),
            stream_id,
            viewer_id: viewer_id.into(),
            quality: quality.map(String::from),
            joined_at: Utc::now(),
            left_at: None,
        };
        guard.push(session.clone());
        Ok(session)
    }

    async fn update_session(
        &self,
        session_id: Uuid,
        quality: Option<&str>,
    ) -> Result<ViewerSession, StreamError> {
        let mut guard = self.sessions.lock().await;
        if let Some(session) = guard.iter_mut().find(|s| s.id == session_id) {
            session.quality = quality.map(String::from);
            return Ok(session.clone());
        }
        Err(StreamError::NotFound)
    }

    async fn end_session(&self, session_id: Uuid) -> Result<ViewerSession, StreamError> {
        let mut guard = self.sessions.lock().await;
        if let Some(session) = guard.iter_mut().find(|s| s.id == session_id) {
            session.left_at = Some(Utc::now());
            return Ok(session.clone());
        }
        Err(StreamError::NotFound)
    }

    async fn active_sessions(&self, stream_id: Uuid) -> Result<Vec<ViewerSession>, StreamError> {
        let guard = self.sessions.lock().await;
        Ok(guard
            .iter()
            .filter(|s| s.stream_id == stream_id && s.left_at.is_none())
            .cloned()
            .collect())
    }
}

#[actix_rt::test]
async fn session_manager_tracks_lifecycle() {
    let stream_id = Uuid::new_v4();
    let store: Arc<dyn ViewerSessionStore + Send + Sync> = Arc::new(MockStore::new());
    let manager = SessionManager::new(store);

    let session = manager
        .join_stream(stream_id, "viewer-1", Some("720p"))
        .await
        .expect("join");
    assert_eq!(manager.active_sessions(stream_id).await.unwrap().len(), 1);

    let updated = manager
        .switch_quality(session.id, Some("1080p"))
        .await
        .expect("switch");
    assert_eq!(updated.quality.as_deref(), Some("1080p"));

    manager.leave_stream(session.id).await.expect("leave");
    assert!(manager.active_sessions(stream_id).await.unwrap().is_empty());
}
