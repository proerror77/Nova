use crate::error::Result;
use crate::services::deep_learning_inference::DeepLearningInferenceService;
use actix_web::{web, HttpResponse};

/// POST /api/v1/admin/milvus/init-collection
pub async fn init_milvus_collection(
    dl: web::Data<DeepLearningInferenceService>,
) -> Result<HttpResponse> {
    let ok = dl.ensure_milvus_collection().await?;
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "collection": dl.get_config_info().get("milvus_collection"),
        "created_or_exists": ok
    })))
}
