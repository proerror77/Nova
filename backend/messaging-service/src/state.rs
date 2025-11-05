use crate::{
    config::Config,
    redis_client::RedisClient,
    services::{auth_client::AuthClient, encryption::EncryptionService, key_exchange::KeyExchangeService, push::ApnsPush},
    websocket::ConnectionRegistry,
};
use sqlx::{Pool, Postgres};
use std::sync::Arc;

#[derive(Clone)]
pub struct AppState {
    pub db: Pool<Postgres>,
    pub registry: ConnectionRegistry,
    pub redis: RedisClient,
    pub config: Arc<Config>,
    pub apns: Option<Arc<ApnsPush>>,
    pub encryption: Arc<EncryptionService>,
    pub key_exchange_service: Option<Arc<KeyExchangeService>>,
    // Phase 1: Spec 007 - Auth service client for user consolidation
    pub auth_client: Arc<AuthClient>,
}
