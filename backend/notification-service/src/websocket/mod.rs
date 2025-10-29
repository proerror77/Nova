/// WebSocket real-time notification system
///
/// This module handles WebSocket connections for real-time push notifications.
///
/// Architecture:
/// 1. ConnectionManager: Manages active WebSocket connections
/// 2. Message broadcast: Sends notifications to connected clients
/// 3. User-specific channels: Route notifications to specific users
/// 4. Graceful disconnection: Handle client disconnects

pub mod manager;
pub mod messages;

pub use manager::ConnectionManager;
pub use messages::WebSocketMessage;
