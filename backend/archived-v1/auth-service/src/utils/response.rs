/// Response utilities
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct SuccessResponse<T> {
    pub data: T,
    pub message: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ErrorResponse {
    pub error: String,
    pub details: Option<String>,
}

impl<T: Serialize> SuccessResponse<T> {
    pub fn new(data: T, message: impl Into<String>) -> Self {
        Self {
            data,
            message: message.into(),
        }
    }
}

impl ErrorResponse {
    pub fn new(error: impl Into<String>, details: Option<impl Into<String>>) -> Self {
        Self {
            error: error.into(),
            details: details.map(|d| d.into()),
        }
    }
}
