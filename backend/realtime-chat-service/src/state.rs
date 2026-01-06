use crate::{
    config::Config,
    redis_client::RedisClient,
    services::{
        graph_client::GraphClient, identity_client::IdentityClient,
        key_exchange::KeyExchangeService, matrix_admin::MatrixAdminClient, matrix_client::MatrixClient,
        notification_producer::NotificationProducer, MegolmService, OlmService,
    },
    websocket::ConnectionRegistry,
};
#[allow(deprecated)]
use crate::services::encryption::EncryptionService;
use grpc_clients::AuthClient;
use deadpool_postgres::Pool;
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub db: Pool,
    pub registry: ConnectionRegistry,
    pub redis: RedisClient,
    pub config: Arc<Config>,
    #[allow(deprecated)]
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
    /// Identity client for user settings (dm_permission) via identity-service
    /// P0: Single source of truth for dm_permission
    pub identity_client: Option<Arc<IdentityClient>>,
    /// Matrix Admin client for user provisioning (create users, generate login tokens)
    pub matrix_admin_client: Option<Arc<MatrixAdminClient>>,
    /// Kafka notification producer for sending message notifications
    pub notification_producer: Option<Arc<NotificationProducer>>,
}
