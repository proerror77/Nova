//! Cache error types

use thiserror::Error;

#[derive(Error, Debug)]
pub enum CacheError {
    #[error("Redis error: {0}")]
    Redis(#[from] redis::RedisError),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Cache miss")]
    NotFound,

    #[error("Invalid cache data: {0}")]
    InvalidData(String),
}

pub type CacheResult<T> = Result<T, CacheError>;
