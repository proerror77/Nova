/// JWT密钥轮换服务
/// 管理JWT签名密钥的生命周期、轮换和验证
use anyhow::{anyhow, Context, Result};
use chrono::{Duration, Utc};
use sqlx::PgPool;
use uuid::Uuid;

/// JWT密钥信息
#[derive(Debug, Clone)]
pub struct JwtKey {
    pub key_id: String,
    pub version: i32,
    pub public_key_pem: String,
    pub algorithm: String,
    pub is_active: bool,
    pub activated_at: Option<chrono::DateTime<chrono::Utc>>,
    pub rotated_at: Option<chrono::DateTime<chrono::Utc>>,
    pub expires_at: Option<chrono::DateTime<chrono::Utc>>,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// 获取当前活跃的JWT密钥
///
/// # 参数
/// - `pool`: PostgreSQL连接池
///
/// # 返回
/// 当前活跃的JWT密钥
pub async fn get_active_key(pool: &PgPool) -> Result<JwtKey> {
    let key = sqlx::query_as::<_, (String, i32, String, String, bool, Option<chrono::DateTime<chrono::Utc>>, Option<chrono::DateTime<chrono::Utc>>, Option<chrono::DateTime<chrono::Utc>>, chrono::DateTime<chrono::Utc>)>(
        r#"
        SELECT key_id, version, public_key_pem, algorithm, is_active, activated_at, rotated_at, expires_at, created_at
        FROM jwt_signing_keys
        WHERE is_active = TRUE
        ORDER BY activated_at DESC
        LIMIT 1
        "#,
    )
    .fetch_optional(pool)
    .await
    .context("Failed to query active JWT key")?
    .ok_or_else(|| anyhow!("No active JWT key found"))?;

    Ok(JwtKey {
        key_id: key.0,
        version: key.1,
        public_key_pem: key.2,
        algorithm: key.3,
        is_active: key.4,
        activated_at: key.5,
        rotated_at: key.6,
        expires_at: key.7,
        created_at: key.8,
    })
}

/// 获取所有有效的JWT密钥 (用于JWKS端点)
///
/// # 参数
/// - `pool`: PostgreSQL连接池
///
/// # 返回
/// 所有仍在有效期内的JWT密钥
pub async fn get_valid_keys(pool: &PgPool) -> Result<Vec<JwtKey>> {
    let now = Utc::now();

    let keys = sqlx::query_as::<_, (String, i32, String, String, bool, Option<chrono::DateTime<chrono::Utc>>, Option<chrono::DateTime<chrono::Utc>>, Option<chrono::DateTime<chrono::Utc>>, chrono::DateTime<chrono::Utc>)>(
        r#"
        SELECT key_id, version, public_key_pem, algorithm, is_active, activated_at, rotated_at, expires_at, created_at
        FROM jwt_signing_keys
        WHERE expires_at IS NULL OR expires_at > $1
        ORDER BY is_active DESC, activated_at DESC
        "#,
    )
    .bind(now)
    .fetch_all(pool)
    .await
    .context("Failed to query valid JWT keys")?;

    Ok(keys
        .into_iter()
        .map(|key| JwtKey {
            key_id: key.0,
            version: key.1,
            public_key_pem: key.2,
            algorithm: key.3,
            is_active: key.4,
            activated_at: key.5,
            rotated_at: key.6,
            expires_at: key.7,
            created_at: key.8,
        })
        .collect())
}

/// 将新密钥标记为活跃 (执行密钥轮换)
///
/// # 参数
/// - `pool`: PostgreSQL连接池
/// - `new_key_id`: 新密钥ID
/// - `grace_period_days`: 旧密钥的宽限期 (天数)
///
/// # 返回
/// Ok 如果轮换成功
pub async fn activate_key(pool: &PgPool, new_key_id: &str, grace_period_days: i64) -> Result<()> {
    let now = Utc::now();
    let expires_at = now + Duration::days(grace_period_days);

    let mut tx = pool.begin().await.context("Failed to begin transaction")?;

    // 1. 找到当前活跃的密钥
    let current_active: Option<String> =
        sqlx::query_scalar(r#"SELECT key_id FROM jwt_signing_keys WHERE is_active = TRUE"#)
            .fetch_optional(&mut *tx)
            .await
            .context("Failed to query current active key")?;

    // 2. 如果存在，标记为非活跃并设置过期时间
    if let Some(old_key_id) = current_active {
        sqlx::query(
            r#"
            UPDATE jwt_signing_keys
            SET is_active = FALSE, rotated_at = $1, expires_at = $2
            WHERE key_id = $3
            "#,
        )
        .bind(now)
        .bind(expires_at)
        .bind(&old_key_id)
        .execute(&mut *tx)
        .await
        .context("Failed to deactivate old key")?;
    }

    // 3. 激活新密钥
    sqlx::query(
        r#"
        UPDATE jwt_signing_keys
        SET is_active = TRUE, activated_at = $1
        WHERE key_id = $2
        "#,
    )
    .bind(now)
    .bind(new_key_id)
    .execute(&mut *tx)
    .await
    .context("Failed to activate new key")?;

    tx.commit().await.context("Failed to commit transaction")?;

    Ok(())
}

/// 清理过期的JWT密钥
///
/// # 参数
/// - `pool`: PostgreSQL连接池
///
/// # 返回
/// 被删除的密钥数量
pub async fn cleanup_expired_keys(pool: &PgPool) -> Result<i64> {
    let now = Utc::now();

    let result = sqlx::query(
        r#"
        DELETE FROM jwt_signing_keys
        WHERE expires_at IS NOT NULL AND expires_at < $1
        "#,
    )
    .bind(now)
    .execute(pool)
    .await
    .context("Failed to cleanup expired keys")?;

    Ok(result.rows_affected() as i64)
}

/// 存储新的JWT密钥
///
/// # 参数
/// - `pool`: PostgreSQL连接池
/// - `key_id`: 密钥ID
/// - `version`: 密钥版本
/// - `public_key_pem`: 公钥 (PEM格式)
/// - `algorithm`: 加密算法 (默认: RS256)
///
/// # 返回
/// Ok 如果存储成功
pub async fn store_key(
    pool: &PgPool,
    key_id: &str,
    version: i32,
    public_key_pem: &str,
    algorithm: &str,
) -> Result<()> {
    let now = Utc::now();

    sqlx::query(
        r#"
        INSERT INTO jwt_signing_keys (key_id, version, public_key_pem, algorithm, created_at, is_active, created_by)
        VALUES ($1, $2, $3, $4, $5, FALSE, 'system')
        ON CONFLICT (key_id) DO NOTHING
        "#,
    )
    .bind(key_id)
    .bind(version)
    .bind(public_key_pem)
    .bind(algorithm)
    .bind(now)
    .execute(pool)
    .await
    .context("Failed to store JWT key")?;

    Ok(())
}

/// 检查是否需要轮换 (简化设计: 仅返回是否可以轮换)
///
/// # 参数
/// - `pool`: PostgreSQL连接池
///
/// # 返回
/// 是否应该轮换密钥
pub async fn should_rotate(pool: &PgPool) -> Result<bool> {
    // 简化设计: 如果没有活跃密钥，则应该轮换
    let has_active = sqlx::query_scalar::<_, bool>(
        r#"SELECT EXISTS(SELECT 1 FROM jwt_signing_keys WHERE is_active = TRUE)"#,
    )
    .fetch_one(pool)
    .await
    .context("Failed to check active key")?;

    Ok(!has_active)
}

/// 根据配置检查并执行 JWT 密钥轮换
///
/// 如果当前没有活跃密钥，则生成新的密钥记录并激活。
/// 返回新激活的密钥 ID，如果无需轮换则返回 None。
pub async fn rotate_if_needed(
    pool: &PgPool,
    public_key_pem: &str,
    grace_period_days: i64,
) -> Result<Option<String>> {
    if !should_rotate(pool).await? {
        return Ok(None);
    }

    let next_version: i32 =
        sqlx::query_scalar(r#"SELECT COALESCE(MAX(version), 0) + 1 FROM jwt_signing_keys"#)
            .fetch_one(pool)
            .await
            .context("Failed to determine next JWT key version")?;

    let new_key_id = format!("jwt-key-{}", Uuid::new_v4());

    store_key(pool, &new_key_id, next_version, public_key_pem, "RS256").await?;
    activate_key(pool, &new_key_id, grace_period_days).await?;

    Ok(Some(new_key_id))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_structure() {
        // 验证JwtKey结构体可以创建
        let key = JwtKey {
            key_id: "test-key-id".to_string(),
            version: 1,
            public_key_pem: "test-pem".to_string(),
            algorithm: "RS256".to_string(),
            is_active: true,
            activated_at: Some(Utc::now()),
            rotated_at: None,
            expires_at: None,
            created_at: Utc::now(),
        };

        assert_eq!(key.key_id, "test-key-id");
        assert_eq!(key.version, 1);
        assert!(key.is_active);
    }

    #[test]
    fn test_grace_period_calculation() {
        let now = Utc::now();
        let grace_period_days = 7i64;
        let expires_at = now + Duration::days(grace_period_days);

        // 验证过期时间计算正确
        let duration = expires_at.signed_duration_since(now);
        assert!(
            duration.num_days() >= grace_period_days - 1
                && duration.num_days() <= grace_period_days + 1
        );
    }
}
