pub mod devices;
/// HTTP handlers for notification service API
pub mod notifications;
pub mod preferences;
pub mod websocket;

pub use devices::*;
pub use notifications::*;
pub use preferences::*;
pub use websocket::register_routes as register_websocket;
