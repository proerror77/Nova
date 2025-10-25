/// 备用码管理服务
/// 用于 2FA 账户恢复 (当 Authenticator 应用丢失时)
use anyhow::{anyhow, Context, Result};
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use argon2::password_hash::SaltString;
use rand::rngs::OsRng;

/// CRITICAL FIX: Use Argon2 for secure backup code hashing
/// SHA256 is not sufficient for security-sensitive operations like 2FA recovery codes.
/// Argon2 provides key stretching and is resistant to GPU/ASIC attacks.

/// Generate 10 backup codes and store to database
///
/// # Parameters
/// - `pool`: PostgreSQL connection pool
/// - `user_id`: user ID
///
/// # Returns
/// 10 plaintext backup codes (only returned once)
/// Database stores Argon2 hash
///
/// # Note
/// Plaintext codes are not returned again, so user must save immediately
pub async fn generate_backup_codes(pool: &PgPool, user_id: Uuid) -> Result<Vec<String>> {
    // 1. Generate 10 backup codes
    let codes = crate::security::TOTPGenerator::generate_backup_codes();

    // 2. Delete old backup codes
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

    // 3. Hash with Argon2 and store new codes
    let now = Utc::now();
    for code in &codes {
        let code_hash = hash_backup_code(code).context("Failed to hash backup code")?;
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

    tracing::info!("Generated 10 new backup codes for user: {}", user_id);
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
    // 1. Validate code format: 8 hex digits
    if code.len() != 8 || !code.chars().all(|c| c.is_ascii_hexdigit()) {
        return Ok(false);
    }

    // 2. Query unused backup codes
    let record = sqlx::query_as::<_, (Uuid, String, bool)>(
        r#"
        SELECT id, code_hash, is_used FROM two_fa_backup_codes
        WHERE user_id = $1 AND is_used = FALSE
        "#,
    )
    .bind(user_id)
    .fetch_optional(pool)
    .await
    .context("Failed to query backup codes")?;

    let (record_id, code_hash, _is_used) = match record {
        Some(r) => r,
        None => return Ok(false), // No unused codes found
    };

    // 3. Verify code against stored Argon2 hash
    let password_hash = match PasswordHash::new(&code_hash) {
        Ok(hash) => hash,
        Err(_) => return Ok(false), // Invalid hash format stored
    };

    let is_valid = Argon2::default()
        .verify_password(code.as_bytes(), &password_hash)
        .is_ok();

    if !is_valid {
        return Ok(false);
    }

    // 4. Mark as used
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

    tracing::info!("Backup code used successfully for user: {}", user_id);
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
    // 1. Delete old backup codes
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

    // 2. Hash with Argon2 and store new codes
    let now = Utc::now();
    for code in codes {
        let code_hash = hash_backup_code(code).context("Failed to hash backup code")?;
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

    tracing::info!("Stored {} backup codes for user: {}", codes.len(), user_id);
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

/// Hash backup code using Argon2 (memory-hard KDF resistant to GPU attacks)
///
/// Argon2 is the winner of the Password Hashing Competition and provides:
/// - Memory-hard computation resistant to GPU/ASIC attacks
/// - Time cost parameter for adaptive hashing
/// - Per-code unique salt for protection against rainbow tables
///
/// # Parameters
/// - `code`: backup code to hash
///
/// # Returns
/// Argon2 PHC string format hash (includes algorithm, parameters, salt, and hash)
fn hash_backup_code(code: &str) -> Result<String> {
    // Generate random salt for this code
    let salt = SaltString::generate(&mut OsRng);

    // Use Argon2 with default parameters (Argon2id variant)
    // This provides good security without excessive computation time
    let argon2 = Argon2::default();

    // Hash the backup code
    let password_hash = argon2
        .hash_password(code.as_bytes(), &salt)
        .map_err(|e| anyhow!("Failed to hash backup code: {}", e))?;

    Ok(password_hash.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_backup_code_success() {
        let code = "a1b2c3d4";
        let result = hash_backup_code(code);
        assert!(result.is_ok());

        let hash = result.unwrap();
        // Argon2 hashes are in PHC format: $argon2id$v=19$m=19456,t=2,p=1$...
        assert!(hash.starts_with("$argon2"));
        assert!(hash.len() > 50); // Argon2 hashes are longer due to salt encoding
    }

    #[test]
    fn test_hash_backup_code_different_codes_different_hashes() {
        let code1 = "a1b2c3d4";
        let code2 = "e5f6g7h8";

        let hash1 = hash_backup_code(code1).unwrap();
        let hash2 = hash_backup_code(code2).unwrap();

        // Different codes should produce different hashes
        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_hash_backup_code_verification() {
        let code = "a1b2c3d4";
        let hash = hash_backup_code(code).unwrap();

        // Verify the hash is in correct format
        assert!(hash.starts_with("$argon2"));

        // Try to parse it as a PasswordHash (this is what verify_backup_code does)
        let password_hash = PasswordHash::new(&hash);
        assert!(password_hash.is_ok());

        // Verify the code against the hash
        let password_hash = password_hash.unwrap();
        let is_valid = Argon2::default()
            .verify_password(code.as_bytes(), &password_hash)
            .is_ok();
        assert!(is_valid);
    }

    #[test]
    fn test_hash_backup_code_rejects_wrong_code() {
        let code = "a1b2c3d4";
        let wrong_code = "ffffffff";

        let hash = hash_backup_code(code).unwrap();
        let password_hash = PasswordHash::new(&hash).unwrap();

        // Wrong code should not verify
        let is_valid = Argon2::default()
            .verify_password(wrong_code.as_bytes(), &password_hash)
            .is_ok();
        assert!(!is_valid);
    }
}
