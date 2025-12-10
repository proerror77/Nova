/// Location sharing service
///
/// Manages real-time location sharing within conversations.
/// Handles sharing, updating, and stopping location broadcasts.
use crate::error::{AppError, AppResult};
use crate::models::location::*;
use chrono::Utc;
use deadpool_postgres::Pool;
use uuid::Uuid;

pub struct LocationService;

impl LocationService {
    /// Start sharing location in a conversation
    pub async fn start_sharing(
        pool: &Pool,
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
        let client = pool.get().await?;
        let existing = client.query_opt(
            r#"
            SELECT * FROM user_locations
            WHERE user_id = $1 AND conversation_id = $2
            AND is_active = true AND deleted_at IS NULL
            LIMIT 1
            "#,
            &[&user_id, &conversation_id],
        )
        .await?;

        if let Some(row) = existing {
            let existing = UserLocation::from_row(&row);
            // Update existing location
            let row = client.query_one(
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
                &[
                    &existing.id,
                    &coords.latitude,
                    &coords.longitude,
                    &coords.accuracy_meters,
                    &request.altitude_meters,
                    &request.heading_degrees,
                    &request.speed_mps,
                    &now,
                ],
            )
            .await?;

            let updated = UserLocation::from_row(&row);

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
            let row = client.query_one(
                r#"
                INSERT INTO user_locations
                (id, user_id, conversation_id, latitude, longitude, accuracy_meters,
                 altitude_meters, heading_degrees, speed_mps, is_active, created_at, updated_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, true, $10, $10)
                RETURNING *
                "#,
                &[
                    &location_id,
                    &user_id,
                    &conversation_id,
                    &coords.latitude,
                    &coords.longitude,
                    &coords.accuracy_meters,
                    &request.altitude_meters,
                    &request.heading_degrees,
                    &request.speed_mps,
                    &now,
                ],
            )
            .await?;

            let location = UserLocation::from_row(&row);

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
        pool: &Pool,
        user_id: Uuid,
        conversation_id: Uuid,
        request: StopSharingRequest,
    ) -> AppResult<()> {
        let now = Utc::now();

        // Find active location
        let client = pool.get().await?;
        let location = client.query_opt(
            r#"
            SELECT * FROM user_locations
            WHERE user_id = $1 AND conversation_id = $2
            AND is_active = true AND deleted_at IS NULL
            "#,
            &[&user_id, &conversation_id],
        )
        .await?;

        if let Some(row) = location {
            let location = UserLocation::from_row(&row);
            // Calculate duration
            let duration_seconds = request
                .duration_seconds
                .unwrap_or_else(|| (now - location.created_at).num_seconds() as i32);

            // Mark as inactive
            client.execute(
                r#"
                UPDATE user_locations
                SET is_active = false, stopped_at = $2
                WHERE id = $1
                "#,
                &[&location.id, &now],
            )
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
        pool: &Pool,
        conversation_id: Uuid,
    ) -> AppResult<ConversationLocations> {
        let client = pool.get().await?;
        let rows = client.query(
            r#"
            SELECT * FROM user_locations
            WHERE conversation_id = $1
            AND is_active = true AND deleted_at IS NULL
            ORDER BY updated_at DESC
            "#,
            &[&conversation_id],
        )
        .await?;

        let locations: Vec<UserLocation> = rows
            .iter()
            .map(|row| UserLocation::from_row(row))
            .collect();

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
        pool: &Pool,
        user_id: Uuid,
        conversation_id: Uuid,
    ) -> AppResult<Option<SharedLocation>> {
        let client = pool.get().await?;
        let location = client.query_opt(
            r#"
            SELECT * FROM user_locations
            WHERE user_id = $1 AND conversation_id = $2
            AND is_active = true AND deleted_at IS NULL
            "#,
            &[&user_id, &conversation_id],
        )
        .await?;

        Ok(location
            .map(|row| UserLocation::from_row(&row))
            .map(SharedLocation::from))
    }

    /// Get or create location permissions for a user
    pub async fn get_or_create_permission(
        pool: &Pool,
        user_id: Uuid,
    ) -> AppResult<LocationPermission> {
        // Try to fetch existing
        let client = pool.get().await?;
        let existing = client.query_opt(
            "SELECT * FROM location_permissions WHERE user_id = $1",
            &[&user_id],
        )
        .await?;

        if let Some(row) = existing {
            return Ok(LocationPermission::from_row(&row));
        }

        // Create default permission (allow sharing in conversations)
        let now = Utc::now();
        let row = client.query_one(
            r#"
            INSERT INTO location_permissions
            (id, user_id, allow_conversations, allow_search, blur_location, created_at, updated_at)
            VALUES ($1, $2, true, false, false, $3, $3)
            ON CONFLICT (user_id) DO UPDATE SET user_id = $2
            RETURNING *
            "#,
            &[&Uuid::new_v4(), &user_id, &now],
        )
        .await?;

        Ok(LocationPermission::from_row(&row))
    }

    /// Update location permissions
    pub async fn update_permissions(
        pool: &Pool,
        user_id: Uuid,
        request: UpdateLocationPermissionsRequest,
    ) -> AppResult<LocationPermission> {
        // Ensure permission record exists
        let _ = Self::get_or_create_permission(pool, user_id).await?;

        let now = Utc::now();

        // Update only provided fields
        let client = pool.get().await?;
        let row = client.query_one(
            r#"
            UPDATE location_permissions
            SET allow_conversations = COALESCE($2, allow_conversations),
                allow_search = COALESCE($3, allow_search),
                blur_location = COALESCE($4, blur_location),
                updated_at = $5
            WHERE user_id = $1
            RETURNING *
            "#,
            &[
                &user_id,
                &request.allow_conversations,
                &request.allow_search,
                &request.blur_location,
                &now,
            ],
        )
        .await?;

        Ok(LocationPermission::from_row(&row))
    }

    /// Log location sharing event
    async fn log_event(
        pool: &Pool,
        user_id: Uuid,
        conversation_id: Uuid,
        event_type: &str,
        coords: Option<LocationCoordinates>,
        duration_seconds: Option<i32>,
        distance_meters: Option<i32>,
    ) -> AppResult<()> {
        let client = pool.get().await?;
        client.execute(
            r#"
            INSERT INTO location_share_events
            (id, user_id, conversation_id, event_type, latitude, longitude,
             accuracy_meters, duration_seconds, distance_meters, created_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
            "#,
            &[
                &Uuid::new_v4(),
                &user_id,
                &conversation_id,
                &event_type,
                &coords.map(|c| c.latitude),
                &coords.map(|c| c.longitude),
                &coords.map(|c| c.accuracy_meters),
                &duration_seconds,
                &distance_meters,
            ],
        )
        .await?;

        Ok(())
    }

    /// Get location sharing statistics (for analytics)
    pub async fn get_sharing_stats(
        pool: &Pool,
        conversation_id: Uuid,
    ) -> AppResult<serde_json::Value> {
        let client = pool.get().await?;
        let row = client.query_one(
            "SELECT COUNT(*) FROM user_locations WHERE conversation_id = $1 AND is_active = true AND deleted_at IS NULL",
            &[&conversation_id],
        )
        .await?;
        let count: i64 = row.get(0);

        let last_update: Option<chrono::DateTime<chrono::Utc>> = client.query_opt(
            "SELECT MAX(updated_at) FROM user_locations WHERE conversation_id = $1 AND is_active = true AND deleted_at IS NULL",
            &[&conversation_id],
        )
        .await?
        .map(|row| row.get(0));

        Ok(serde_json::json!({
            "active_sharers": count,
            "last_update": last_update.map(|t| t.to_rfc3339()),
        }))
    }
}
