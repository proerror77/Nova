use actix_web::{HttpResponse, Responder};

#[inline]
pub async fn stories_not_implemented() -> impl Responder {
    HttpResponse::NotImplemented().json(serde_json::json!({
        "message": "Stories API not implemented yet"
    }))
}

