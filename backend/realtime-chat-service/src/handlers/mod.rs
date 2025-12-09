//! HTTP request handlers for E2EE endpoints
//!
//! This module provides REST API handlers that complement the existing
//! WebSocket-based real-time messaging system.

pub mod e2ee;
pub mod matrix_voip_event_handler;

pub use matrix_voip_event_handler::MatrixVoipEventHandler;
