use actix_web::{web, HttpResponse, Responder};
use serde::{Deserialize, Serialize};
use validator::Validate;

#[derive(Debug, Deserialize, Validate)]
pub struct RegisterRequest {
    #[validate(email)]
    pub email: String,

    #[validate(length(min = 3, max = 50))]
    pub username: String,

    #[validate(length(min = 8))]
    pub password: String,
}

#[derive(Debug, Deserialize, Validate)]
pub struct LoginRequest {
    #[validate(email)]
    pub email: String,

    #[validate(length(min = 1))]
    pub password: String,
}

#[derive(Debug, Serialize)]
pub struct AuthResponse {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

// Placeholder handlers - will be implemented in later phases
pub async fn register(_req: web::Json<RegisterRequest>) -> impl Responder {
    HttpResponse::NotImplemented().json(serde_json::json!({
        "message": "Registration endpoint - to be implemented"
    }))
}

pub async fn login(_req: web::Json<LoginRequest>) -> impl Responder {
    HttpResponse::NotImplemented().json(serde_json::json!({
        "message": "Login endpoint - to be implemented"
    }))
}

pub async fn logout() -> impl Responder {
    HttpResponse::NotImplemented().json(serde_json::json!({
        "message": "Logout endpoint - to be implemented"
    }))
}

pub async fn refresh_token() -> impl Responder {
    HttpResponse::NotImplemented().json(serde_json::json!({
        "message": "Refresh token endpoint - to be implemented"
    }))
}
