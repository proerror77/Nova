use chrono::Utc;
use sqlx::{Pool, Postgres, Row};
use uuid::Uuid;

pub struct CallService;

/// Call status enum
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "varchar")]
pub enum CallStatus {
    #[sqlx(rename = "ringing")]
    Ringing,
    #[sqlx(rename = "connected")]
    Connected,
    #[sqlx(rename = "ended")]
    Ended,
    #[sqlx(rename = "failed")]
    Failed,
}

impl CallStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Ringing => "ringing",
            Self::Connected => "connected",
            Self::Ended => "ended",
            Self::Failed => "failed",
        }
    }
}

/// WebRTC connection state enum
#[derive(Debug, Clone, Copy, PartialEq, Eq, sqlx::Type)]
#[sqlx(type_name = "varchar")]
pub enum ConnectionState {
    #[sqlx(rename = "new")]
    New,
    #[sqlx(rename = "connecting")]
    Connecting,
    #[sqlx(rename = "connected")]
    Connected,
    #[sqlx(rename = "disconnected")]
    Disconnected,
    #[sqlx(rename = "failed")]
    Failed,
    #[sqlx(rename = "closed")]
    Closed,
}

impl ConnectionState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::New => "new",
            Self::Connecting => "connecting",
            Self::Connected => "connected",
            Self::Disconnected => "disconnected",
            Self::Failed => "failed",
            Self::Closed => "closed",
        }
    }
}

impl CallService {
    /// Initiate a new video call (1:1 or group)
    ///
    /// Creates a new call session and adds the initiator as the first participant.
    /// The call starts in "ringing" status until other participants join.
    pub async fn initiate_call(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
        initiator_id: Uuid,
        initiator_sdp: &str,
        call_type: &str,
        max_participants: i32,
    ) -> Result<Uuid, crate::error::AppError> {
        let call_id = Uuid::new_v4();

        // Start transaction
        let mut tx = db
            .begin()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx begin: {e}")))?;

        // Insert call session
        sqlx::query(
            "INSERT INTO call_sessions (id, conversation_id, initiator_id, status, initiator_sdp, max_participants, call_type) \
             VALUES ($1, $2, $3, 'ringing', $4, $5, $6)"
        )
        .bind(call_id)
        .bind(conversation_id)
        .bind(initiator_id)
        .bind(initiator_sdp)
        .bind(max_participants)
        .bind(call_type)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert call: {e}")))?;

        // Add initiator as participant
        let participant_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO call_participants (id, call_id, user_id, connection_state) \
             VALUES ($1, $2, $3, 'new')",
        )
        .bind(participant_id)
        .bind(call_id)
        .bind(initiator_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert participant: {e}")))?;

        tx.commit()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx commit: {e}")))?;

        Ok(call_id)
    }

    /// Answer an incoming call
    ///
    /// Adds the answering participant to the call and transitions to "connected" state.
    pub async fn answer_call(
        db: &Pool<Postgres>,
        call_id: Uuid,
        answerer_id: Uuid,
        answer_sdp: &str,
    ) -> Result<Uuid, crate::error::AppError> {
        // Verify call exists and is in ringing state
        let call_row = sqlx::query("SELECT id, status FROM call_sessions WHERE id = $1")
            .bind(call_id)
            .fetch_optional(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("fetch call: {e}")))?;

        let call_row =
            call_row.ok_or_else(|| crate::error::AppError::Config("Call not found".into()))?;

        let status: String = call_row.get("status");
        if status != "ringing" {
            return Err(crate::error::AppError::Config(
                "Call is not in ringing state".into(),
            ));
        }

        // Start transaction
        let mut tx = db
            .begin()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx begin: {e}")))?;

