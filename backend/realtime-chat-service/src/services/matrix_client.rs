use crate::config::MatrixConfig;
use crate::error::AppError;
use matrix_sdk::{
    config::SyncSettings,
    room::Room,
    ruma::{
        events::room::message::{RoomMessageEventContent, SyncRoomMessageEvent},
        OwnedRoomId, OwnedUserId, RoomId, UserId,
    },
    Client,
};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn};
use uuid::Uuid;

/// Matrix client wrapper for E2EE messaging
pub struct MatrixClient {
    client: Client,
    config: MatrixConfig,
    /// Maps conversation_id -> matrix_room_id
    room_mapping: Arc<RwLock<std::collections::HashMap<Uuid, OwnedRoomId>>>,
}

impl MatrixClient {
    /// Initialize Matrix client and login with access token
    pub async fn new(config: MatrixConfig) -> Result<Self, AppError> {
        if !config.enabled {
            return Err(AppError::Config(
                "Matrix is disabled in configuration".into(),
            ));
        }

        let _access_token = config.access_token.clone().ok_or_else(|| {
            AppError::Config("MATRIX_ACCESS_TOKEN not set but Matrix is enabled".into())
        })?;

        info!(
            "Initializing Matrix client for homeserver: {}",
            config.homeserver_url
        );

        // Build Matrix SDK client
        let client = Client::builder()
            .homeserver_url(&config.homeserver_url)
            .build()
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix client build failed: {e}")))?;

        // TODO: Matrix SDK 0.7 session restoration
        // The current Matrix SDK version (0.7) has different session APIs than newer versions
        // For now, we'll use a placeholder implementation
        // This needs to be updated to properly restore session with access token
        //
        // Correct implementation for matrix-sdk 0.7 would be:
        // client.matrix_auth().login_token(&config.access_token).send().await?;
        //
        // However, this API is not available in 0.7, and restore_session has different structure
        warn!("Matrix client session restoration not fully implemented for SDK 0.7 - client created but not authenticated");

        info!("Matrix client initialized (authentication pending SDK update)");

        Ok(Self {
            client,
            config,
            room_mapping: Arc::new(RwLock::new(std::collections::HashMap::new())),
        })
    }

    /// Get or create a Matrix room for a conversation
    pub async fn get_or_create_room(
        &self,
        conversation_id: Uuid,
        participant_user_ids: &[Uuid],
    ) -> Result<OwnedRoomId, AppError> {
        // Check cache first
        {
            let mapping = self.room_mapping.read().await;
            if let Some(room_id) = mapping.get(&conversation_id) {
                return Ok(room_id.clone());
            }
        }

        // Create new DM room
        info!(
            "Creating Matrix room for conversation {}",
            conversation_id
        );

        let invites: Vec<OwnedUserId> = participant_user_ids
            .iter()
            .filter_map(|user_id| {
                // Convert UUID to Matrix user ID format: @<uuid>:<server_name>
                let matrix_user_id = format!(
                    "@{}:{}",
                    user_id.to_string().replace("-", ""),
                    self.extract_server_name()
                );
                UserId::parse(&matrix_user_id).ok()
            })
            .collect();

        let request = matrix_sdk::ruma::api::client::room::create_room::v3::Request::new();
        let mut request = request;
        request.is_direct = true;
        request.invite = invites;
        request.name = Some(format!("Conversation {}", conversation_id));
        request.preset = Some(
            matrix_sdk::ruma::api::client::room::create_room::v3::RoomPreset::TrustedPrivateChat,
        );

        let response = self
            .client
            .send(request, None)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix room creation failed: {e}")))?;

        let room_id = response.room_id;

        // Cache mapping
        {
            let mut mapping = self.room_mapping.write().await;
            mapping.insert(conversation_id, room_id.clone());
        }

        info!(
            "Created Matrix room {} for conversation {}",
            room_id, conversation_id
        );

        Ok(room_id)
    }

    /// Send a text message to a Matrix room
    pub async fn send_message(
        &self,
        conversation_id: Uuid,
        room_id: &RoomId,
        text: &str,
    ) -> Result<String, AppError> {
        let room = self
            .client
            .get_room(room_id)
            .ok_or(AppError::NotFound)?;

        let content = RoomMessageEventContent::text_plain(text);

        let response = room
            .send(content)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix send message failed: {e}")))?;

        let event_id = response.event_id.to_string();

        info!(
            "Sent message to Matrix room {} (conversation {}): event_id={}",
            room_id, conversation_id, event_id
        );

        Ok(event_id)
    }

