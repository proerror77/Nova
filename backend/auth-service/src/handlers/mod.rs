/// HTTP request handlers (REST API)
pub mod auth;
pub mod oauth;

// Re-export handlers for easy access
pub use auth::{
    change_password, login, logout, refresh_token, register, request_password_reset, LoginResponse,
    LogoutResponse, RefreshTokenResponse, RegisterResponse,
};
pub use oauth::{
    complete_oauth_flow, start_oauth_flow, OAuthLoginResponse, StartOAuthFlowResponse,
};
