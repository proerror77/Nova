use actix_web::{web, HttpResponse, Responder};
use serde::Serialize;
use sqlx::PgPool;
use uuid::Uuid;

use crate::db::user_repo;

#[derive(Debug, Serialize)]
pub struct PublicUser {
    pub id: Uuid,
    pub username: String,
    pub email: String,
    pub display_name: Option<String>,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub is_verified: bool,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// GET /api/v1/users/{id}
pub async fn get_user(path: web::Path<String>, pool: web::Data<PgPool>) -> impl Responder {
    let id = match Uuid::parse_str(&path.into_inner()) {
        Ok(id) => id,
        Err(e) => {
            return HttpResponse::BadRequest().json(serde_json::json!({
                "error": "Invalid user id",
                "details": e.to_string()
            }))
        }
    };

    match user_repo::find_by_id(pool.get_ref(), id).await {
        Ok(Some(u)) => HttpResponse::Ok().json(PublicUser {
            id: u.id,
            username: u.username,
            email: u.email,
            display_name: None,
            bio: None,
            avatar_url: None,
            is_verified: u.email_verified,
            created_at: u.created_at,
        }),
        Ok(None) => HttpResponse::NotFound().finish(),
        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
            "error": "Database error",
            "details": e.to_string()
        })),
    }
}