        // Add answerer as participant
        let participant_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO call_participants (id, call_id, user_id, answer_sdp, connection_state) \
             VALUES ($1, $2, $3, $4, 'new')",
        )
        .bind(participant_id)
        .bind(call_id)
        .bind(answerer_id)
        .bind(answer_sdp)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert answerer: {e}")))?;

        // Update call status to connected
        sqlx::query("UPDATE call_sessions SET status = 'connected', started_at = CURRENT_TIMESTAMP WHERE id = $1")
            .bind(call_id)
            .execute(&mut *tx)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("update call: {e}")))?;

        tx.commit()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx commit: {e}")))?;

        Ok(participant_id)
    }

    /// End a call
    ///
    /// Marks the call as ended and records the duration.
    pub async fn end_call(
        db: &Pool<Postgres>,
        call_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        // Get call start time
        let call_row = sqlx::query("SELECT started_at FROM call_sessions WHERE id = $1")
            .bind(call_id)
            .fetch_optional(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("fetch call: {e}")))?;

        let call_row =
            call_row.ok_or_else(|| crate::error::AppError::Config("Call not found".into()))?;

        let started_at: Option<chrono::DateTime<chrono::Utc>> = call_row.get("started_at");

        // Calculate duration
        let duration_ms = started_at.map(|start| {
            let now = Utc::now();
            (now.timestamp_millis() - start.timestamp_millis()) as i32
        });

        // Update call status
        sqlx::query(
            "UPDATE call_sessions SET status = 'ended', ended_at = CURRENT_TIMESTAMP, duration_ms = $2 WHERE id = $1"
        )
        .bind(call_id)
        .bind(duration_ms)
        .execute(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("update call: {e}")))?;

        // Mark all participants as left
        sqlx::query("UPDATE call_participants SET left_at = CURRENT_TIMESTAMP WHERE call_id = $1 AND left_at IS NULL")
            .bind(call_id)
            .execute(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("update participants: {e}")))?;

        Ok(())
    }

    /// Reject/decline an incoming call
    ///
    /// Marks the call as failed without accepting it.
    pub async fn reject_call(
        db: &Pool<Postgres>,
        call_id: Uuid,
    ) -> Result<(), crate::error::AppError> {
        sqlx::query("UPDATE call_sessions SET status = 'failed', ended_at = CURRENT_TIMESTAMP WHERE id = $1")
            .bind(call_id)
            .execute(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("update call: {e}")))?;

        Ok(())
    }

    /// Update participant connection state
    ///
    /// Tracks WebRTC connection state transitions for debugging and monitoring.
    pub async fn update_participant_state(
        db: &Pool<Postgres>,
        participant_id: Uuid,
        connection_state: &str,
    ) -> Result<(), crate::error::AppError> {
        sqlx::query(
            "UPDATE call_participants SET connection_state = $2, last_ice_candidate_timestamp = CURRENT_TIMESTAMP WHERE id = $1"
        )
        .bind(participant_id)
        .bind(connection_state)
        .execute(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("update participant: {e}")))?;

        Ok(())
    }

    /// Get active calls in a conversation
    ///
    /// Returns all calls that are currently ringing or connected.
    pub async fn get_active_calls(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
    ) -> Result<Vec<(Uuid, String)>, crate::error::AppError> {
        let rows = sqlx::query(
            "SELECT id, status FROM call_sessions \
             WHERE conversation_id = $1 AND status IN ('ringing', 'connected') AND deleted_at IS NULL"
        )
        .bind(conversation_id)
        .fetch_all(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch calls: {e}")))?;

        Ok(rows
            .into_iter()
            .map(|r| (r.get("id"), r.get("status")))
            .collect())
    }

    /// Get call participants with their SDP data
    ///
    /// Returns all participants in a call including their SDP offers/answers.
    pub async fn get_call_participants(
        db: &Pool<Postgres>,
        call_id: Uuid,
    ) -> Result<Vec<(Uuid, Uuid, Option<String>)>, crate::error::AppError> {
        let rows = sqlx::query(
            "SELECT id, user_id, answer_sdp FROM call_participants WHERE call_id = $1 ORDER BY joined_at ASC"
        )
        .bind(call_id)
        .fetch_all(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch participants: {e}")))?;

        Ok(rows
            .into_iter()
            .map(|r| (r.get("id"), r.get("user_id"), r.get("answer_sdp")))
            .collect())
    }

    /// Get initiator's SDP offer
    ///
    /// Used by answering participant to get the original offer.
    pub async fn get_initiator_sdp(
        db: &Pool<Postgres>,
        call_id: Uuid,
    ) -> Result<String, crate::error::AppError> {
        let row = sqlx::query("SELECT initiator_sdp FROM call_sessions WHERE id = $1")
            .bind(call_id)
            .fetch_optional(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("fetch call: {e}")))?;

        let row = row.ok_or_else(|| crate::error::AppError::Config("Call not found".into()))?;

        let sdp: Option<String> = row.get("initiator_sdp");
        sdp.ok_or_else(|| crate::error::AppError::Config("SDP not available".into()))
    }

    /// Join a group call (or answer a 1:1 call)
    ///
    /// Adds a participant to an active call and returns all existing participants with their SDPs.
    /// For P2P mesh architecture, new participants need SDP from all existing participants.
    pub async fn join_call(
        db: &Pool<Postgres>,
        call_id: Uuid,
        user_id: Uuid,
        sdp: &str,
        max_participants: i32,
    ) -> Result<(Uuid, Vec<crate::routes::calls::ParticipantSdpInfo>), crate::error::AppError> {
        // Start transaction
        let mut tx = db
            .begin()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx begin: {e}")))?;

        // Check if user is already in the call
        let existing = sqlx::query(
            "SELECT id FROM call_participants WHERE call_id = $1 AND user_id = $2 AND left_at IS NULL"
        )
        .bind(call_id)
        .bind(user_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("check participant: {e}")))?;

        if existing.is_some() {
            return Err(crate::error::AppError::Config(
                "User is already in the call".into(),
            ));
        }

        // Check participant count
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM call_participants WHERE call_id = $1 AND left_at IS NULL",
        )
        .bind(call_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("count participants: {e}")))?;

        if count >= max_participants as i64 {
            return Err(crate::error::AppError::Config(
                "Call is full (max participants reached)".into(),
            ));
        }

        // Get all existing participants with SDPs
        let rows = sqlx::query(
            "SELECT cp.id, cp.user_id, cp.answer_sdp, cp.joined_at, cp.connection_state, cs.initiator_id, cs.initiator_sdp \
             FROM call_participants cp \
             JOIN call_sessions cs ON cp.call_id = cs.id \
             WHERE cp.call_id = $1 AND cp.left_at IS NULL \
             ORDER BY cp.joined_at ASC"
        )
        .bind(call_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch participants: {e}")))?;

        let mut existing_participants = Vec::new();
        for row in rows {
            let participant_id: Uuid = row.get("id");
            let participant_user_id: Uuid = row.get("user_id");
            let answer_sdp: Option<String> = row.get("answer_sdp");
            let joined_at: chrono::DateTime<Utc> = row.get("joined_at");
            let connection_state: String = row.get("connection_state");
            let initiator_id: Uuid = row.get("initiator_id");
            let initiator_sdp: Option<String> = row.get("initiator_sdp");

            // Use initiator_sdp for the initiator, answer_sdp for others
            let sdp = if participant_user_id == initiator_id {
                initiator_sdp.unwrap_or_default()
            } else {
                answer_sdp.unwrap_or_default()
            };

            if !sdp.is_empty() {
                existing_participants.push(crate::routes::calls::ParticipantSdpInfo {
                    participant_id,
                    user_id: participant_user_id,
                    sdp,
                    joined_at: joined_at.to_rfc3339(),
                    connection_state,
                });
            }
        }

        // Add new participant
        let participant_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO call_participants (id, call_id, user_id, answer_sdp, connection_state) \
             VALUES ($1, $2, $3, $4, 'new')",
        )
        .bind(participant_id)
        .bind(call_id)
        .bind(user_id)
        .bind(sdp)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert participant: {e}")))?;

        // Update call status to connected if it was ringing
        sqlx::query(
            "UPDATE call_sessions SET status = 'connected', started_at = COALESCE(started_at, CURRENT_TIMESTAMP) \
             WHERE id = $1 AND status = 'ringing'"
        )
        .bind(call_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("update call: {e}")))?;

        tx.commit()
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("tx commit: {e}")))?;

        Ok((participant_id, existing_participants))
    }

    /// Leave a group call
    ///
    /// Marks the participant as left by setting left_at timestamp.
    pub async fn leave_call(
        db: &Pool<Postgres>,
        call_id: Uuid,
        user_id: Uuid,
    ) -> Result<Uuid, crate::error::AppError> {
        // Find the participant
        let row = sqlx::query(
            "SELECT id FROM call_participants WHERE call_id = $1 AND user_id = $2 AND left_at IS NULL"
        )
        .bind(call_id)
        .bind(user_id)
        .fetch_optional(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch participant: {e}")))?;

        let participant_id: Uuid = row
            .ok_or_else(|| crate::error::AppError::Config("User is not in the call".into()))?
            .get("id");

        // Mark as left
        sqlx::query("UPDATE call_participants SET left_at = CURRENT_TIMESTAMP WHERE id = $1")
            .bind(participant_id)
            .execute(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("update participant: {e}")))?;

        Ok(participant_id)
    }

    /// Get all participants of a call
    ///
    /// Returns participant information including their join/leave times and connection state.
    pub async fn get_participants(
        db: &Pool<Postgres>,
        call_id: Uuid,
    ) -> Result<Vec<crate::routes::calls::ParticipantInfo>, crate::error::AppError> {
        let rows = sqlx::query(
            "SELECT id, user_id, joined_at, left_at, connection_state, has_audio, has_video \
             FROM call_participants \
             WHERE call_id = $1 \
             ORDER BY joined_at ASC",
        )
        .bind(call_id)
        .fetch_all(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch participants: {e}")))?;

        Ok(rows
            .into_iter()
            .map(|r| crate::routes::calls::ParticipantInfo {
                id: r.get("id"),
                user_id: r.get("user_id"),
                joined_at: r.get::<chrono::DateTime<Utc>, _>("joined_at").to_rfc3339(),
                left_at: r
                    .get::<Option<chrono::DateTime<Utc>>, _>("left_at")
                    .map(|dt| dt.to_rfc3339()),
                connection_state: r.get("connection_state"),
                has_audio: r.get("has_audio"),
                has_video: r.get("has_video"),
            })
            .collect())
    }

    /// Get call history for a user
    ///
    /// Returns all calls a user participated in with duration and participants.
    pub async fn get_call_history(
        db: &Pool<Postgres>,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<(Uuid, String, i32, i64)>, crate::error::AppError> {
        let rows = sqlx::query(
            "SELECT cs.id, cs.status, COALESCE(cs.duration_ms, 0), COUNT(cp.id) as participant_count \
             FROM call_sessions cs \
             JOIN call_participants cp ON cs.id = cp.call_id \
             WHERE cp.user_id = $1 AND cs.deleted_at IS NULL \
             GROUP BY cs.id, cs.status, cs.duration_ms \
             ORDER BY cs.created_at DESC \
             LIMIT $2 OFFSET $3"
        )
        .bind(user_id)
        .bind(limit.min(100)) // Cap at 100
        .bind(offset)
        .fetch_all(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch history: {e}")))?;

        Ok(rows
            .into_iter()
            .map(|r| {
                (
                    r.get::<Uuid, _>("id"),
                    r.get::<String, _>("status"),
                    r.get::<i32, _>("duration_ms"),
                    r.get::<i64, _>("participant_count"),
                )
            })
            .collect())
    }

    // ==================== Matrix VoIP Integration Methods ====================
    // These methods provide optional Matrix E2EE VoIP signaling alongside WebSocket.
    // See CALL_SERVICE_MATRIX_INTEGRATION.md for architecture details.

    /// Initiate a new video call with Matrix VoIP signaling
    ///
    /// This is the Matrix-integrated version of `initiate_call()`.
    /// It performs dual-write: creates call in Nova DB and sends m.call.invite to Matrix.
    ///
    /// # Arguments
    /// * `db` - Database connection pool
    /// * `matrix_voip_service` - Matrix VoIP service for sending events
    /// * `matrix_client` - Matrix client for room lookups
    /// * `conversation_id` - Nova conversation UUID
    /// * `initiator_id` - User ID of call initiator
    /// * `initiator_sdp` - WebRTC SDP offer from initiator
    /// * `call_type` - "video" or "audio"
    /// * `max_participants` - Maximum allowed participants
    ///
    /// # Returns
    /// Call session UUID
    ///
    /// # Errors
    /// - Database operation fails
    /// - Matrix room not found for conversation
    /// - Matrix event sending fails (logged as warning, not returned as error)
    pub async fn initiate_call_with_matrix(
        db: &Pool<Postgres>,
        matrix_voip_service: &crate::services::matrix_voip_service::MatrixVoipService,
        matrix_client: &crate::services::matrix_client::MatrixClient,
        conversation_id: Uuid,
        initiator_id: Uuid,
        initiator_sdp: &str,
        call_type: &str,
        max_participants: i32,
    ) -> Result<Uuid, crate::error::AppError> {
        use tracing::{info, warn};

        // Step 1: Create call in Nova database
        let call_id = Self::initiate_call(
            db,
            conversation_id,
            initiator_id,
            initiator_sdp,
            call_type,
            max_participants,
        )
        .await?;

        info!(
            call_id = %call_id,
            conversation_id = %conversation_id,
            initiator_id = %initiator_id,
            "Call created in database, sending Matrix invite"
        );

        // Step 2: Get Matrix room_id from conversation_id
        let room_id = match matrix_client.get_cached_room_id(conversation_id).await {
            Some(id) => id,
            None => {
                warn!(
                    call_id = %call_id,
                    conversation_id = %conversation_id,
                    "No Matrix room ID found in cache, call will use WebSocket signaling only"
                );
                return Ok(call_id); // Non-blocking: return call_id without Matrix
            }
        };

        // Step 3: Generate Matrix party_id for this call session
        let party_id = format!("nova-{}", Uuid::new_v4());

        // Step 4: Send m.call.invite to Matrix
        let invite_result = matrix_voip_service
            .send_invite(&room_id, call_id, &party_id, initiator_sdp, None)
            .await;

        let matrix_invite_event_id = match invite_result {
            Ok(event_id) => event_id,
            Err(e) => {
                warn!(
                    call_id = %call_id,
                    error = ?e,
                    "Failed to send Matrix invite, call will use WebSocket signaling only"
                );
                return Ok(call_id); // Non-blocking: return call_id without Matrix
            }
        };

        info!(
            call_id = %call_id,
            matrix_event_id = %matrix_invite_event_id,
            party_id = %party_id,
            "Matrix invite sent successfully"
        );

        // Step 5: Update call_sessions with Matrix event IDs
        let update_result = sqlx::query(
            "UPDATE call_sessions
             SET matrix_invite_event_id = $1, matrix_party_id = $2
             WHERE id = $3",
        )
        .bind(&matrix_invite_event_id)
        .bind(&party_id)
        .bind(call_id)
        .execute(db)
        .await;

        if let Err(e) = update_result {
            warn!(
                call_id = %call_id,
                error = ?e,
                "Failed to update Matrix event IDs in database"
            );
            // Non-blocking: call already created, Matrix metadata update failed
        }

        Ok(call_id)
    }

    /// Answer an existing call with Matrix VoIP signaling
    ///
    /// This is the Matrix-integrated version of `answer_call()`.
    /// It performs dual-write: adds participant to Nova DB and sends m.call.answer to Matrix.
    ///
    /// # Arguments
    /// * `db` - Database connection pool
    /// * `matrix_voip_service` - Matrix VoIP service for sending events
    /// * `matrix_client` - Matrix client for room lookups
    /// * `call_id` - UUID of the call to answer
    /// * `answerer_id` - User ID of the answerer
    /// * `answer_sdp` - WebRTC SDP answer from answerer
    ///
    /// # Returns
    /// Participant UUID
    ///
    /// # Errors
    /// - Database operation fails
    /// - Call not found
    /// - Matrix event sending fails (logged as warning, not returned as error)
    pub async fn answer_call_with_matrix(
        db: &Pool<Postgres>,
        matrix_voip_service: &crate::services::matrix_voip_service::MatrixVoipService,
        matrix_client: &crate::services::matrix_client::MatrixClient,
        call_id: Uuid,
        answerer_id: Uuid,
        answer_sdp: &str,
    ) -> Result<Uuid, crate::error::AppError> {
        use tracing::{info, warn};

        // Step 1: Get call's matrix_party_id and conversation_id from DB
        let call_row = sqlx::query(
            "SELECT matrix_party_id, conversation_id FROM call_sessions WHERE id = $1",
        )
        .bind(call_id)
        .fetch_optional(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch call: {e}")))?
        .ok_or(crate::error::AppError::NotFound)?;

        let conversation_id: Uuid = call_row.get("conversation_id");
        let _call_party_id: Option<String> = call_row.get("matrix_party_id");

        // Step 2: Add participant to Nova database
        let participant_id = Self::answer_call(db, call_id, answerer_id, answer_sdp).await?;

        info!(
            call_id = %call_id,
            participant_id = %participant_id,
            answerer_id = %answerer_id,
            "Participant added to database, sending Matrix answer"
        );

        // Step 3: Generate answerer's Matrix party_id
        let answerer_party_id = format!("nova-{}", Uuid::new_v4());

        // Step 4: Get Matrix room_id
        let room_id = match matrix_client.get_cached_room_id(conversation_id).await {
            Some(id) => id,
            None => {
                warn!(
                    call_id = %call_id,
                    conversation_id = %conversation_id,
                    "No Matrix room ID found in cache, answer will use WebSocket signaling only"
                );
                return Ok(participant_id); // Non-blocking
            }
        };

        // Step 5: Send m.call.answer to Matrix
        let answer_result = matrix_voip_service
            .send_answer(&room_id, call_id, &answerer_party_id, answer_sdp)
            .await;

        let matrix_answer_event_id = match answer_result {
            Ok(event_id) => event_id,
            Err(e) => {
                warn!(
                    call_id = %call_id,
                    error = ?e,
                    "Failed to send Matrix answer, will use WebSocket signaling only"
                );
                return Ok(participant_id); // Non-blocking
            }
        };

        info!(
            call_id = %call_id,
            participant_id = %participant_id,
            matrix_event_id = %matrix_answer_event_id,
            party_id = %answerer_party_id,
            "Matrix answer sent successfully"
        );

        // Step 6: Update call_participants with Matrix event IDs
        let update_result = sqlx::query(
            "UPDATE call_participants
             SET matrix_answer_event_id = $1, matrix_party_id = $2
             WHERE id = $3",
        )
        .bind(&matrix_answer_event_id)
        .bind(&answerer_party_id)
        .bind(participant_id)
        .execute(db)
        .await;

        if let Err(e) = update_result {
            warn!(
                participant_id = %participant_id,
                error = ?e,
                "Failed to update Matrix event IDs in database"
            );
            // Non-blocking: participant already added
        }

        Ok(participant_id)
    }

    /// End a call with Matrix VoIP signaling
    ///
    /// This is the Matrix-integrated version of `end_call()`.
    /// It performs dual-write: updates Nova DB and sends m.call.hangup to Matrix.
    ///
    /// # Arguments
    /// * `db` - Database connection pool
    /// * `matrix_voip_service` - Matrix VoIP service for sending events
    /// * `matrix_client` - Matrix client for room lookups
    /// * `call_id` - UUID of the call to end
    /// * `reason` - Hangup reason (e.g., "user_hangup", "ice_failed", "invite_timeout")
    ///
    /// # Errors
    /// - Database operation fails
    /// - Call not found
    /// - Matrix event sending fails (logged as warning, not returned as error)
    pub async fn end_call_with_matrix(
        db: &Pool<Postgres>,
        matrix_voip_service: &crate::services::matrix_voip_service::MatrixVoipService,
        matrix_client: &crate::services::matrix_client::MatrixClient,
        call_id: Uuid,
        reason: &str,
    ) -> Result<(), crate::error::AppError> {
        use tracing::{info, warn};

        // Step 1: Get call's matrix_party_id and conversation_id from DB
        let call_row = sqlx::query(
            "SELECT matrix_party_id, conversation_id FROM call_sessions WHERE id = $1",
        )
        .bind(call_id)
        .fetch_optional(db)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("fetch call: {e}")))?
        .ok_or(crate::error::AppError::NotFound)?;

        let conversation_id: Uuid = call_row.get("conversation_id");
        let party_id: Option<String> = call_row.get("matrix_party_id");

        // Step 2: End call in Nova database
        Self::end_call(db, call_id).await?;

        info!(
            call_id = %call_id,
            reason = %reason,
            "Call ended in database, sending Matrix hangup"
        );

        // Step 3: If no Matrix party_id, skip Matrix signaling
        let party_id = match party_id {
            Some(id) => id,
            None => {
                info!(
                    call_id = %call_id,
                    "No Matrix party_id found, skipping Matrix hangup"
                );
                return Ok(()); // Non-Matrix call, already ended in DB
            }
        };

        // Step 4: Get Matrix room_id
        let room_id = match matrix_client.get_cached_room_id(conversation_id).await {
            Some(id) => id,
            None => {
                warn!(
                    call_id = %call_id,
                    conversation_id = %conversation_id,
                    "No Matrix room ID found in cache, hangup will not be sent to Matrix"
                );
                return Ok(()); // Non-blocking: call already ended in DB
            }
        };

        // Step 5: Send m.call.hangup to Matrix
        let hangup_result = matrix_voip_service
            .send_hangup(&room_id, call_id, &party_id, reason)
            .await;

        if let Err(e) = hangup_result {
            warn!(
                call_id = %call_id,
                error = ?e,
                "Failed to send Matrix hangup, but call already ended in database"
            );
            // Non-blocking: call already ended in DB
        } else {
            info!(
                call_id = %call_id,
                reason = %reason,
                "Matrix hangup sent successfully"
            );
        }

        Ok(())
    }
}
