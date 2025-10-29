/// HTTP request handlers (REST API)
pub mod auth;
pub mod oauth;

// Re-export handlers for easy access
pub use auth::{
    register, login, logout, refresh_token, change_password, request_password_reset,
    RegisterResponse, LoginResponse, RefreshTokenResponse, LogoutResponse,
};
pub use oauth::{
    start_oauth_flow, complete_oauth_flow,
    StartOAuthFlowResponse, OAuthLoginResponse,
};
