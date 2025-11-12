/// Location sharing data models
///
/// Supports real-time location sharing in conversations.
/// Uses WGS84 coordinate system (standard for GPS).
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Location data point (WGS84)
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct LocationCoordinates {
    /// Latitude (-90 to 90)
    pub latitude: f64,
    /// Longitude (-180 to 180)
    pub longitude: f64,
    /// Accuracy radius in meters (0-10000)
    pub accuracy_meters: i32,
}

impl LocationCoordinates {
    pub fn new(latitude: f64, longitude: f64, accuracy_meters: i32) -> Result<Self, String> {
        if !(-90.0..=90.0).contains(&latitude) {
            return Err("Invalid latitude: must be between -90 and 90".to_string());
        }
        if !(-180.0..=180.0).contains(&longitude) {
            return Err("Invalid longitude: must be between -180 and 180".to_string());
        }
        if !(0..=10000).contains(&accuracy_meters) {
            return Err("Invalid accuracy: must be between 0 and 10000 meters".to_string());
        }

        Ok(Self {
            latitude,
            longitude,
            accuracy_meters,
        })
    }

    /// Calculate distance between two points using Haversine formula (kilometers)
    pub fn distance_to(&self, other: &LocationCoordinates) -> f64 {
        const EARTH_RADIUS_KM: f64 = 6371.0;

        let lat1_rad = self.latitude.to_radians();
        let lat2_rad = other.latitude.to_radians();
        let delta_lat = (other.latitude - self.latitude).to_radians();
        let delta_lon = (other.longitude - self.longitude).to_radians();

        let a = (delta_lat / 2.0).sin().powi(2)
            + lat1_rad.cos() * lat2_rad.cos() * (delta_lon / 2.0).sin().powi(2);
        let c = 2.0 * a.sqrt().atan2((1.0 - a).sqrt());

        EARTH_RADIUS_KM * c
    }
}

/// User location in a conversation
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct UserLocation {
    pub id: Uuid,
    pub user_id: Uuid,
    pub conversation_id: Uuid,

    pub latitude: f64,
    pub longitude: f64,
    pub accuracy_meters: i32,
    pub altitude_meters: Option<f64>,
    pub heading_degrees: Option<f64>,
    pub speed_mps: Option<f64>,

    pub is_active: bool,

    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub stopped_at: Option<DateTime<Utc>>,
    pub deleted_at: Option<DateTime<Utc>>,
}

/// Location sharing event
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocationShareEvent {
    pub id: Uuid,
    pub user_id: Uuid,
    pub conversation_id: Uuid,
    pub event_type: String, // "started", "updated", "stopped"
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub accuracy_meters: Option<i32>,
    pub duration_seconds: Option<i32>,
    pub distance_meters: Option<i32>,
    pub created_at: DateTime<Utc>,
}

/// API Request: Share location
#[derive(Debug, Deserialize)]
pub struct ShareLocationRequest {
    /// Latitude (-90 to 90)
    pub latitude: f64,
    /// Longitude (-180 to 180)
    pub longitude: f64,
    /// Accuracy in meters (0-10000)
    pub accuracy_meters: i32,
    /// Altitude (optional, in meters)
    pub altitude_meters: Option<f64>,
    /// Heading (optional, 0-360 degrees)
    pub heading_degrees: Option<f64>,
    /// Speed (optional, in m/s)
    pub speed_mps: Option<f64>,
}

/// API Response: Shared location
#[derive(Debug, Serialize)]
pub struct SharedLocation {
    pub id: Uuid,
    pub user_id: Uuid,
    pub conversation_id: Uuid,
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy_meters: i32,
    pub altitude_meters: Option<f64>,
    pub heading_degrees: Option<f64>,
    pub speed_mps: Option<f64>,
    pub is_active: bool,
    pub updated_at: String,
}

impl From<UserLocation> for SharedLocation {
    fn from(loc: UserLocation) -> Self {
        Self {
            id: loc.id,
            user_id: loc.user_id,
            conversation_id: loc.conversation_id,
            latitude: loc.latitude,
            longitude: loc.longitude,
            accuracy_meters: loc.accuracy_meters,
            altitude_meters: loc.altitude_meters,
            heading_degrees: loc.heading_degrees,
            speed_mps: loc.speed_mps,
            is_active: loc.is_active,
            updated_at: loc.updated_at.to_rfc3339(),
        }
    }
}

/// API Response: Conversation locations (all active shares)
#[derive(Debug, Serialize)]
pub struct ConversationLocations {
    pub conversation_id: Uuid,
    pub locations: Vec<SharedLocation>,
    pub timestamp: String,
}

/// API Request: Stop sharing location
#[derive(Debug, Deserialize)]
pub struct StopSharingRequest {
    pub duration_seconds: Option<i32>,
    pub distance_meters: Option<i32>,
}

/// WebSocket event payload: User shared location
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocationSharedPayload {
    pub type_: String, // "location.shared"
    pub user_id: Uuid,
    pub conversation_id: Uuid,
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy_meters: i32,
    pub altitude_meters: Option<f64>,
    pub heading_degrees: Option<f64>,
    pub speed_mps: Option<f64>,
    pub timestamp: String,
}

/// WebSocket event payload: Location updated
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocationUpdatedPayload {
    pub type_: String, // "location.updated"
    pub user_id: Uuid,
    pub conversation_id: Uuid,
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy_meters: i32,
    pub timestamp: String,
}

/// WebSocket event payload: Stopped sharing
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocationStoppedPayload {
    pub type_: String, // "location.stopped"
    pub user_id: Uuid,
    pub conversation_id: Uuid,
    pub timestamp: String,
}

/// Location permission settings
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct LocationPermission {
    pub id: Uuid,
    pub user_id: Uuid,
    pub allow_conversations: bool,
    pub allow_search: bool,
    pub blur_location: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// API Request: Update location permissions
#[derive(Debug, Deserialize)]
pub struct UpdateLocationPermissionsRequest {
    pub allow_conversations: Option<bool>,
    pub allow_search: Option<bool>,
    pub blur_location: Option<bool>,
}

/// API Response: Location permissions
#[derive(Debug, Serialize)]
pub struct LocationPermissionResponse {
    pub id: Uuid,
    pub user_id: Uuid,
    pub allow_conversations: bool,
    pub allow_search: bool,
    pub blur_location: bool,
}

impl From<LocationPermission> for LocationPermissionResponse {
    fn from(perm: LocationPermission) -> Self {
        Self {
            id: perm.id,
            user_id: perm.user_id,
            allow_conversations: perm.allow_conversations,
            allow_search: perm.allow_search,
            blur_location: perm.blur_location,
        }
    }
}
