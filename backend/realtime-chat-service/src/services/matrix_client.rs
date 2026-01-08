use crate::config::MatrixConfig;
use crate::error::AppError;
use matrix_sdk::{
    authentication::{matrix::MatrixSession, AuthSession, SessionTokens},
    config::SyncSettings,
    room::Room,
    ruma::{
        events::{
            call::{
                answer::SyncCallAnswerEvent,
                candidates::SyncCallCandidatesEvent,
                hangup::SyncCallHangupEvent,
                invite::SyncCallInviteEvent,
            },
            AnySyncMessageLikeEvent,
            AnySyncTimelineEvent,
            room::{
                encryption::RoomEncryptionEventContent,
                encrypted::SyncRoomEncryptedEvent,
                message::{
                    ReplacementMetadata, RoomMessageEventContent, SyncRoomMessageEvent,
                },
            },
            InitialStateEvent,
        },
        serde::Raw,
        OwnedDeviceId, OwnedRoomId, OwnedUserId, RoomId, UserId,
    },
    Client, SessionMeta,
};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info};
use uuid::Uuid;

/// Matrix client wrapper for E2EE messaging
///
/// This client supports end-to-end encryption (E2EE) using Matrix's Olm/Megolm protocols.
/// The Matrix SDK automatically handles:
/// - Olm one-to-one key exchange for device-to-device communication
/// - Megolm group session keys for encrypted rooms
/// - Automatic encryption of messages when sent to encrypted rooms
/// - Key rotation and ratcheting
///
/// ## Crypto Store Persistence
///
/// **Current Status**: In-memory crypto store (keys lost on restart)
///
/// **Why not SQLite?** Matrix SDK 0.16 requires `libsqlite3-sys 0.35`, which conflicts
/// with `sqlx 0.8`'s dependency on `libsqlite3-sys 0.28`. Using memory-only store avoids
/// this version conflict.
///
/// **Acceptable for Nova because:**
/// 1. Nova has its own application-layer E2EE using vodozemac Olm/Megolm
/// 2. Matrix integration is for external user interoperability, not primary E2EE
/// 3. Matrix's server-side key backup can recover session keys after restart
///
/// ## Future Improvements (if needed)
///
/// To add PostgreSQL persistence, implement `matrix_sdk_crypto::store::CryptoStore` trait:
/// 1. Create `matrix_crypto_state` table for pickled account/sessions
/// 2. Implement 50+ trait methods for session, identity, and backup management
/// 3. Use `store_config.crypto_store()` to inject custom implementation
///
/// Alternatively, wait for `matrix-sdk-sql` to support SDK 0.16 with PostgreSQL.
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

        let access_token = config.access_token.clone().ok_or_else(|| {
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

        // Restore session using Matrix SDK 0.16 API
        // Parse service user ID from config (format: @user:server.name)
        let user_id = OwnedUserId::try_from(config.service_user.as_str())
            .map_err(|e| AppError::Config(format!("Invalid MATRIX_SERVICE_USER format: {e}")))?;

        let device_id = OwnedDeviceId::from(config.device_name.as_str());

        // Create MatrixSession for restoration
        let matrix_session = MatrixSession {
            meta: SessionMeta {
                user_id: user_id.clone(),
                device_id: device_id.clone(),
            },
            tokens: SessionTokens {
                access_token: access_token.clone(),
                refresh_token: None,
            },
        };

        // Convert to AuthSession and restore
        let auth_session = AuthSession::Matrix(matrix_session);

        client
            .restore_session(auth_session)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix session restoration failed: {e}")))?;

        info!(
            "Matrix client authenticated successfully for user: {} (device: {})",
            user_id, device_id
        );

        Ok(Self {
            client,
            config,
            room_mapping: Arc::new(RwLock::new(std::collections::HashMap::new())),
        })
    }

    /// Get or create a Matrix room for a conversation
    ///
    /// Creates encrypted rooms by default using Megolm (m.megolm.v1.aes-sha2).
    /// Once encryption is enabled on a room, it cannot be disabled.
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

        // Create new DM room with E2EE enabled
        info!(
            "Creating encrypted Matrix room for conversation {}",
            conversation_id
        );

        let invites: Vec<OwnedUserId> = participant_user_ids
            .iter()
            .filter_map(|user_id| {
                // Convert UUID to Matrix user ID format: @nova-<uuid>:<server_name>
                let matrix_user_id = format!(
                    "@nova-{}:{}",
                    user_id,
                    self.extract_server_name()
                );
                UserId::parse(&matrix_user_id).ok()
            })
            .collect();

        let request = matrix_sdk::ruma::api::client::room::create_room::v3::Request::new();
        let mut request = request;
        request.is_direct = true;
        request.invite = invites;
        // Don't set room name for DMs - Matrix clients will display the other user's name automatically
        // Setting a name would override this and show "Conversation {uuid}" instead
        request.name = None;
        request.preset = Some(
            matrix_sdk::ruma::api::client::room::create_room::v3::RoomPreset::TrustedPrivateChat,
        );

        // Enable E2EE encryption with recommended defaults (Megolm)
        // This sets m.room.encryption state event with algorithm: m.megolm.v1.aes-sha2
        // Use with_empty_state_key for encryption state event (state_key is empty string)
        request.initial_state = vec![
            InitialStateEvent::with_empty_state_key(
                RoomEncryptionEventContent::with_recommended_defaults()
            ).to_raw_any(),
        ];

        let response = self
            .client
            .send(request)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix room creation failed: {e}")))?;

        let room_id = response.room_id;

        // Cache mapping
        {
            let mut mapping = self.room_mapping.write().await;
            mapping.insert(conversation_id, room_id.clone());
        }

        info!(
            "Created encrypted Matrix room {} for conversation {}",
            room_id, conversation_id
        );

        Ok(room_id)
    }

    /// Send a text message to a Matrix room
    ///
    /// Messages are automatically encrypted by the Matrix SDK if the room has encryption enabled.
    /// The SDK handles Megolm session keys, key rotation, and device verification transparently.
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

        // Check if room is encrypted and log appropriately
        // Use encryption_state() which is synchronous and infallible
        let encryption_state = room.encryption_state();
        let is_encrypted = encryption_state.is_encrypted();

        if is_encrypted {
            info!(
                "Sending encrypted message to room {} (conversation {})",
                room_id, conversation_id
            );
        } else {
            info!(
                "Sending plaintext message to room {} (conversation {})",
                room_id, conversation_id
            );
        }

        let content = RoomMessageEventContent::text_plain(text);

        // The Matrix SDK automatically encrypts the message if the room is encrypted
        let response = room
            .send(content)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix send message failed: {e}")))?;

        let event_id = response.event_id.to_string();

        info!(
            "Sent message to Matrix room {} (conversation {}): encrypted={}, event_id={}",
            room_id, conversation_id, is_encrypted, event_id
        );

        Ok(event_id)
    }

    /// Upload media from external URL to Matrix and send as proper media message
    ///
    /// This function implements the full Matrix media upload flow:
    /// 1. Fetches media bytes from the external URL (S3)
    /// 2. Uploads to Matrix media server via /_matrix/media/v3/upload
    /// 3. Sends as proper typed media message (Audio/Image/Video/File)
    ///
    /// This enables:
    /// - Native Matrix media rendering in clients
    /// - Matrix media server caching and CDN delivery
    /// - Proper thumbnail generation
    /// - Better E2EE integration (encrypted media uploads in encrypted rooms)
    /// - Media preview in notifications
    ///
    /// # Arguments
    /// * `room_id` - Matrix room to send to
    /// * `media_url` - External URL to fetch media from
    /// * `media_type` - MIME type (e.g., "audio/mpeg", "image/png")
    /// * `filename` - Original filename
    ///
    /// # Returns
    /// Matrix event ID of the sent message
    pub async fn upload_and_send_media(
        &self,
        room_id: &RoomId,
        media_url: &str,
        media_type: &str,
        filename: &str,
    ) -> Result<String, AppError> {
        use matrix_sdk::ruma::events::room::message::{
            AudioMessageEventContent, FileMessageEventContent, ImageMessageEventContent,
            MessageType, VideoMessageEventContent,
        };

        // 1. Fetch media from external URL
        let response = reqwest::get(media_url)
            .await
            .map_err(|e| AppError::StartServer(format!("Failed to fetch media: {e}")))?;

        let bytes = response
            .bytes()
            .await
            .map_err(|e| AppError::StartServer(format!("Failed to read media bytes: {e}")))?;

        // 2. Parse MIME type
        let mime: mime::Mime = media_type
            .parse()
            .map_err(|e| AppError::Config(format!("Invalid MIME type: {e}")))?;

        // 3. Upload to Matrix media server
        let upload_response = self
            .client
            .media()
            .upload(&mime, bytes.to_vec(), None)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix media upload failed: {e}")))?;

        let mxc_uri = upload_response.content_uri.clone();

        // 4. Create appropriate message type
        let message_type = if media_type.starts_with("audio/") {
            MessageType::Audio(AudioMessageEventContent::plain(
                filename.to_string(),
                mxc_uri,
            ))
        } else if media_type.starts_with("image/") {
            MessageType::Image(ImageMessageEventContent::plain(
                filename.to_string(),
                mxc_uri,
            ))
        } else if media_type.starts_with("video/") {
            MessageType::Video(VideoMessageEventContent::plain(
                filename.to_string(),
                mxc_uri,
            ))
        } else {
            MessageType::File(FileMessageEventContent::plain(filename.to_string(), mxc_uri))
        };

        // 5. Send message
        let room = self
            .client
            .get_room(room_id)
            .ok_or(AppError::NotFound)?;
        let content = RoomMessageEventContent::new(message_type);
        let response = room
            .send(content)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix send media failed: {e}")))?;

        info!(
            "Uploaded and sent media to Matrix: room={}, mxc={}, event_id={}",
            room_id, upload_response.content_uri, response.event_id
        );

        Ok(response.event_id.to_string())
    }

    /// Send media (audio, image, video, file) to a Matrix room
    ///
    /// # Arguments
    /// * `conversation_id` - The conversation UUID
    /// * `room_id` - The Matrix room ID
    /// * `media_url` - External URL to the media (e.g., S3 URL)
    /// * `media_type` - MIME type of the media (e.g., "audio/mpeg", "image/png", "video/mp4")
    /// * `filename` - Original filename of the media
    /// * `upload_to_matrix` - If true, uploads media to Matrix server; if false, sends as text with URL
    ///
    /// # Returns
    /// The Matrix event ID of the sent message
    ///
    /// # Implementation
    /// When `upload_to_matrix` is true:
    /// - Fetches media from external URL
    /// - Uploads to Matrix media server
    /// - Sends as proper typed media message with MXC URI
    /// - Enables native rendering, E2EE integration, and thumbnails
    ///
    /// When `upload_to_matrix` is false:
    /// - Sends as formatted text message with external URL
    /// - Useful for large files or when external hosting is preferred
    pub async fn send_media(
        &self,
        conversation_id: Uuid,
        room_id: &RoomId,
        media_url: &str,
        media_type: &str,
        filename: &str,
        upload_to_matrix: bool,
    ) -> Result<String, AppError> {
        // If upload_to_matrix is true, use the new upload function
        if upload_to_matrix {
            return self
                .upload_and_send_media(room_id, media_url, media_type, filename)
                .await;
        }

        // Fallback: send as text with URL
        let room = self
            .client
            .get_room(room_id)
            .ok_or(AppError::NotFound)?;

        // Determine media category for user-friendly display
        let media_category = if media_type.starts_with("audio/") {
            "Audio"
        } else if media_type.starts_with("image/") {
            "Image"
        } else if media_type.starts_with("video/") {
            "Video"
        } else {
            "File"
        };

        // Create formatted message with external media URL
        // This is displayed properly in Matrix clients with clickable links
        let message_text = format!(
            "{}: {}\n{}",
            media_category, filename, media_url
        );

        let content = RoomMessageEventContent::text_plain(&message_text);

        let response = room
            .send(content)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix send media failed: {e}")))?;

        info!(
            "Sent media reference to Matrix room {} (conversation {}): type={}, filename={}, event_id={}",
            room_id, conversation_id, media_type, filename, response.event_id
        );

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

        // Create proper Matrix replacement event using the SDK's make_replacement method
        // This automatically sets the correct m.relates_to field and formats the body with "* " prefix
        let new_content = RoomMessageEventContent::text_plain(new_text);
        let metadata = ReplacementMetadata::new(original_event_id.to_owned(), None);
        let edit_content = new_content.make_replacement(metadata);

        let response = room
            .send(edit_content)
            .await
            .map_err(|e| AppError::StartServer(format!("Matrix edit message failed: {e}")))?;

        info!(
            "Sent replacement event for Matrix event {} in room {}: new event_id={}",
            original_event_id, room_id, response.event_id
        );

        Ok(response.event_id.to_string())
    }

    /// Start Matrix sync loop to receive events
    /// This should be spawned as a background task
    pub async fn start_sync(
        &self,
        message_handler: impl Fn(SyncRoomMessageEvent, Room) + Send + Sync + 'static,
        encrypted_handler: impl Fn(SyncRoomEncryptedEvent, Room) + Send + Sync + 'static,
    ) -> Result<(), AppError> {
        let message_handler = Arc::new(message_handler);
        let encrypted_handler = Arc::new(encrypted_handler);

        self.client.add_event_handler({
            let handler = message_handler.clone();
            move |ev: SyncRoomMessageEvent, room: Room| {
                let handler = handler.clone();
                async move {
                    handler(ev, room);
                }
            }
        });

        // Some SDK paths may only surface encrypted timeline events as raw timeline events (before / without
        // decryption). Register a raw handler as a fallback so we can still persist metadata-only rows.
        self.client.add_event_handler({
            let handler = encrypted_handler.clone();
            move |raw: Raw<AnySyncTimelineEvent>, room: Room| {
                let handler = handler.clone();
                async move {
                    match raw.get_field::<String>("type") {
                        Ok(Some(t)) if t == "m.room.encrypted" => match raw.deserialize() {
                            Ok(AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomEncrypted(ev))) => {
                                handler(ev, room)
                            }
                            Ok(_) => {}
                            Err(e) => {
                                error!(error = %e, "Failed to deserialize raw m.room.encrypted event");
                            }
                        },
                        Ok(_) => {}
                        Err(e) => {
                            error!(error = %e, "Failed to read raw event type");
                        }
                    }
                }
            }
        });

        self.client.add_event_handler({
            let handler = encrypted_handler.clone();
            move |ev: SyncRoomEncryptedEvent, room: Room| {
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

    /// Register VoIP event handler for Matrix sync loop
    ///
    /// Registers typed event handlers for Matrix VoIP call events using Matrix SDK 0.16 API.
    /// The handler will process:
    /// - m.call.invite - Incoming call invitations with SDP offer
    /// - m.call.answer - Call answers with SDP answer
    /// - m.call.candidates - ICE candidates for WebRTC connection establishment
    /// - m.call.hangup - Call termination signals
    ///
    /// Each event type is registered with a dedicated handler that forwards the event
    /// to the `MatrixVoipEventHandler` for processing.
    ///
    /// # Arguments
    /// * `voip_handler` - Handler for VoIP events that processes call signaling
    pub fn register_voip_handler(
        &self,
        voip_handler: Arc<crate::handlers::MatrixVoipEventHandler>,
    ) {
        info!("Registering Matrix VoIP event handlers for SDK 0.16");

        // Register handler for m.call.invite events
        self.client.add_event_handler({
            let handler = voip_handler.clone();
            move |ev: SyncCallInviteEvent, room: Room| {
                let handler = handler.clone();
                async move {
                    if let Err(e) = handler.handle_call_invite(ev, room).await {
                        error!(error = ?e, "Failed to handle m.call.invite event");
                    }
                }
            }
        });

        // Register handler for m.call.answer events
        self.client.add_event_handler({
            let handler = voip_handler.clone();
            move |ev: SyncCallAnswerEvent, room: Room| {
                let handler = handler.clone();
                async move {
                    if let Err(e) = handler.handle_call_answer(ev, room).await {
                        error!(error = ?e, "Failed to handle m.call.answer event");
                    }
                }
            }
        });

        // Register handler for m.call.candidates events
        self.client.add_event_handler({
            let handler = voip_handler.clone();
            move |ev: SyncCallCandidatesEvent, room: Room| {
                let handler = handler.clone();
                async move {
                    if let Err(e) = handler.handle_call_candidates(ev, room).await {
                        error!(error = ?e, "Failed to handle m.call.candidates event");
                    }
                }
            }
        });

        // Register handler for m.call.hangup events
        self.client.add_event_handler({
            let handler = voip_handler.clone();
            move |ev: SyncCallHangupEvent, room: Room| {
                let handler = handler.clone();
                async move {
                    if let Err(e) = handler.handle_call_hangup(ev, room).await {
                        error!(error = ?e, "Failed to handle m.call.hangup event");
                    }
                }
            }
        });

        info!("Successfully registered VoIP event handlers (invite, answer, candidates, hangup)");
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

    /// Check if a room has encryption enabled
    ///
    /// Returns true if the room has the m.room.encryption state event set.
    /// Once enabled, encryption cannot be disabled for a room.
    pub async fn is_room_encrypted(&self, room_id: &RoomId) -> bool {
        if let Some(room) = self.client.get_room(room_id) {
            room.latest_encryption_state().await.map(|s| s.is_encrypted()).unwrap_or(false)
        } else {
            false
        }
    }

    /// Enable encryption on an existing room
    ///
    /// This sends an m.room.encryption state event to the room with Megolm algorithm.
    /// Once enabled, encryption cannot be disabled.
    ///
    /// # Arguments
    /// * `room_id` - The Matrix room ID to enable encryption for
    ///
    /// # Returns
    /// Ok(()) if encryption was enabled or was already enabled, Err otherwise
    ///
    /// # Note
    /// This is idempotent - calling it on an already-encrypted room is safe and will
    /// return Ok without sending a duplicate state event.
    pub async fn enable_room_encryption(&self, room_id: &RoomId) -> Result<(), AppError> {
        let room = self.client.get_room(room_id).ok_or(AppError::NotFound)?;

        // Check if already encrypted
        if room.latest_encryption_state().await.map(|s| s.is_encrypted()).unwrap_or(false) {
            info!("Room {} is already encrypted", room_id);
            return Ok(());
        }

        // Enable encryption with recommended defaults (Megolm: m.megolm.v1.aes-sha2)
        let content = RoomEncryptionEventContent::with_recommended_defaults();
        room.send_state_event(content)
            .await
            .map_err(|e| AppError::StartServer(format!("Failed to enable encryption: {e}")))?;

        info!("Enabled E2EE encryption for room {}", room_id);
        Ok(())
    }

    /// Get the client's own device keys for verification
    ///
    /// Returns the Ed25519 public key fingerprint of this device in base64 format.
    /// This key can be used for out-of-band verification to establish trust between devices.
    ///
    /// # Returns
    /// Some(fingerprint) if the device has encryption keys, None otherwise
    ///
    /// # Use Cases
    /// - Display QR code for device verification
    /// - Show fingerprint in UI for manual verification
    /// - Implement emoji verification flows
    pub async fn get_own_device_keys(&self) -> Option<String> {
        let user_id = self.client.user_id()?;
        let device_id = self.client.device_id()?;

        // Return device fingerprint for out-of-band verification
        if let Some(device) = self.client
            .encryption()
            .get_device(user_id, device_id)
            .await
            .ok()
            .flatten()
        {
            Some(device.ed25519_key().map(|k| k.to_base64()).unwrap_or_default())
        } else {
            None
        }
    }

    /// Enable server-side key backup for E2EE session recovery
    ///
    /// Server-side key backup allows recovery of Megolm session keys after service restart.
    /// This is the Matrix standard way to persist encryption keys without local storage.
    ///
    /// # How it works
    /// 1. Creates or retrieves existing backup version from homeserver
    /// 2. Encrypts session keys with a recovery key before upload
    /// 3. Homeserver stores encrypted keys (cannot decrypt them)
    /// 4. After restart, keys can be downloaded and decrypted with recovery key
    ///
    /// # Returns
    /// Ok(recovery_key) - Base58-encoded recovery key to store securely
    /// Err if backup creation fails
    ///
    /// # Important
    /// Store the recovery key in a secure location (e.g., environment variable,
    /// secrets manager). Without it, backed-up keys cannot be recovered.
    pub async fn enable_key_backup(&self) -> Result<String, AppError> {
        use matrix_sdk::encryption::recovery::RecoveryState;

        let encryption = self.client.encryption();
        let recovery = encryption.recovery();

        // Check current recovery state
        let state = recovery.state();
        match state {
            RecoveryState::Enabled => {
                info!("Matrix key backup already enabled");
                return Ok(String::new());
            }
            RecoveryState::Incomplete => {
                info!("Matrix key backup incomplete, re-enabling...");
            }
            RecoveryState::Disabled | RecoveryState::Unknown => {
                info!("Enabling Matrix key backup...");
            }
        }

        // Enable recovery with a new key
        // This creates secret storage and backup automatically
        let enable_result = recovery.enable().await
            .map_err(|e| AppError::StartServer(format!("Failed to enable key backup: {e}")))?;

        info!("Matrix key backup enabled successfully");

        Ok(enable_result)
    }

    /// Recover encryption keys from server-side backup
    ///
    /// Call this after service restart to restore Megolm session keys.
    /// The recovery key must match the one returned by `enable_key_backup()`.
    ///
    /// # Arguments
    /// * `recovery_key` - Base58-encoded recovery key from initial backup setup
    ///
    /// # Returns
    /// Ok(()) if recovery succeeded, Err otherwise
    pub async fn recover_keys(&self, recovery_key: &str) -> Result<(), AppError> {
        let encryption = self.client.encryption();
        let recovery = encryption.recovery();

        // Recover using the provided key
        recovery.recover(recovery_key).await
            .map_err(|e| AppError::StartServer(format!("Failed to recover keys: {e}")))?;

        info!("Matrix encryption keys recovered from backup");
        Ok(())
    }

    /// Check if key backup is enabled and working
    pub fn is_key_backup_enabled(&self) -> bool {
        use matrix_sdk::encryption::recovery::RecoveryState;
        matches!(self.client.encryption().recovery().state(), RecoveryState::Enabled)
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
            public_url: None,
            service_user: "@nova-service:staging.nova.internal".to_string(),
            access_token: Some("test_token".to_string()),
            device_name: "test_device".to_string(),
            recovery_key: None,
            admin_token: None,
            admin_username: None,
            admin_password: None,
            server_name: "staging.nova.internal".to_string(),
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
