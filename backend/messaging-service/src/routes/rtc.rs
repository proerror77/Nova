use crate::state::AppState;
use axum::{extract::State, Json};
use serde::Serialize;

#[derive(Serialize)]
pub struct IceServerResponse {
    pub urls: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub credential: Option<String>,
    #[serde(rename = "credential_type", skip_serializing_if = "Option::is_none")]
    pub credential_type: Option<String>,
}

#[derive(Serialize)]
pub struct IceConfigResponse {
    pub ice_servers: Vec<IceServerResponse>,
    pub ttl_seconds: u32,
}

pub async fn get_ice_config(State(state): State<AppState>) -> Json<IceConfigResponse> {
    let response = IceConfigResponse {
        ice_servers: state
            .config
            .ice_servers
            .iter()
            .map(|server| IceServerResponse {
                urls: server.urls.clone(),
                username: server.username.clone(),
                credential: server.credential.clone(),
                credential_type: server.credential_type.clone(),
            })
            .collect(),
        ttl_seconds: state.config.ice_ttl_seconds,
    };

    Json(response)
}
