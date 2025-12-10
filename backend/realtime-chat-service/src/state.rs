use crate::{
    config::Config,
    redis_client::RedisClient,
    services::{
        encryption::EncryptionService, graph_client::GraphClient, key_exchange::KeyExchangeService,
        matrix_client::MatrixClient, MegolmService, OlmService,
    },
    websocket::ConnectionRegistry,
};
use grpc_clients::AuthClient;
use deadpool_postgres::Pool;
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub db: Pool,
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
    /// Matrix client for E2EE messaging (optional, when MATRIX_ENABLED=true)
    pub matrix_client: Option<Arc<MatrixClient>>,
    /// Graph client for block/follow operations via graph-service
    pub graph_client: Option<Arc<GraphClient>>,
}
