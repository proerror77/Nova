//! HTTP handlers for Streaming Service
//!
//! This module contains HTTP handlers for:
//! - Live streaming (create, join, leave, etc.)
//! - WebSocket chat connections
//! - RTMP webhook integration

pub mod streams;
pub mod streams_ws;

// Re-export handlers for convenience
pub use streams::*;
pub use streams_ws::stream_chat_ws;
