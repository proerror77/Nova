//! JWT authentication middleware for GraphQL Gateway

use actix_web::{
    dev::{forward_ready, Service, ServiceRequest, ServiceResponse, Transform},
    Error, HttpMessage, HttpResponse,
};
use futures_util::future::LocalBoxFuture;
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm};
use serde::{Deserialize, Serialize};
use std::future::{ready, Ready};

/// JWT Claims structure
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: String,      // Subject (user ID)
    pub exp: usize,       // Expiration time
    pub iat: usize,       // Issued at
    pub email: String,    // User email
}

/// JWT authentication middleware
pub struct JwtMiddleware {
    secret: String,
}

impl JwtMiddleware {
    pub fn new(secret: String) -> Self {
        Self { secret }
    }
}

impl<S, B> Transform<S, ServiceRequest> for JwtMiddleware
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type InitError = ();
    type Transform = JwtMiddlewareService<S>;
    type Future = Ready<Result<Self::Transform, Self::InitError>>;

    fn new_transform(&self, service: S) -> Self::Future {
        ready(Ok(JwtMiddlewareService {
            service,
            secret: self.secret.clone(),
        }))
    }
}

pub struct JwtMiddlewareService<S> {
    service: S,
    secret: String,
}

impl<S, B> Service<ServiceRequest> for JwtMiddlewareService<S>
where
    S: Service<ServiceRequest, Response = ServiceResponse<B>, Error = Error>,
    S::Future: 'static,
    B: 'static,
{
    type Response = ServiceResponse<B>;
    type Error = Error;
    type Future = LocalBoxFuture<'static, Result<Self::Response, Self::Error>>;

    forward_ready!(service);

    fn call(&self, req: ServiceRequest) -> Self::Future {
        // Skip auth for health check endpoint
        if req.path() == "/health" {
            let fut = self.service.call(req);
            return Box::pin(async move {
                let res = fut.await?;
                Ok(res)
            });
        }

        // Extract Authorization header
        let auth_header = req.headers().get("Authorization");

        if auth_header.is_none() {
            return Box::pin(async move {
                Err(actix_web::error::ErrorUnauthorized("Missing Authorization header"))
            });
        }

        let auth_str = match auth_header.unwrap().to_str() {
            Ok(s) => s,
            Err(_) => {
                return Box::pin(async move {
                    Err(actix_web::error::ErrorUnauthorized("Invalid Authorization header"))
                });
            }
        };

        // Check for Bearer token
        if !auth_str.starts_with("Bearer ") {
            return Box::pin(async move {
                Err(actix_web::error::ErrorUnauthorized("Authorization must use Bearer scheme"))
            });
        }

        let token = &auth_str[7..]; // Remove "Bearer " prefix

        // Validate JWT
        let secret = self.secret.clone();
        let validation = Validation::new(Algorithm::HS256);
        let decoding_key = DecodingKey::from_secret(secret.as_bytes());

        let token_data = match decode::<Claims>(token, &decoding_key, &validation) {
            Ok(data) => data,
            Err(e) => {
                return Box::pin(async move {
                    Err(actix_web::error::ErrorUnauthorized(format!("Invalid token: {}", e)))
                });
            }
        };

        // Store user_id in request extensions for downstream use
        req.extensions_mut().insert(token_data.claims.sub.clone());
        req.extensions_mut().insert(token_data.claims.clone());

        let fut = self.service.call(req);
        Box::pin(async move {
            let res = fut.await?;
            Ok(res)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::{test, web, App};
    use jsonwebtoken::{encode, EncodingKey, Header};

    fn create_test_jwt(user_id: &str, expires_in_seconds: i64, secret: &str) -> String {
        let now = chrono::Utc::now().timestamp();
        let exp = (now + expires_in_seconds) as usize;

        let claims = Claims {
            sub: user_id.to_string(),
            exp,
            iat: now as usize,
            email: "test@example.com".to_string(),
        };

        encode(
            &Header::new(Algorithm::HS256),
            &claims,
            &EncodingKey::from_secret(secret.as_bytes()),
        )
        .unwrap()
    }

    async fn test_handler() -> actix_web::Result<HttpResponse> {
        Ok(HttpResponse::Ok().body("success"))
    }

    #[actix_web::test]
    async fn test_valid_jwt_allows_access() {
        let app = test::init_service(
            App::new()
                .wrap(JwtMiddleware::new("test-secret".to_string()))
                .route("/test", web::get().to(test_handler)),
        )
        .await;

        let valid_token = create_test_jwt("user-123", 3600, "test-secret");

        let req = test::TestRequest::get()
            .uri("/test")
            .insert_header(("Authorization", format!("Bearer {}", valid_token)))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 200);
    }

    #[actix_web::test]
    async fn test_expired_jwt_rejected() {
        let app = test::init_service(
            App::new()
                .wrap(JwtMiddleware::new("test-secret".to_string()))
                .route("/test", web::get().to(test_handler)),
        )
        .await;

        let expired_token = create_test_jwt("user-123", -3600, "test-secret");

        let req = test::TestRequest::get()
            .uri("/test")
            .insert_header(("Authorization", format!("Bearer {}", expired_token)))
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 401);
    }

    #[actix_web::test]
    async fn test_missing_authorization_header() {
        let app = test::init_service(
            App::new()
                .wrap(JwtMiddleware::new("test-secret".to_string()))
                .route("/test", web::get().to(test_handler)),
        )
        .await;

        let req = test::TestRequest::get()
            .uri("/test")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 401);
    }

    #[actix_web::test]
    async fn test_health_check_bypasses_auth() {
        let app = test::init_service(
            App::new()
                .wrap(JwtMiddleware::new("test-secret".to_string()))
                .route("/health", web::get().to(test_handler)),
        )
        .await;

        let req = test::TestRequest::get()
            .uri("/health")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 200);
    }
}
