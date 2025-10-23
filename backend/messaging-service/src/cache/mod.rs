use redis::Client;

pub fn new_redis_client(url: &str) -> Result<Client, redis::RedisError> {
    // To be implemented: create client and possibly establish a connection for health check
    Client::open(url)
}

