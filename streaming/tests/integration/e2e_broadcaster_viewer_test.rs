use actix_web::{body, test, web, App};
use async_trait::async_trait;
use awc::{ws, Client};
use chrono::Utc;
use futures_util::StreamExt;
use std::sync::Arc;
use streaming_core::{models::QualityLevel, StreamError, ViewerSession};
use streaming_delivery::cdn_config::CdnConfig;
use streaming_delivery::cdn_url_rewriter::CdnUrlRewriter;
use streaming_delivery::hls_handler::{master_playlist, HlsState};
use streaming_delivery::session_manager::{SessionManager, ViewerSessionStore};
use streaming_delivery::status_publisher::StreamStatusPublisher;
use streaming_delivery::websocket_hub::WebSocketHub;
use tokio::sync::Mutex;
use uuid::Uuid;

use super::support::start_websocket_server;

struct DummyStore {
    sessions: Mutex<Vec<ViewerSession>>,
}

impl DummyStore {
    fn new() -> Self {
        Self {
            sessions: Mutex::new(Vec::new()),
        }
    }
}

#[async_trait]
impl ViewerSessionStore for DummyStore {
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
async fn end_to_end_flow_simulation() {
    let stream_id = Uuid::new_v4();
    let hub = WebSocketHub::new();
    let publisher = StreamStatusPublisher::new(hub.clone());
    let (addr, handle) = start_websocket_server(hub.clone(), publisher.clone())
        .await
        .expect("start websocket server");
    let client = Client::new();
    let (_resp, mut ws_client) = client
        .ws(format!("http://{addr}/ws/stream/{stream_id}"))
        .connect()
        .await
        .expect("connect websocket client");

    publisher.stream_started(stream_id);

    let frame = ws_client.next().await.expect("frame").expect("frame data");
    match frame {
        ws::Frame::Text(bytes) => {
            let text = String::from_utf8(bytes.to_vec()).unwrap();
            assert!(text.contains("ACTIVE"));
        }
        other => panic!("unexpected frame: {other:?}"),
    }
    handle.stop(true).await;

    let hls_state = HlsState {
        quality_levels: vec![QualityLevel {
            id: Uuid::new_v4(),
            stream_id,
            name: "720p".into(),
            bitrate_kbps: 5000,
            width: 1280,
            height: 720,
            created_at: Utc::now(),
        }],
        cdn_rewriter: Some(CdnUrlRewriter::new(CdnConfig {
            enabled: true,
            base_url: "https://cdn.example.com".into(),
            token_secret: None,
            token_ttl: std::time::Duration::from_secs(60),
        })),
    };
    let app = test::init_service(
        App::new()
            .app_data(web::Data::new(hls_state))
            .service(master_playlist),
    )
    .await;
    let req = test::TestRequest::get()
        .uri(&format!("/hls/{stream_id}/master.m3u8"))
        .to_request();
    let resp = test::call_service(&app, req).await;
    let playlist =
        String::from_utf8(body::to_bytes(resp.into_body()).await.unwrap().to_vec()).unwrap();
    assert!(playlist.contains("https://cdn.example.com"));

    let store: Arc<dyn ViewerSessionStore + Send + Sync> = Arc::new(DummyStore::new());
    let session_manager = SessionManager::new(store);
    let session = session_manager
        .join_stream(stream_id, "viewer-1", Some("720p"))
        .await
        .unwrap();
    assert_eq!(
        session_manager
            .active_sessions(stream_id)
            .await
            .unwrap()
            .len(),
        1
    );
    session_manager.leave_stream(session.id).await.unwrap();
    assert!(session_manager
        .active_sessions(stream_id)
        .await
        .unwrap()
        .is_empty());
}
