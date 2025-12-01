use thiserror::Error;
use tonic::Status;

#[derive(Debug, Error)]
pub enum TrustSafetyError {
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),

    #[error("ONNX Runtime error: {0}")]
    OnnxRuntime(String),

    #[error("Image processing error: {0}")]
    ImageProcessing(String),

    #[error("HTTP request error: {0}")]
    Http(#[from] reqwest::Error),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Invalid input: {0}")]
    InvalidInput(String),

    #[error("Model not found: {0}")]
    ModelNotFound(String),

    #[error("Appeal not found: {0}")]
    AppealNotFound(String),

    #[error("Moderation log not found: {0}")]
    ModerationLogNotFound(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Invalid appeal status transition: {from} -> {to}")]
    InvalidAppealStatusTransition { from: String, to: String },

    #[error("Unauthorized: {0}")]
    Unauthorized(String),

    #[error("Internal error: {0}")]
    Internal(String),
}

impl From<TrustSafetyError> for Status {
    fn from(err: TrustSafetyError) -> Self {
        match err {
            TrustSafetyError::Database(e) => {
                tracing::error!("Database error: {:?}", e);
                Status::internal(format!("Database error: {}", e))
            }
            TrustSafetyError::OnnxRuntime(e) => {
                tracing::error!("ONNX Runtime error: {}", e);
                Status::internal(format!("ML inference failed: {}", e))
            }
            TrustSafetyError::ImageProcessing(e) => {
                tracing::warn!("Image processing error: {}", e);
                Status::invalid_argument(format!("Image processing failed: {}", e))
            }
            TrustSafetyError::Http(e) => {
                tracing::error!("HTTP error: {:?}", e);
                Status::internal(format!("HTTP request failed: {}", e))
            }
            TrustSafetyError::Io(e) => {
                tracing::error!("IO error: {:?}", e);
                Status::internal(format!("IO error: {}", e))
            }
            TrustSafetyError::Config(e) => {
                tracing::error!("Configuration error: {}", e);
                Status::internal(format!("Configuration error: {}", e))
            }
            TrustSafetyError::InvalidInput(e) => Status::invalid_argument(e),
            TrustSafetyError::ModelNotFound(e) => {
                tracing::error!("Model not found: {}", e);
                Status::failed_precondition(format!("Model not found: {}", e))
            }
            TrustSafetyError::AppealNotFound(id) => {
                Status::not_found(format!("Appeal not found: {}", id))
            }
            TrustSafetyError::ModerationLogNotFound(id) => {
                Status::not_found(format!("Moderation log not found: {}", id))
            }
            TrustSafetyError::NotFound(msg) => Status::not_found(msg),
            TrustSafetyError::InvalidAppealStatusTransition { from, to } => {
                Status::failed_precondition(format!(
                    "Invalid appeal status transition: {} -> {}",
                    from, to
                ))
            }
            TrustSafetyError::Unauthorized(e) => Status::permission_denied(e),
            TrustSafetyError::Internal(e) => {
                tracing::error!("Internal error: {}", e);
                Status::internal(e)
            }
        }
    }
}

pub type Result<T> = std::result::Result<T, TrustSafetyError>;
