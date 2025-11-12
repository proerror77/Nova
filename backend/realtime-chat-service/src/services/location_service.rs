/// Location sharing service
///
/// Manages real-time location sharing within conversations.
/// Handles sharing, updating, and stopping location broadcasts.
use crate::error::{AppError, AppResult};
use crate::models::location::*;
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;

pub struct LocationService;

impl LocationService {
    /// Start sharing location in a conversation
    pub async fn start_sharing(
        pool: &PgPool,
        user_id: Uuid,
        conversation_id: Uuid,
        request: ShareLocationRequest,
    ) -> AppResult<SharedLocation> {
        // Validate coordinates
        let coords =
            LocationCoordinates::new(request.latitude, request.longitude, request.accuracy_meters)
                .map_err(AppError::BadRequest)?;

        // Check if user has permission to share
        let perm = Self::get_or_create_permission(pool, user_id).await?;
        if !perm.allow_conversations {
            return Err(AppError::Forbidden);
        }

        let now = Utc::now();
        let location_id = Uuid::new_v4();

        // Check if user already has active location in this conversation
        // If yes, update it; if no, create new entry
        let existing = sqlx::query_as::<_, UserLocation>(
            r#"
            SELECT * FROM user_locations
            WHERE user_id = $1 AND conversation_id = $2
            AND is_active = true AND deleted_at IS NULL
            LIMIT 1
            "#,
        )
        .bind(user_id)
        .bind(conversation_id)
        .fetch_optional(pool)
        .await?;

        if let Some(existing) = existing {
            // Update existing location
            let updated = sqlx::query_as::<_, UserLocation>(
                r#"
                UPDATE user_locations
                SET latitude = $2,
                    longitude = $3,
                    accuracy_meters = $4,
                    altitude_meters = $5,
                    heading_degrees = $6,
                    speed_mps = $7,
                    updated_at = $8
                WHERE id = $1 AND is_active = true
                RETURNING *
                "#,
            )
            .bind(existing.id)
            .bind(coords.latitude)
            .bind(coords.longitude)
            .bind(coords.accuracy_meters)
            .bind(request.altitude_meters)
            .bind(request.heading_degrees)
            .bind(request.speed_mps)
            .bind(now)
            .fetch_one(pool)
            .await?;

            // Log update event
            let _ = Self::log_event(
                pool,
                user_id,
                conversation_id,
                "updated",
                Some(coords),
                None,
                None,
            )
            .await;

            Ok(SharedLocation::from(updated))
        } else {
            // Create new location share
            let location = sqlx::query_as::<_, UserLocation>(
                r#"
                INSERT INTO user_locations
                (id, user_id, conversation_id, latitude, longitude, accuracy_meters,
                 altitude_meters, heading_degrees, speed_mps, is_active, created_at, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, true, $10, $10)
                RETURNING *
                "#,
            )
            .bind(location_id)
            .bind(user_id)
            .bind(conversation_id)
            .bind(coords.latitude)
            .bind(coords.longitude)
            .bind(coords.accuracy_meters)
            .bind(request.altitude_meters)
            .bind(request.heading_degrees)
            .bind(request.speed_mps)
            .bind(now)
            .fetch_one(pool)
            .await?;

            // Log start event
            let _ = Self::log_event(
                pool,
                user_id,
                conversation_id,
                "started",
                Some(coords),
                None,
                None,
            )
            .await;

            Ok(SharedLocation::from(location))
        }
    }

    /// Stop sharing location
    pub async fn stop_sharing(
        pool: &PgPool,
        user_id: Uuid,
        conversation_id: Uuid,
        request: StopSharingRequest,
    ) -> AppResult<()> {
        let now = Utc::now();

        // Find active location
        let location = sqlx::query_as::<_, UserLocation>(
            r#"
            SELECT * FROM user_locations
            WHERE user_id = $1 AND conversation_id = $2
            AND is_active = true AND deleted_at IS NULL
            "#,
        )
        .bind(user_id)
        .bind(conversation_id)
        .fetch_optional(pool)
        .await?;

        if let Some(location) = location {
            // Calculate duration
            let duration_seconds = request
                .duration_seconds
                .unwrap_or_else(|| (now - location.created_at).num_seconds() as i32);

            // Mark as inactive
            sqlx::query(
                r#"
                UPDATE user_locations
                SET is_active = false, stopped_at = $2
                WHERE id = $1
                "#,
            )
            .bind(location.id)
            .bind(now)
            .execute(pool)
            .await?;

            // Log stop event
            let _ = Self::log_event(
                pool,
                user_id,
                conversation_id,
                "stopped",
                None,
                Some(duration_seconds),
                request.distance_meters,
            )
            .await;
        }

        Ok(())
    }

