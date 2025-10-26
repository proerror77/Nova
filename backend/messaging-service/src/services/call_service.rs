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
    /// Initiate a new video call
    ///
    /// Creates a new call session and adds the initiator as the first participant.
    /// The call starts in "ringing" status until the other party answers.
    pub async fn initiate_call(
        db: &Pool<Postgres>,
        conversation_id: Uuid,
        initiator_id: Uuid,
        initiator_sdp: &str,
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
             VALUES ($1, $2, $3, 'ringing', $4, 2, 'direct')"
        )
        .bind(call_id)
        .bind(conversation_id)
        .bind(initiator_id)
        .bind(initiator_sdp)
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
}
