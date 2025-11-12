//! Streaming Manifest Generation Module
//!
//! This module handles VOD (Video-on-Demand) manifest generation for:
//! - HLS (HTTP Live Streaming) playlists
//! - DASH (Dynamic Adaptive Streaming over HTTP) manifests
//!
//! ## Scope
//!
//! This module is focused on **VOD playback only**:
//! - Pre-recorded video manifest generation
//! - Adaptive bitrate streaming configurations
//! - Multi-quality tier support
//!
//! ## NOT in Scope
//!
//! Live streaming features are handled by the future `live-service` (Issue #15):
//! - RTMP ingestion and authentication
//! - WebSocket live chat
//! - Live viewer counting
//! - Real-time stream discovery
//! - Live stream analytics
//!
//! ## Architecture
//!
//! - **manifest.rs** - HLS/DASH manifest generation logic
//! - Uses standard streaming protocols (HLS, DASH)
//! - Integrates with CDN delivery (CloudFront, Cloudflare)
//! - Supports adaptive bitrate streaming (ABR)

pub mod manifest;

// Re-export commonly used types
pub use manifest::{QualityTier, StreamingConfig, StreamingManifestGenerator};
