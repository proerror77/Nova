use crate::{
    config::Config,
    redis_client::RedisClient,
    services::{
        encryption::EncryptionService, key_exchange::KeyExchangeService, MegolmService, OlmService,
    },
    websocket::ConnectionRegistry,
};
use grpc_clients::AuthClient;
use sqlx::{Pool, Postgres};
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub db: Pool<Postgres>,
    pub registry: ConnectionRegistry,
    pub redis: RedisClient,
    pub config: Arc<Config>,
    pub encryption: Arc<EncryptionService>,
    pub key_exchange_service: Option<Arc<KeyExchangeService>>,
    pub auth_client: Arc<AuthClient>,
    /// Olm service for 1:1 E2EE (vodozemac Double Ratchet)
    pub olm_service: Option<Arc<OlmService>>,
    /// Megolm service for group E2EE (vodozemac symmetric ratchet)
    pub megolm_service: Option<Arc<MegolmService>>,
}
