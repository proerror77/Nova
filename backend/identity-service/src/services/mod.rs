/// Service layer for identity-service
///
/// Provides business logic and integrations:
/// - Email service (SMTP for verification/password reset)
/// - Kafka event producer (user lifecycle events)
/// - Two-factor authentication (TOTP + backup codes)
/// - OAuth 2.0 (Google, Apple, Facebook, WeChat)
/// - Transactional outbox (reliable event publishing)
pub mod email;
pub mod kafka_events;
pub mod oauth;
pub mod outbox;
pub mod two_fa;

pub use email::EmailService;
pub use kafka_events::KafkaEventProducer;
pub use oauth::{OAuthAuthorizationUrl, OAuthCallbackResult, OAuthProvider, OAuthService};
pub use outbox::{spawn_outbox_consumer, OutboxConsumerConfig};
pub use two_fa::{TwoFaService, TwoFaSetup};
