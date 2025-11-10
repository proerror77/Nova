//! Database-specific error types
//!
//! Provides fine-grained error handling for database operations
//! with proper context and debugging information.

use thiserror::Error;
use std::time::Duration;

/// Database operation errors
#[derive(Debug, Error)]
pub enum DatabaseError {
    /// Connection pool exhausted
    #[error("Connection pool exhausted (max: {max_connections})")]
    PoolExhausted {
        max_connections: u32,
    },

    /// Connection timeout
    #[error("Connection timeout after {timeout:?}")]
    ConnectionTimeout {
        timeout: Duration,
    },

    /// Query timeout
    #[error("Query timeout after {timeout:?}")]
    QueryTimeout {
        timeout: Duration,
        query: String,
    },

    /// Deadlock detected
    #[error("Deadlock detected")]
    Deadlock,

    /// Foreign key constraint violation
    #[error("Foreign key constraint violation: {constraint}")]
    ForeignKeyViolation {
        constraint: String,
    },

    /// Unique constraint violation
    #[error("Unique constraint violation: {constraint}")]
    UniqueViolation {
        constraint: String,
    },

    /// Check constraint violation
    #[error("Check constraint violation: {constraint}")]
    CheckViolation {
        constraint: String,
    },

    /// Not null constraint violation
    #[error("Not null constraint violation: {column}")]
    NotNullViolation {
        column: String,
    },

    /// Transaction rollback
    #[error("Transaction rolled back")]
    TransactionRollback,

    /// Migration error
    #[error("Migration failed: {message}")]
    MigrationFailed {
        message: String,
        migration: String,
    },

    /// Connection error
    #[error("Database connection error")]
    ConnectionError {
        #[source]
        source: Box<dyn std::error::Error + Send + Sync>,
    },

    /// Generic database error
    #[error("Database error: {message}")]
    Other {
        message: String,
        #[source]
        source: Option<Box<dyn std::error::Error + Send + Sync>>,
    },
}

impl DatabaseError {
    /// Check if error is retryable
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            Self::ConnectionTimeout { .. }
            | Self::QueryTimeout { .. }
            | Self::Deadlock
            | Self::TransactionRollback
            | Self::ConnectionError { .. }
        )
    }

    /// Get suggested retry delay
    pub fn retry_delay(&self) -> Option<Duration> {
        match self {
            Self::Deadlock => Some(Duration::from_millis(100)),
            Self::ConnectionTimeout { .. } => Some(Duration::from_secs(1)),
            Self::QueryTimeout { .. } => Some(Duration::from_secs(2)),
            Self::TransactionRollback => Some(Duration::from_millis(500)),
            _ => None,
        }
    }

    /// Check if error indicates a constraint violation
    pub fn is_constraint_violation(&self) -> bool {
        matches!(
            self,
            Self::ForeignKeyViolation { .. }
            | Self::UniqueViolation { .. }
            | Self::CheckViolation { .. }
            | Self::NotNullViolation { .. }
        )
    }
}

/// Convert from sqlx errors (when using sqlx)
#[cfg(feature = "sqlx")]
impl From<sqlx::Error> for DatabaseError {
    fn from(err: sqlx::Error) -> Self {
        match err {
            sqlx::Error::PoolTimedOut => Self::PoolExhausted {
                max_connections: 0, // Would need to get from pool config
            },
            sqlx::Error::PoolClosed => Self::ConnectionError {
                source: Box::new(err),
            },
            sqlx::Error::Database(db_err) => {
                // Parse database-specific errors
                if let Some(constraint) = db_err.constraint() {
                    match db_err.kind() {
                        sqlx::error::ErrorKind::UniqueViolation => {
                            Self::UniqueViolation {
                                constraint: constraint.to_string(),
                            }
                        }
                        sqlx::error::ErrorKind::ForeignKeyViolation => {
                            Self::ForeignKeyViolation {
                                constraint: constraint.to_string(),
                            }
                        }
                        sqlx::error::ErrorKind::CheckViolation => {
                            Self::CheckViolation {
                                constraint: constraint.to_string(),
                            }
                        }
                        _ => Self::Other {
                            message: db_err.message().to_string(),
                            source: Some(Box::new(err)),
                        }
                    }
                } else {
                    Self::Other {
                        message: db_err.message().to_string(),
                        source: Some(Box::new(err)),
                    }
                }
            }
            _ => Self::Other {
                message: err.to_string(),
                source: Some(Box::new(err)),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_retryable_errors() {
        let deadlock = DatabaseError::Deadlock;
        assert!(deadlock.is_retryable());
        assert_eq!(deadlock.retry_delay(), Some(Duration::from_millis(100)));

        let unique = DatabaseError::UniqueViolation {
            constraint: "users_email_key".to_string(),
        };
        assert!(!unique.is_retryable());
        assert_eq!(unique.retry_delay(), None);
    }

    #[test]
    fn test_constraint_violations() {
        let fk = DatabaseError::ForeignKeyViolation {
            constraint: "fk_user_id".to_string(),
        };
        assert!(fk.is_constraint_violation());

        let timeout = DatabaseError::QueryTimeout {
            timeout: Duration::from_secs(5),
            query: "SELECT * FROM users".to_string(),
        };
        assert!(!timeout.is_constraint_violation());
    }
}