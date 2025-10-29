/// FCM Client - Re-export from shared library
///
/// This module re-exports the FCMClient from the nova-fcm-shared library
/// to maintain backward compatibility with existing code that imports from notification-service.
/// The actual implementation has been moved to the shared library to avoid code duplication.

pub use nova_fcm_shared::{
    FCMClient, FCMSendResult, MulticastSendResult, TopicSubscriptionResult, ServiceAccountKey,
    FCMError,
};
