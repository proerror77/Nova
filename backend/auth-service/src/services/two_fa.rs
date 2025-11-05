use crate::error::{AuthError, AuthResult};
use crate::metrics::{record_two_fa_setup, record_two_fa_verification};
use crate::security::{token_revocation, TOTPGenerator};
use crate::services::KafkaEventProducer;
use redis_utils::SharedConnectionManager;
use sqlx::PgPool;
use uuid::Uuid;

const BACKUP_CODE_COUNT: usize = 8;

/// Two-factor authentication service (TOTP)
#[derive(Clone)]
pub struct TwoFaService {
    db: PgPool,
    redis: SharedConnectionManager,
    kafka: Option<KafkaEventProducer>,
}

/// Response payload for initiating 2FA setup
pub struct TwoFaSetup {
    pub secret: String,
    pub provisioning_uri: String,
    pub backup_codes: Vec<String>,
}

impl TwoFaService {
    pub fn new(
        db: PgPool,
        redis: SharedConnectionManager,
        kafka: Option<KafkaEventProducer>,
    ) -> Self {
        Self { db, redis, kafka }
    }

    /// Begin TOTP enrollment for a user. Generates secret + backup codes and stores secret.
    pub async fn initiate(&self, user_id: Uuid, email: &str) -> AuthResult<TwoFaSetup> {
        let timer = std::time::Instant::now();
        let (secret, provisioning_uri) = TOTPGenerator::generate_secret_and_uri(email)?;

        crate::db::users::enable_totp(&self.db, user_id, &secret).await?;

        let backup_codes = Self::generate_backup_codes();
        self.persist_backup_codes(user_id, &backup_codes).await?;

        record_two_fa_setup("enable", true, timer.elapsed().as_millis() as u64);

        Ok(TwoFaSetup {
            secret,
            provisioning_uri,
            backup_codes,
        })
    }

    /// Confirm TOTP by verifying the provided code.
    pub async fn confirm(&self, user_id: Uuid, code: &str) -> AuthResult<()> {
        let timer = std::time::Instant::now();
        let user = crate::db::users::find_by_id(&self.db, user_id)
            .await?
            .ok_or(AuthError::UserNotFound)?;

        let secret = user.totp_secret.ok_or(AuthError::TwoFANotEnabled)?;

        let verification = TOTPGenerator::verify_code(&secret, code)?;

        if verification {
            crate::db::users::verify_totp(&self.db, user_id).await?;
            token_revocation::revoke_all_user_tokens(&self.redis, user_id).await?;
            if let Some(producer) = &self.kafka {
                if let Err(err) = producer.publish_two_fa_enabled(user_id).await {
                    tracing::warn!("Failed to publish 2FA enabled event: {:?}", err);
                }
            }
            record_two_fa_setup("confirm", true, timer.elapsed().as_millis() as u64);
            record_two_fa_verification(true);
            Ok(())
        } else {
            record_two_fa_setup("confirm", false, timer.elapsed().as_millis() as u64);
            record_two_fa_verification(false);
            Err(AuthError::InvalidTwoFACode)
        }
    }

    /// Disable TOTP for a user.
    pub async fn disable(&self, user_id: Uuid) -> AuthResult<()> {
        crate::db::users::disable_totp(&self.db, user_id).await?;
        self.clear_backup_codes(user_id).await?;
        token_revocation::revoke_all_user_tokens(&self.redis, user_id).await?;
        Ok(())
    }

    /// Verify backup code (one-time use). Returns true if consumed.
    pub async fn consume_backup_code(&self, user_id: Uuid, code: &str) -> AuthResult<bool> {
        let hashed = Self::hash_backup_code(code);
        let key = backup_codes_key(user_id);
        let mut conn = self.redis.lock().await.clone();
        let removed: i32 = redis::cmd("SREM")
            .arg(&key)
            .arg(&hashed)
            .query_async(&mut conn)
            .await
            .map_err(|e| AuthError::Redis(e.to_string()))?;

        if removed > 0 {
            record_two_fa_verification(true);
            Ok(true)
        } else {
            record_two_fa_verification(false);
            Ok(false)
        }
    }

    fn generate_backup_codes() -> Vec<String> {
        TOTPGenerator::generate_backup_codes()
            .into_iter()
            .take(BACKUP_CODE_COUNT)
            .collect()
    }

    async fn persist_backup_codes(&self, user_id: Uuid, codes: &[String]) -> AuthResult<()> {
        let key = backup_codes_key(user_id);
        let mut conn = self.redis.lock().await.clone();

        // Reset the set then insert hashed codes
        redis::cmd("DEL")
            .arg(&key)
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| AuthError::Redis(e.to_string()))?;

        for code in codes {
            let hashed = Self::hash_backup_code(code);
            redis::cmd("SADD")
                .arg(&key)
                .arg(&hashed)
                .query_async::<_, ()>(&mut conn)
                .await
                .map_err(|e| AuthError::Redis(e.to_string()))?;
        }

        // Backup codes never expire until disabled
        Ok(())
    }

    async fn clear_backup_codes(&self, user_id: Uuid) -> AuthResult<()> {
        let key = backup_codes_key(user_id);
        let mut conn = self.redis.lock().await.clone();
        redis::cmd("DEL")
            .arg(&key)
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| AuthError::Redis(e.to_string()))?;
        Ok(())
    }

    fn hash_backup_code(code: &str) -> String {
        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(code.as_bytes());
        hex::encode(hasher.finalize())
    }
}

fn backup_codes_key(user_id: Uuid) -> String {
    format!("nova:2fa:backup_codes:{user_id}")
}
