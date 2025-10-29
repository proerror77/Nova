use crate::{
    config::Config,
    services::{encryption::EncryptionService, push::ApnsPush},
    websocket::ConnectionRegistry,
};
use redis::Client as RedisClient;
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
}
