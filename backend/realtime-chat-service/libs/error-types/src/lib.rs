use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio_postgres;

/// 服务级错误类型（用于内部错误处理）
///
/// 这个枚举为所有微服务提供统一的错误表示，可以自动转换为 HTTP 响应。
///
/// 示例：
/// ```ignore
/// match db_operation() {
///     Ok(result) => Ok(result),
///     Err(e) => Err(ServiceError::Database(e.to_string()))
/// }
/// ```
#[derive(Debug, Error)]
pub enum ServiceError {
    #[error("Database error: {0}")]
    Database(String),

    #[error("Resource not found: {0}")]
    NotFound(String),

    #[error("Unauthorized")]
    Unauthorized,

    #[error("Forbidden")]
    Forbidden,

    #[error("Validation error: {0}")]
    ValidationError(String),

    #[error("Internal server error: {0}")]
    InternalError(String),

    #[error("Bad request: {0}")]
    BadRequest(String),

    #[error("Conflict: {0}")]
    Conflict(String),

    #[error("Service unavailable")]
    ServiceUnavailable,

    #[error("Timeout")]
    Timeout,
}

impl ServiceError {
    pub fn status_code(&self) -> u16 {
        match self {
            ServiceError::NotFound(_) => 404,
            ServiceError::Unauthorized => 401,
            ServiceError::Forbidden => 403,
            ServiceError::ValidationError(_) => 400,
            ServiceError::BadRequest(_) => 400,
            ServiceError::Conflict(_) => 409,
            ServiceError::ServiceUnavailable => 503,
            ServiceError::Timeout => 408,
            ServiceError::Database(_) | ServiceError::InternalError(_) => 500,
        }
    }

    pub fn error_code(&self) -> &'static str {
        match self {
            ServiceError::NotFound(_) => "NOT_FOUND",
            ServiceError::Unauthorized => "UNAUTHORIZED",
            ServiceError::Forbidden => "FORBIDDEN",
            ServiceError::ValidationError(_) => "VALIDATION_ERROR",
            ServiceError::BadRequest(_) => "BAD_REQUEST",
            ServiceError::Conflict(_) => "CONFLICT",
            ServiceError::ServiceUnavailable => "SERVICE_UNAVAILABLE",
            ServiceError::Timeout => "TIMEOUT",
            ServiceError::Database(_) => "DATABASE_ERROR",
            ServiceError::InternalError(_) => "INTERNAL_ERROR",
        }
    }

    pub fn error_type(&self) -> &'static str {
        match self {
            ServiceError::Database(_) => "DatabaseError",
            ServiceError::NotFound(_) => "NotFoundError",
            ServiceError::Unauthorized => "UnauthorizedError",
            ServiceError::Forbidden => "ForbiddenError",
            ServiceError::ValidationError(_) => "ValidationError",
            ServiceError::BadRequest(_) => "BadRequestError",
            ServiceError::Conflict(_) => "ConflictError",
            ServiceError::ServiceUnavailable => "ServiceUnavailableError",
            ServiceError::Timeout => "TimeoutError",
            ServiceError::InternalError(_) => "InternalError",
        }
    }

    pub fn to_response(&self) -> ErrorResponse {
        ErrorResponse {
            error: self.error_type().to_string(),
            message: self.to_string(),
            status: self.status_code(),
            error_type: self.error_type().to_string(),
            code: self.error_code().to_string(),
            details: None,
            trace_id: None,
            timestamp: chrono::Utc::now().to_rfc3339(),
        }
    }
}

impl From<tokio_postgres::Error> for ServiceError {
    fn from(err: tokio_postgres::Error) -> Self {
        // tokio-postgres doesn't distinguish RowNotFound; treat all as database errors
        ServiceError::Database(err.to_string())
    }
}

/// 统一的 API 错误响应格式（所有服务使用）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorResponse {
    /// 错误代码（IANA 标准 HTTP 状态码或自定义错误代码）
    pub error: String,

    /// 错误消息（用户友好的说明）
    pub message: String,

    /// HTTP 状态码
    pub status: u16,

    /// 错误类型（用于客户端路由处理）
    /// 可能的值：
    /// - "validation_error" - 输入验证失败
    /// - "authentication_error" - 认证失败
    /// - "authorization_error" - 权限不足
    /// - "not_found_error" - 资源不存在
    /// - "conflict_error" - 冲突（如版本冲突）
    /// - "rate_limit_error" - 速率限制
    /// - "server_error" - 服务器内部错误
    /// - "service_unavailable_error" - 服务不可用
    pub error_type: String,

    /// 错误代码（用于客户端本地化和追踪）
    /// 格式：SERVICE_CODE，如 "USER_NOT_FOUND", "EMAIL_INVALID"
    pub code: String,

    /// 细节信息（可选，仅在开发环境返回）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,

    /// 请求跟踪 ID（用于日志关联）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub trace_id: Option<String>,

    /// 时间戳（ISO 8601 格式）
    pub timestamp: String,
}

impl ErrorResponse {
    pub fn new(error: &str, message: &str, status: u16, error_type: &str, code: &str) -> Self {
        Self {
            error: error.to_string(),
            message: message.to_string(),
            status,
            error_type: error_type.to_string(),
            code: code.to_string(),
            details: None,
            trace_id: None,
            timestamp: chrono::Utc::now().to_rfc3339(),
        }
    }

