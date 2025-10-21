//! User notification preferences management

use crate::services::notifications::models::{NotificationPreferences, NotificationType, DeliveryChannel};
use chrono::{Local, NaiveTime};
use uuid::Uuid;

/// Service for managing notification preferences
pub struct PreferencesService;

impl PreferencesService {
    /// Check if notifications are enabled for a type
    pub fn is_notification_enabled(
        preferences: &NotificationPreferences,
        notification_type: &NotificationType,
    ) -> bool {
        match notification_type {
            NotificationType::Like => preferences.likes_enabled,
            NotificationType::Comment => preferences.comments_enabled,
            NotificationType::Follow => preferences.follows_enabled,
            NotificationType::Message => preferences.messages_enabled,
            NotificationType::LiveStart => preferences.live_notifications_enabled,
            NotificationType::StreamUpdate => preferences.live_notifications_enabled,
        }
    }

    /// Check if channel is enabled for notifications
    pub fn is_channel_enabled(
        preferences: &NotificationPreferences,
        channel: &DeliveryChannel,
    ) -> bool {
        match channel {
            DeliveryChannel::FCM => preferences.push_enabled,
            DeliveryChannel::APNs => preferences.push_enabled,
            DeliveryChannel::Email => preferences.email_enabled,
            DeliveryChannel::InApp => preferences.in_app_enabled,
        }
    }

    /// Check if currently in quiet hours
    pub fn is_quiet_hours(preferences: &NotificationPreferences) -> bool {
        if !preferences.quiet_hours_enabled {
            return false;
        }

        let start = preferences.quiet_hours_start.as_ref();
        let end = preferences.quiet_hours_end.as_ref();

        match (start, end) {
            (Some(start_str), Some(end_str)) => {
                if let (Ok(start), Ok(end)) = (
                    NaiveTime::parse_from_str(start_str, "%H:%M:%S"),
                    NaiveTime::parse_from_str(end_str, "%H:%M:%S"),
                ) {
                    let now = Local::now().time();
                    if start < end {
                        // e.g., 22:00 to 08:00
                        now >= start && now < end
                    } else {
                        // e.g., 22:00 to 08:00 (crosses midnight)
                        now >= start || now < end
                    }
                } else {
                    false
                }
            }
            _ => false,
        }
    }

    /// Get appropriate channels for delivery based on preferences
    pub fn get_enabled_channels(
        preferences: &NotificationPreferences,
        in_quiet_hours: bool,
    ) -> Vec<DeliveryChannel> {
        let mut channels = Vec::new();

        // In-app is always delivered unless in quiet hours
        if !in_quiet_hours && preferences.in_app_enabled {
            channels.push(DeliveryChannel::InApp);
        }

        // Push notifications
        if preferences.push_enabled {
            channels.push(DeliveryChannel::FCM);
            channels.push(DeliveryChannel::APNs);
        }

        // Email
        if preferences.email_enabled {
            channels.push(DeliveryChannel::Email);
        }

        channels
    }

    /// Create default preferences for new user
    pub fn create_default(user_id: Uuid) -> NotificationPreferences {
        use chrono::Utc;

        NotificationPreferences {
            id: 0, // Will be set by database
            user_id,
            push_enabled: true,
            email_enabled: true,
            in_app_enabled: true,
            likes_enabled: true,
            comments_enabled: true,
            follows_enabled: true,
            messages_enabled: true,
            live_notifications_enabled: true,
            quiet_hours_start: Some("22:00:00".to_string()),
            quiet_hours_end: Some("08:00:00".to_string()),
            quiet_hours_enabled: false,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }

    /// Validate preferences
    pub fn validate(preferences: &NotificationPreferences) -> Result<(), String> {
        if let (Some(start), Some(end)) = (&preferences.quiet_hours_start, &preferences.quiet_hours_end) {
            // Validate time format
            if NaiveTime::parse_from_str(start, "%H:%M:%S").is_err() {
                return Err("Invalid quiet_hours_start format. Use HH:MM:SS".to_string());
            }
            if NaiveTime::parse_from_str(end, "%H:%M:%S").is_err() {
                return Err("Invalid quiet_hours_end format. Use HH:MM:SS".to_string());
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    #[test]
    fn test_is_notification_enabled_like() {
        let prefs = NotificationPreferences {
            id: 1,
            user_id: Uuid::new_v4(),
            push_enabled: true,
            email_enabled: true,
            in_app_enabled: true,
            likes_enabled: true,
            comments_enabled: false,
            follows_enabled: false,
            messages_enabled: false,
            live_notifications_enabled: false,
            quiet_hours_start: None,
            quiet_hours_end: None,
            quiet_hours_enabled: false,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        assert!(PreferencesService::is_notification_enabled(
            &prefs,
            &NotificationType::Like
        ));
        assert!(!PreferencesService::is_notification_enabled(
            &prefs,
            &NotificationType::Comment
        ));
    }

    #[test]
    fn test_is_channel_enabled() {
        let prefs = NotificationPreferences {
            id: 1,
            user_id: Uuid::new_v4(),
            push_enabled: true,
            email_enabled: false,
            in_app_enabled: true,
            likes_enabled: true,
            comments_enabled: true,
            follows_enabled: true,
            messages_enabled: true,
            live_notifications_enabled: true,
            quiet_hours_start: None,
            quiet_hours_end: None,
            quiet_hours_enabled: false,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        assert!(PreferencesService::is_channel_enabled(
            &prefs,
            &DeliveryChannel::FCM
        ));
        assert!(!PreferencesService::is_channel_enabled(
            &prefs,
            &DeliveryChannel::Email
        ));
    }

    #[test]
    fn test_get_enabled_channels() {
        let prefs = NotificationPreferences {
            id: 1,
            user_id: Uuid::new_v4(),
            push_enabled: true,
            email_enabled: true,
            in_app_enabled: true,
            likes_enabled: true,
            comments_enabled: true,
            follows_enabled: true,
            messages_enabled: true,
            live_notifications_enabled: true,
            quiet_hours_start: None,
            quiet_hours_end: None,
            quiet_hours_enabled: false,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        let channels = PreferencesService::get_enabled_channels(&prefs, false);
        assert_eq!(channels.len(), 4); // InApp, FCM, APNs, Email
        assert!(channels.contains(&DeliveryChannel::InApp));
    }

    #[test]
    fn test_create_default_preferences() {
        let user_id = Uuid::new_v4();
        let prefs = PreferencesService::create_default(user_id);

        assert_eq!(prefs.user_id, user_id);
        assert!(prefs.push_enabled);
        assert!(prefs.email_enabled);
        assert!(prefs.in_app_enabled);
        assert!(!prefs.quiet_hours_enabled);
    }

    #[test]
    fn test_validate_preferences() {
        let user_id = Uuid::new_v4();
        let mut prefs = PreferencesService::create_default(user_id);

        // Valid preferences
        assert!(PreferencesService::validate(&prefs).is_ok());

        // Invalid time format
        prefs.quiet_hours_start = Some("invalid".to_string());
        prefs.quiet_hours_enabled = true;
        assert!(PreferencesService::validate(&prefs).is_err());
    }
}
