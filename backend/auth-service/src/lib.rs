// Auth Service Library

pub mod db;
pub mod error;
pub mod handlers;
pub mod models;
pub mod services;
pub mod telemetry;

pub use error::{AuthError, Result};

// Re-export commonly used types
pub use models::{
    AuthLog, EmailVerification, OAuthConnection, PasswordReset, RefreshToken, Session, User,
};

#[derive(Clone)]
pub struct AppState {
    pub db: sqlx::PgPool,
}
