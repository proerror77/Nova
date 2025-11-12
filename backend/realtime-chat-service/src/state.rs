use crate::{
    config::Config,
    redis_client::RedisClient,
    services::{encryption::EncryptionService, key_exchange::KeyExchangeService},
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
}
