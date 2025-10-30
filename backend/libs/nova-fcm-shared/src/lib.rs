/// Nova FCM Shared Library
///
/// This library provides a unified Firebase Cloud Messaging (FCM) client
/// for sending push notifications to Android and Web devices across the Nova platform.
///
/// It handles:
/// - OAuth2 token generation using Google service accounts
/// - Token caching with automatic refresh
/// - Single and multicast message delivery
/// - Topic subscriptions and messaging
/// - Device token validation

pub mod client;
pub mod models;
pub mod errors;

pub use client::FCMClient;
pub use models::{FCMSendResult, MulticastSendResult, TopicSubscriptionResult, ServiceAccountKey};
pub use errors::FCMError;
