/// HTTP handlers for notification service API
pub mod notifications;
pub mod devices;
pub mod preferences;
pub mod websocket;

pub use notifications::*;
pub use devices::*;
pub use preferences::*;
pub use websocket::register_routes as register_websocket;
