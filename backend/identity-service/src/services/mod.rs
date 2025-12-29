/// Service layer for identity-service
///
/// Provides business logic and integrations:
/// - Email service (SMTP for verification/password reset)
/// - Kafka event producer (user lifecycle events)
/// - Two-factor authentication (TOTP + backup codes)
/// - OAuth 2.0 (Google, Apple, Facebook, WeChat)
/// - Transactional outbox (reliable event publishing)
/// - Invite delivery (SMS via AWS SNS, Email, Dynamic Links)
/// - Phone authentication (SMS OTP via AWS SNS)
pub mod email;
pub mod invite_delivery;
pub mod kafka_events;
pub mod oauth;
pub mod outbox;
pub mod passkey;
pub mod phone_auth;
pub mod two_fa;
pub mod zitadel;

pub use email::EmailService;
pub use invite_delivery::{InviteDeliveryConfig, InviteDeliveryService, SendInviteResult};
pub use kafka_events::KafkaEventProducer;
pub use oauth::{OAuthAuthorizationUrl, OAuthCallbackResult, OAuthProvider, OAuthService};
pub use outbox::{spawn_outbox_consumer, IdentityOutboxPublisher, OutboxConsumerConfig};
pub use passkey::{PasskeyAuthenticationResult, PasskeyRegistrationResult, PasskeyService};
pub use phone_auth::{PhoneAuthService, PhoneLoginResult, PhoneRegisterResult};
pub use two_fa::{TwoFaService, TwoFaSetup};
pub use zitadel::{ZitadelService, ZitadelUserInfo};
