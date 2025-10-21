/// 备用码管理服务
/// 用于 2FA 账户恢复 (当 Authenticator 应用丢失时)
use anyhow::{Context, Result};
use chrono::Utc;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use uuid::Uuid;

/// 生成 10 个备用码并存储到数据库
///
/// # 参数
/// - `pool`: PostgreSQL 连接池
/// - `user_id`: 用户 ID
///
/// # 返回
/// 10 个明文备用码 (仅此一次返回给用户保存)
/// 数据库中存储的是 SHA256 哈希
///
/// # 注意
/// 明文码不会再次返回给用户，所以用户必须立即保存
pub async fn generate_backup_codes(pool: &PgPool, user_id: Uuid) -> Result<Vec<String>> {
    // 1. 生成 10 个备用码
    let codes = crate::security::TOTPGenerator::generate_backup_codes();

    // 2. 删除用户的旧备用码
    sqlx::query(
        r#"
        DELETE FROM two_fa_backup_codes
        WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await
    .context("Failed to delete old backup codes")?;

    // 3. 计算哈希并存储新的备用码
    let now = Utc::now();
    for code in &codes {
        let code_hash = hash_code(code);
        sqlx::query(
            r#"
            INSERT INTO two_fa_backup_codes (id, user_id, code_hash, is_used, created_at)
            VALUES ($1, $2, $3, FALSE, $4)
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(code_hash)
        .bind(now)
        .execute(pool)
        .await
        .context("Failed to insert backup code")?;
    }

    Ok(codes)
}

/// 验证备用码并标记为已使用
///
/// # 参数
/// - `pool`: PostgreSQL 连接池
/// - `user_id`: 用户 ID
/// - `code`: 用户输入的备用码
///
/// # 返回
/// true 如果备用码有效且未使用过
pub async fn verify_backup_code(pool: &PgPool, user_id: Uuid, code: &str) -> Result<bool> {
    // 1. 校验码格式: 8 位十六进制
    if code.len() != 8 || !code.chars().all(|c| c.is_ascii_hexdigit()) {
        return Ok(false);
    }

    // 2. 计算码的 SHA256 哈希
    let code_hash = hash_code(code);

    // 3. 查询未使用的备用码
    let record = sqlx::query_as::<_, (Uuid, bool)>(
        r#"
        SELECT id, is_used FROM two_fa_backup_codes
        WHERE user_id = $1 AND code_hash = $2
        "#,
    )
    .bind(user_id)
    .bind(code_hash)
    .fetch_optional(pool)
    .await
    .context("Failed to query backup code")?;

    let (record_id, is_used) = match record {
        Some(r) => r,
        None => return Ok(false), // 码不存在或不属于此用户
    };

    // 4. 检查是否已使用
    if is_used {
        return Ok(false);
    }

    // 5. 标记为已使用
    sqlx::query(
        r#"
        UPDATE two_fa_backup_codes
        SET is_used = TRUE, used_at = NOW()
        WHERE id = $1
        "#,
    )
    .bind(record_id)
    .execute(pool)
    .await
    .context("Failed to mark backup code as used")?;

    Ok(true)
}

/// 获取用户未使用的备用码数量
///
/// # 参数
/// - `pool`: PostgreSQL 连接池
/// - `user_id`: 用户 ID
///
/// # 返回
/// 未使用的备用码数量
pub async fn count_unused_backup_codes(pool: &PgPool, user_id: Uuid) -> Result<i64> {
    let result = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM two_fa_backup_codes
        WHERE user_id = $1 AND is_used = FALSE
        "#,
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .context("Failed to count unused backup codes")?;

    Ok(result)
}

/// 存储预生成的备用码 (2FA 确认时使用)
///
/// # 参数
/// - `pool`: PostgreSQL 连接池
/// - `user_id`: 用户 ID
/// - `codes`: 备用码列表 (明文)
///
/// # 返回
/// Ok 如果所有码都存储成功
pub async fn store_backup_codes(pool: &PgPool, user_id: Uuid, codes: &[String]) -> Result<()> {
    // 1. 删除用户的旧备用码
    sqlx::query(
        r#"
        DELETE FROM two_fa_backup_codes
        WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await
    .context("Failed to delete old backup codes")?;

    // 2. 计算哈希并存储新的备用码
    let now = Utc::now();
    for code in codes {
        let code_hash = hash_code(code);
        sqlx::query(
            r#"
            INSERT INTO two_fa_backup_codes (id, user_id, code_hash, is_used, created_at)
            VALUES ($1, $2, $3, FALSE, $4)
            "#,
        )
        .bind(Uuid::new_v4())
        .bind(user_id)
        .bind(code_hash)
        .bind(now)
        .execute(pool)
        .await
        .context("Failed to insert backup code")?;
    }

    Ok(())
}

/// 撤销所有备用码 (用户禁用 2FA 时)
///
/// # 参数
/// - `pool`: PostgreSQL 连接池
/// - `user_id`: 用户 ID
pub async fn revoke_backup_codes(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query(
        r#"
        DELETE FROM two_fa_backup_codes
        WHERE user_id = $1
        "#,
    )
    .bind(user_id)
    .execute(pool)
    .await
    .context("Failed to revoke backup codes")?;

    Ok(())
}

/// 计算备用码的 SHA256 哈希 (常定时间)
///
/// # 参数
/// - `code`: 备用码
///
/// # 返回
/// 64 字符十六进制 SHA256 哈希
fn hash_code(code: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(code.as_bytes());
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_code() {
        let code = "a1b2c3d4";
        let hash = hash_code(code);
        assert_eq!(hash.len(), 64);
        assert!(hash.chars().all(|c| c.is_ascii_hexdigit()));
        // 哈希应该是确定性的
        let hash2 = hash_code(code);
        assert_eq!(hash, hash2);
    }

    #[test]
    fn test_hash_different_codes() {
        let hash1 = hash_code("a1b2c3d4");
        let hash2 = hash_code("e5f6g7h8");
        assert_ne!(hash1, hash2);
    }
}
