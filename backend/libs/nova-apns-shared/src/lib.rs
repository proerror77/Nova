/// Nova APNs Shared Library
///
/// This library provides a unified Apple Push Notification Service (APNs) client
/// for sending push notifications to iOS and macOS devices across the Nova platform.
///
/// It handles:
/// - Certificate loading and validation
/// - HTTP/2 connection management with connection pooling
/// - Notification building and sending
/// - Error handling and logging
/// - Support for badges, sounds, and priority levels
pub mod client;
pub mod config;

pub use client::{ApnsPush, PushProvider};
pub use config::ApnsConfig;
