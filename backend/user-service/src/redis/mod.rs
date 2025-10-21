/// Redis utilities and operations
/// Centralizes all Redis interactions to eliminate duplication
pub mod operations;
pub mod keys;

pub use operations::{
    redis_set_ex, redis_get, redis_delete, redis_exists,
    redis_incr, redis_expire,
};
pub use keys::{
    EmailVerificationKey, PasswordResetKey, TokenRevocationKey,
    FeedCacheKey, RedisKeyBuilder,
};
