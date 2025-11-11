use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::value_objects::{Email, HashedPassword, UserId};
use super::events::IdentityEvent;
use super::errors::IdentityError;

/// User Aggregate Root - The core identity entity
///
/// This aggregate owns all authentication-related data.
/// Profile data is NOT stored here - it belongs to user-service.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct User {
    // Identity fields (owned by this service)
    pub id: UserId,
    pub email: Email,
    pub password_hash: HashedPassword,
    pub email_verified: bool,
    pub is_active: bool,
    pub is_locked: bool,
    pub failed_login_attempts: i32,
    pub locked_until: Option<DateTime<Utc>>,

    // Metadata
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_login_at: Option<DateTime<Utc>>,
    pub password_changed_at: DateTime<Utc>,

    // Event tracking
    #[serde(skip)]
    pending_events: Vec<IdentityEvent>,
}

impl User {
    /// Create a new user with email and password
    pub fn create(email: Email, password: &str) -> Result<Self, IdentityError> {
        let id = UserId::new();
        let password_hash = HashedPassword::from_plain(password)?;
        let now = Utc::now();

        let mut user = Self {
            id: id.clone(),
            email: email.clone(),
            password_hash,
            email_verified: false,
            is_active: true,
            is_locked: false,
            failed_login_attempts: 0,
            locked_until: None,
            created_at: now,
            updated_at: now,
            last_login_at: None,
            password_changed_at: now,
            pending_events: Vec::new(),
        };

        // Record domain event
        user.record_event(IdentityEvent::UserCreated {
            user_id: id,
            email,
            created_at: now,
        });

        Ok(user)
    }

    /// Attempt to authenticate with password
    pub fn authenticate(&mut self, password: &str) -> Result<(), IdentityError> {
        // Check if account is locked
        if self.is_locked {
            if let Some(locked_until) = self.locked_until {
                if Utc::now() < locked_until {
                    return Err(IdentityError::AccountLocked);
                }
                // Unlock if time has passed
                self.unlock();
            }
        }

        // Verify password
        if !self.password_hash.verify(password)? {
            self.record_failed_login();
            return Err(IdentityError::InvalidCredentials);
        }

        // Reset failed attempts on successful login
        self.failed_login_attempts = 0;
        self.last_login_at = Some(Utc::now());
        self.updated_at = Utc::now();

        // Record event
        self.record_event(IdentityEvent::UserAuthenticated {
            user_id: self.id.clone(),
            authenticated_at: Utc::now(),
        });

        Ok(())
    }

    /// Change user password
    pub fn change_password(&mut self, old_password: &str, new_password: &str) -> Result<(), IdentityError> {
        // Verify old password
        if !self.password_hash.verify(old_password)? {
            return Err(IdentityError::InvalidCredentials);
        }

        // Set new password
        self.password_hash = HashedPassword::from_plain(new_password)?;
        self.password_changed_at = Utc::now();
        self.updated_at = Utc::now();

        // Record event
        self.record_event(IdentityEvent::PasswordChanged {
            user_id: self.id.clone(),
            changed_at: self.password_changed_at,
        });

        Ok(())
    }

    /// Reset password (for forgot password flow)
    pub fn reset_password(&mut self, new_password: &str) -> Result<(), IdentityError> {
        self.password_hash = HashedPassword::from_plain(new_password)?;
        self.password_changed_at = Utc::now();
        self.updated_at = Utc::now();

        // Clear any lockout
        self.unlock();

        // Record event
        self.record_event(IdentityEvent::PasswordReset {
            user_id: self.id.clone(),
            reset_at: self.password_changed_at,
        });

        Ok(())
    }

    /// Verify email address
    pub fn verify_email(&mut self) {
        self.email_verified = true;
        self.updated_at = Utc::now();

        self.record_event(IdentityEvent::EmailVerified {
            user_id: self.id.clone(),
            verified_at: Utc::now(),
        });
    }

    /// Lock account after too many failed attempts
    fn record_failed_login(&mut self) {
        self.failed_login_attempts += 1;

        // Lock after 5 failed attempts
        if self.failed_login_attempts >= 5 {
            self.is_locked = true;
            self.locked_until = Some(Utc::now() + chrono::Duration::minutes(30));

            self.record_event(IdentityEvent::AccountLocked {
                user_id: self.id.clone(),
                locked_at: Utc::now(),
                locked_until: self.locked_until.unwrap(),
            });
        }
    }

    /// Unlock account
    fn unlock(&mut self) {
        self.is_locked = false;
        self.locked_until = None;
        self.failed_login_attempts = 0;
        self.updated_at = Utc::now();

        self.record_event(IdentityEvent::AccountUnlocked {
            user_id: self.id.clone(),
            unlocked_at: Utc::now(),
        });
    }

    /// Record a domain event
    fn record_event(&mut self, event: IdentityEvent) {
        self.pending_events.push(event);
    }

    /// Get and clear pending events
    pub fn take_events(&mut self) -> Vec<IdentityEvent> {
        std::mem::take(&mut self.pending_events)
    }

    /// Deactivate user account
    pub fn deactivate(&mut self) {
        self.is_active = false;
        self.updated_at = Utc::now();

        self.record_event(IdentityEvent::UserDeactivated {
            user_id: self.id.clone(),
            deactivated_at: Utc::now(),
        });
    }

    /// Reactivate user account
    pub fn reactivate(&mut self) {
        self.is_active = true;
        self.updated_at = Utc::now();

        self.record_event(IdentityEvent::UserReactivated {
            user_id: self.id.clone(),
            reactivated_at: Utc::now(),
        });
    }
}