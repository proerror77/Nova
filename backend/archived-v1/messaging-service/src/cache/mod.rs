use crate::redis_client::RedisClient;
use redis::RedisResult;

pub async fn new_redis_client(url: &str) -> RedisResult<RedisClient> {
    RedisClient::from_url(url).await
}
