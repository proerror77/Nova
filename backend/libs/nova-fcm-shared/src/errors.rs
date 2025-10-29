use thiserror::Error;

/// FCM Client Error Types
#[derive(Error, Debug)]
pub enum FCMError {
    #[error("Failed to parse private key: {0}")]
    KeyParseError(String),

    #[error("Failed to encode JWT: {0}")]
    JwtEncodeError(String),

    #[error("Failed to get access token: {0}")]
    TokenError(String),

    #[error("Token request failed with status: {0}")]
    TokenRequestFailed(String),

    #[error("Failed to parse token response: {0}")]
    TokenParseError(String),

    #[error("FCM send request failed: {0}")]
    SendRequestError(String),

    #[error("Failed to parse FCM response: {0}")]
    ResponseParseError(String),

    #[error("FCM API error: {0} - {1}")]
    ApiError(String, String),

    #[error("FCM topic send request failed: {0}")]
    TopicSendError(String),

    #[error("Invalid device token")]
    InvalidToken,

    #[error("Internal error")]
    Internal,
}

impl From<FCMError> for String {
    fn from(err: FCMError) -> Self {
        err.to_string()
    }
}