    pub fn with_details(mut self, details: String) -> Self {
        self.details = Some(details);
        self
    }

    pub fn with_trace_id(mut self, trace_id: String) -> Self {
        self.trace_id = Some(trace_id);
        self
    }
}

/// 标准错误代码前缀（按服务）
pub mod error_codes {
    // User Service
    pub const USER_NOT_FOUND: &str = "USER_NOT_FOUND";
    pub const USER_ALREADY_EXISTS: &str = "USER_ALREADY_EXISTS";
    pub const USER_INACTIVE: &str = "USER_INACTIVE";
    pub const INVALID_CREDENTIALS: &str = "INVALID_CREDENTIALS";

    // Authentication
    pub const TOKEN_EXPIRED: &str = "TOKEN_EXPIRED";
    pub const TOKEN_INVALID: &str = "TOKEN_INVALID";
    pub const TOKEN_MISSING: &str = "TOKEN_MISSING";
    pub const REFRESH_TOKEN_INVALID: &str = "REFRESH_TOKEN_INVALID";

    // Email/Verification
    pub const EMAIL_INVALID: &str = "EMAIL_INVALID";
    pub const EMAIL_ALREADY_VERIFIED: &str = "EMAIL_ALREADY_VERIFIED";
    pub const EMAIL_NOT_VERIFIED: &str = "EMAIL_NOT_VERIFIED";
    pub const VERIFICATION_CODE_EXPIRED: &str = "VERIFICATION_CODE_EXPIRED";
    pub const VERIFICATION_CODE_INVALID: &str = "VERIFICATION_CODE_INVALID";

    // Content Service
    pub const POST_NOT_FOUND: &str = "POST_NOT_FOUND";
    pub const POST_DELETED: &str = "POST_DELETED";
    pub const COMMENT_NOT_FOUND: &str = "COMMENT_NOT_FOUND";
    pub const COMMENT_DELETED: &str = "COMMENT_DELETED";
    pub const VERSION_CONFLICT: &str = "VERSION_CONFLICT";
    pub const RECALL_WINDOW_EXPIRED: &str = "RECALL_WINDOW_EXPIRED";
    pub const EDIT_WINDOW_EXPIRED: &str = "EDIT_WINDOW_EXPIRED";

    // Messaging Service
    pub const CONVERSATION_NOT_FOUND: &str = "CONVERSATION_NOT_FOUND";
    pub const MESSAGE_NOT_FOUND: &str = "MESSAGE_NOT_FOUND";
    pub const MESSAGE_ALREADY_RECALLED: &str = "MESSAGE_ALREADY_RECALLED";
    pub const NOT_CONVERSATION_MEMBER: &str = "NOT_CONVERSATION_MEMBER";
    pub const NOT_GROUP_OWNER: &str = "NOT_GROUP_OWNER";

    // Media Service
    pub const MEDIA_NOT_FOUND: &str = "MEDIA_NOT_FOUND";
    pub const MEDIA_PROCESSING_FAILED: &str = "MEDIA_PROCESSING_FAILED";
    pub const UPLOAD_TOO_LARGE: &str = "UPLOAD_TOO_LARGE";
    pub const UNSUPPORTED_FORMAT: &str = "UNSUPPORTED_FORMAT";

    // Database/System
    pub const DATABASE_ERROR: &str = "DATABASE_ERROR";
    pub const CACHE_ERROR: &str = "CACHE_ERROR";
    pub const INTERNAL_SERVER_ERROR: &str = "INTERNAL_SERVER_ERROR";
    pub const SERVICE_UNAVAILABLE: &str = "SERVICE_UNAVAILABLE";
    pub const RATE_LIMIT_ERROR: &str = "RATE_LIMIT_EXCEEDED";
}

/// 标准错误类型
pub mod error_types {
    pub const VALIDATION_ERROR: &str = "validation_error";
    pub const AUTHENTICATION_ERROR: &str = "authentication_error";
    pub const AUTHORIZATION_ERROR: &str = "authorization_error";
    pub const NOT_FOUND_ERROR: &str = "not_found_error";
    pub const CONFLICT_ERROR: &str = "conflict_error";
    pub const RATE_LIMIT_ERROR: &str = "rate_limit_error";
    pub const SERVER_ERROR: &str = "server_error";
    pub const SERVICE_UNAVAILABLE_ERROR: &str = "service_unavailable_error";
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_response_creation() {
        let error = ErrorResponse::new(
            "Not Found",
            "User not found",
            404,
            error_types::NOT_FOUND_ERROR,
            error_codes::USER_NOT_FOUND,
        );

        assert_eq!(error.status, 404);
        assert_eq!(error.error_type, error_types::NOT_FOUND_ERROR);
        assert_eq!(error.code, error_codes::USER_NOT_FOUND);
    }

    #[test]
    fn test_error_response_with_details() {
        let error = ErrorResponse::new(
            "Bad Request",
            "Invalid email format",
            400,
            error_types::VALIDATION_ERROR,
            error_codes::EMAIL_INVALID,
        )
        .with_details("Email must contain @ symbol".to_string());

        assert!(error.details.is_some());
    }
}
