/// JWKS (JSON Web Key Set) endpoint for JWT public key distribution
/// Allows clients to verify JWT signatures without storing private keys
use actix_web::{web, HttpResponse};
use sqlx::PgPool;

use crate::security::jwt;

/// GET /.well-known/jwks.json
/// Returns all active public keys in JWKS format
pub async fn get_jwks(pool: web::Data<PgPool>) -> HttpResponse {
    // Get JWKS with 7-day grace period (default)
    match jwt::get_jwks(&pool, 7).await {
        Ok(jwks) => HttpResponse::Ok().json(jwks),
        Err(e) => {
            tracing::error!("Failed to retrieve JWKS: {}", e);
            HttpResponse::InternalServerError().json(serde_json::json!({
                "error": "Failed to retrieve public keys"
            }))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::{test, App};

    #[actix_web::test]
    async fn test_jwks_endpoint_structure() {
        // This is a placeholder test - actual test would require database setup
        // In practice, you'd mock the database or use a test database

        // Verify the endpoint is wired correctly
        let app =
            test::init_service(App::new().route("/.well-known/jwks.json", web::get().to(get_jwks)))
                .await;

        // Note: This will fail without a proper database connection
        // In production, use integration tests with test database
    }
}
