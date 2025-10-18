/// 双因素认证 (2FA) 服务
/// 处理 TOTP 和备用码的验证逻辑
use anyhow::{anyhow, Result};
use sqlx::PgPool;
use std::convert::TryFrom;
use uuid::Uuid;

use crate::security::TOTPGenerator;
use crate::services::backup_codes;

/// 统一验证用户代码 (TOTP 或备用码)
///
/// # 参数
/// - `pool`: 数据库连接
/// - `user_id`: 用户 ID
/// - `code`: 用户输入的代码 (6位数字 TOTP 或 8位十六进制备用码)
///
/// # 返回
/// true 如果验证成功，false 如果验证失败或代码无效
pub async fn verify_user_code(pool: &PgPool, user_id: Uuid, code: &str) -> Result<bool> {
    // 1. 获取用户的 TOTP secret
    let totp_secret: Option<String> =
        sqlx::query_scalar("SELECT totp_secret FROM users WHERE id = $1 AND totp_enabled = true")
            .bind(user_id)
            .fetch_optional(pool)
            .await?;

    let totp_secret = match totp_secret {
        Some(s) => s,
        None => return Err(anyhow!("2FA not enabled for user")),
    };

    // 2. 尝试验证为 TOTP 码 (6位数字)
    if code.len() == 6 && code.chars().all(|c| c.is_ascii_digit()) {
        return TOTPGenerator::verify_totp(&totp_secret, code);
    }

    // 3. 尝试验证为备用码 (8位十六进制)
    if code.len() == 8 && code.chars().all(|c| c.is_ascii_hexdigit()) {
        return backup_codes::verify_backup_code(pool, user_id, code).await;
    }

    // 4. 代码格式无效
    Ok(false)
}

/// 生成 2FA 初始化信息 (用于启用 2FA)
///
/// # 返回
/// (secret_base32, provisioning_uri, backup_codes)
pub async fn generate_2fa_setup(email: &str) -> Result<(String, String, Vec<String>)> {
    // 1. 生成 TOTP secret
    let secret = TOTPGenerator::generate_secret()?;

    // 2. 生成 provisioning URI
    let uri = TOTPGenerator::generate_provisioning_uri(email, &secret, "Nova");

    // 3. 生成备用码
    let backup_codes = TOTPGenerator::generate_backup_codes();

    Ok((secret, uri, backup_codes))
}

/// 验证临时 2FA session 是否有效
///
/// # 参数
/// - `redis`: Redis 连接管理器
/// - `session_id`: 临时 session ID
/// - `session_type`: Session 类型 ("2fa_pending" 或 "2fa_setup")
///
/// # 返回
/// Ok(user_id) 如果 session 有效, Err 如果无效或过期
pub async fn verify_temp_session(
    redis: &redis::aio::ConnectionManager,
    session_id: &str,
    session_type: &str,
) -> Result<Uuid> {
    use redis::AsyncCommands;

    let key = format!("{}:{}", session_type, session_id);
    let mut redis_conn = redis.clone();
    let user_id_str: Option<String> = redis_conn.get(&key).await?;

    match user_id_str {
        Some(uid) => Ok(Uuid::parse_str(&uid)?),
        None => Err(anyhow!("Session expired or invalid")),
    }
}

/// 存储临时 2FA session
///
/// # 参数
/// - `redis`: Redis 连接管理器
/// - `session_id`: Session ID (通常是 UUID)
/// - `user_id`: 用户 ID
/// - `session_type`: Session 类型
/// - `ttl_secs`: TTL (秒)
pub async fn store_temp_session(
    redis: &redis::aio::ConnectionManager,
    session_id: &str,
    user_id: Uuid,
    session_type: &str,
    ttl_secs: usize,
) -> Result<()> {
    use redis::AsyncCommands;

    let key = format!("{}:{}", session_type, session_id);
    let mut redis_conn = redis.clone();
    let ttl_u64 = u64::try_from(ttl_secs)
        .map_err(|_| anyhow!("TTL value {} does not fit into u64", ttl_secs))?;
    let _: () = redis_conn
        .set_ex(&key, user_id.to_string(), ttl_u64)
        .await?;

    Ok(())
}

/// 删除临时 2FA session
pub async fn delete_temp_session(
    redis: &redis::aio::ConnectionManager,
    session_id: &str,
    session_type: &str,
) -> Result<()> {
    use redis::AsyncCommands;

    let key = format!("{}:{}", session_type, session_id);
    let mut redis_conn = redis.clone();
    let _: () = redis_conn.del(&key).await?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_2fa_setup() {
        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(async {
            let result = generate_2fa_setup("test@example.com").await;
            assert!(result.is_ok());
            let (secret, uri, codes) = result.unwrap();
            assert!(!secret.is_empty());
            assert!(uri.contains("otpauth://totp"));
            assert_eq!(codes.len(), 10);
        });
    }
}
