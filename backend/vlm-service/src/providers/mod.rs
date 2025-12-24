//! VLM provider implementations

pub mod google_vision;

pub use google_vision::{AuthMode, GoogleVisionClient, ImageAnalysisResult, Label};
