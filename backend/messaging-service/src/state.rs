use sqlx::{Pool, Postgres};
use crate::websocket::ConnectionRegistry;
use redis::Client as RedisClient;

#[derive(Clone)]
pub struct AppState {
    pub db: Pool<Postgres>,
    pub registry: ConnectionRegistry,
    pub redis: RedisClient,
}