    /// Send media (audio, image, file) to Matrix room
    pub async fn send_media(
        &self,
        _conversation_id: Uuid,
        room_id: &RoomId,
        media_url: &str,
        media_type: &str,
        filename: &str,
    ) -> Result<String, AppError> {
        let room = self
            .client
            .get_room(room_id)
            .ok_or(AppError::NotFound)?;

        // For now, send as text with media URL
        // TODO: Implement proper Matrix media upload via /_matrix/media/v3/upload
        let content = RoomMessageEventContent::text_plain(format!(
            "[Media: {} - {}]\n{}",
            media_type, filename, media_url
        ));

        let response = room
            .send(content)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix send media failed: {e}")))?;

        Ok(response.event_id.to_string())
    }

    /// Redact (delete) a message in Matrix
    pub async fn delete_message(
        &self,
        room_id: &RoomId,
        event_id: &str,
        reason: Option<&str>,
    ) -> Result<(), AppError> {
        let room = self
            .client
            .get_room(room_id)
            .ok_or(AppError::NotFound)?;

        let event_id = matrix_sdk::ruma::EventId::parse(event_id)
            .map_err(|e| AppError::Config(format!("Invalid event_id: {e}")))?;

        room.redact(&event_id, reason, None)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix redact failed: {e}")))?;

        info!("Redacted Matrix event {} in room {}", event_id, room_id);

        Ok(())
    }

    /// Edit a message in Matrix (send replacement event)
    pub async fn edit_message(
        &self,
        room_id: &RoomId,
        original_event_id: &str,
        new_text: &str,
    ) -> Result<String, AppError> {
        let room = self
            .client
            .get_room(room_id)
            .ok_or(AppError::NotFound)?;

        let original_event_id = matrix_sdk::ruma::EventId::parse(original_event_id)
            .map_err(|e| AppError::Config(format!("Invalid event_id: {e}")))?;

        // Create replacement content (edit message)
        // Matrix SDK 0.7 uses a different API for message edits
        // TODO: Update this when upgrading Matrix SDK
        // For now, we'll send a new message with a note that it's an edit
        let content = RoomMessageEventContent::text_plain(format!(
            "[EDITED] {}",
            new_text
        ));

        let response = room
            .send(content)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix edit message failed: {e}")))?;

        info!(
            "Edited Matrix event {} in room {}: new event_id={}",
            original_event_id, room_id, response.event_id
        );

        Ok(response.event_id.to_string())
    }

    /// Start Matrix sync loop to receive events
    /// This should be spawned as a background task
    pub async fn start_sync(
        &self,
        event_handler: impl Fn(SyncRoomMessageEvent, Room) + Send + Sync + 'static,
    ) -> Result<(), AppError> {
        let event_handler = Arc::new(event_handler);

        self.client.add_event_handler({
            let handler = event_handler.clone();
            move |ev: SyncRoomMessageEvent, room: Room| {
                let handler = handler.clone();
                async move {
                    handler(ev, room);
                }
            }
        });

        info!("Starting Matrix sync loop...");

        let settings = SyncSettings::default().timeout(std::time::Duration::from_secs(30));

        self.client
            .sync(settings)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix sync failed: {e}")))?;

        Ok(())
    }

    /// Get the underlying Matrix SDK client
    pub fn inner(&self) -> &Client {
        &self.client
    }

    /// Extract server name from homeserver URL or config
    fn extract_server_name(&self) -> &str {
        // Use MATRIX_SERVICE_USER to extract server name
        // Format: @user:server.name
        self.config
            .service_user
            .split(':')
            .nth(1)
            .unwrap_or("nova.local")
    }

    /// Cache room mapping (for reloading from DB)
    pub async fn cache_room_mapping(&self, conversation_id: Uuid, room_id: OwnedRoomId) {
        let mut mapping = self.room_mapping.write().await;
        mapping.insert(conversation_id, room_id);
    }

    /// Get cached room ID for conversation
    pub async fn get_cached_room_id(&self, conversation_id: Uuid) -> Option<OwnedRoomId> {
        let mapping = self.room_mapping.read().await;
        mapping.get(&conversation_id).cloned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_extract_server_name() {
        let config = MatrixConfig {
            enabled: true,
            homeserver_url: "http://matrix-synapse:8008".to_string(),
            service_user: "@nova-service:staging.nova.internal".to_string(),
            access_token: Some("test_token".to_string()),
            device_name: "test_device".to_string(),
        };

        let client = MatrixClient {
            client: Client::builder()
                .homeserver_url("http://localhost:8008")
                .build()
                .await
                .unwrap(),
            config: config.clone(),
            room_mapping: Arc::new(RwLock::new(std::collections::HashMap::new())),
        };

        assert_eq!(client.extract_server_name(), "staging.nova.internal");
    }
}