    /// Get all active locations in a conversation
    pub async fn get_conversation_locations(
        pool: &PgPool,
        conversation_id: Uuid,
    ) -> AppResult<ConversationLocations> {
        let locations: Vec<UserLocation> = sqlx::query_as(
            r#"
            SELECT * FROM user_locations
            WHERE conversation_id = $1
            AND is_active = true AND deleted_at IS NULL
            ORDER BY updated_at DESC
            "#,
        )
        .bind(conversation_id)
        .fetch_all(pool)
        .await?;

        let shared_locations: Vec<SharedLocation> =
            locations.into_iter().map(SharedLocation::from).collect();

        Ok(ConversationLocations {
            conversation_id,
            locations: shared_locations,
            timestamp: Utc::now().to_rfc3339(),
        })
    }

    /// Get a specific user's location in a conversation
    pub async fn get_user_location(
        pool: &PgPool,
        user_id: Uuid,
        conversation_id: Uuid,
    ) -> AppResult<Option<SharedLocation>> {
        let location = sqlx::query_as::<_, UserLocation>(
            r#"
            SELECT * FROM user_locations
            WHERE user_id = $1 AND conversation_id = $2
            AND is_active = true AND deleted_at IS NULL
            "#,
        )
        .bind(user_id)
        .bind(conversation_id)
        .fetch_optional(pool)
        .await?;

        Ok(location.map(SharedLocation::from))
    }

    /// Get or create location permissions for a user
    pub async fn get_or_create_permission(
        pool: &PgPool,
        user_id: Uuid,
    ) -> AppResult<LocationPermission> {
        // Try to fetch existing
        let existing = sqlx::query_as::<_, LocationPermission>(
            "SELECT * FROM location_permissions WHERE user_id = $1",
        )
        .bind(user_id)
        .fetch_optional(pool)
        .await?;

        if let Some(perm) = existing {
            return Ok(perm);
        }

        // Create default permission (allow sharing in conversations)
        let now = Utc::now();
        let perm = sqlx::query_as::<_, LocationPermission>(
            r#"
            INSERT INTO location_permissions
            (id, user_id, allow_conversations, allow_search, blur_location, created_at, updated_at)
            VALUES ($1, $2, true, false, false, $3, $3)
            ON CONFLICT (user_id) DO UPDATE SET user_id = $2
            RETURNING *
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(now)
        .fetch_one(pool)
        .await?;

        Ok(perm)
    }

    /// Update location permissions
    pub async fn update_permissions(
        pool: &PgPool,
        user_id: Uuid,
        request: UpdateLocationPermissionsRequest,
    ) -> AppResult<LocationPermission> {
        // Ensure permission record exists
        let _ = Self::get_or_create_permission(pool, user_id).await?;

        let now = Utc::now();

        // Update only provided fields
        let perm = sqlx::query_as::<_, LocationPermission>(
            r#"
            UPDATE location_permissions
            SET allow_conversations = COALESCE($2, allow_conversations),
                allow_search = COALESCE($3, allow_search),
                blur_location = COALESCE($4, blur_location),
                updated_at = $5
            WHERE user_id = $1
            RETURNING *
            "#,
        )
        .bind(user_id)
        .bind(request.allow_conversations)
        .bind(request.allow_search)
        .bind(request.blur_location)
        .bind(now)
        .fetch_one(pool)
        .await?;

        Ok(perm)
    }

    /// Log location sharing event
    async fn log_event(
        pool: &PgPool,
        user_id: Uuid,
        conversation_id: Uuid,
        event_type: &str,
        coords: Option<LocationCoordinates>,
        duration_seconds: Option<i32>,
        distance_meters: Option<i32>,
    ) -> AppResult<()> {
        sqlx::query(
            r#"
            INSERT INTO location_share_events
            (id, user_id, conversation_id, event_type, latitude, longitude,
             accuracy_meters, duration_seconds, distance_meters, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(conversation_id)
        .bind(event_type)
        .bind(coords.map(|c| c.latitude))
        .bind(coords.map(|c| c.longitude))
        .bind(coords.map(|c| c.accuracy_meters))
        .bind(duration_seconds)
        .bind(distance_meters)
        .execute(pool)
        .await?;

        Ok(())
    }

    /// Get location sharing statistics (for analytics)
    pub async fn get_sharing_stats(
        pool: &PgPool,
        conversation_id: Uuid,
    ) -> AppResult<serde_json::Value> {
        let row: (i64,) = sqlx::query_as(
            "SELECT COUNT(*) FROM user_locations WHERE conversation_id = $1 AND is_active = true AND deleted_at IS NULL"
        )
        .bind(conversation_id)
        .fetch_one(pool)
        .await?;

        let last_update: Option<(chrono::DateTime<chrono::Utc>,)> = sqlx::query_as(
            "SELECT MAX(updated_at) FROM user_locations WHERE conversation_id = $1 AND is_active = true AND deleted_at IS NULL"
        )
        .bind(conversation_id)
        .fetch_optional(pool)
        .await?;

        Ok(serde_json::json!({
            "active_sharers": row.0,
            "last_update": last_update.map(|(t,)| t.to_rfc3339()),
        }))
    }
}
