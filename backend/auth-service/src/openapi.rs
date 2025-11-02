use utoipa::OpenApi;

use auth_service::handlers::auth::{
    ErrorResponse, LoginResponse, LogoutResponse, RefreshTokenResponse, RegisterResponse,
};
use auth_service::models::user::{
    ChangePasswordRequest, LoginRequest, RefreshTokenRequest, RegisterRequest,
    RequestPasswordResetRequest,
};

/// OpenAPI 文件，涵蓋 AuthService 暴露的 REST 端點
#[derive(OpenApi)]
#[openapi(
    paths(
        auth_service::handlers::auth::register,
        auth_service::handlers::auth::login,
        auth_service::handlers::auth::logout,
        auth_service::handlers::auth::refresh_token,
        auth_service::handlers::auth::change_password,
        auth_service::handlers::auth::request_password_reset
    ),
    components(schemas(
        RegisterRequest,
        LoginRequest,
        ChangePasswordRequest,
        RefreshTokenRequest,
        RequestPasswordResetRequest,
        RegisterResponse,
        LoginResponse,
        RefreshTokenResponse,
        LogoutResponse,
        ErrorResponse
    )),
    tags(
        (name = "Auth", description = "Authentication & token APIs")
    )
)]
pub struct ApiDoc;
