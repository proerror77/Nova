//! Passkey (WebAuthn) database operations

use crate::error::{IdentityError, Result};
use crate::models::{CreatePasskeyCredential, PasskeyCredential};
use chrono::Utc;
use sqlx::PgPool;
use uuid::Uuid;

/// Find passkey credential by credential ID (base64 encoded)
pub async fn find_by_credential_id(
    pool: &PgPool,
    credential_id_base64: &str,
) -> Result<Option<PasskeyCredential>> {
    let credential = sqlx::query_as::<_, PasskeyCredential>(
        "SELECT * FROM passkey_credentials WHERE credential_id_base64 = $1 AND is_active = TRUE",
    )
    .bind(credential_id_base64)
    .fetch_optional(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(credential)
}

/// Find passkey credential by raw credential ID bytes
pub async fn find_by_credential_id_bytes(
    pool: &PgPool,
    credential_id: &[u8],
) -> Result<Option<PasskeyCredential>> {
    let credential = sqlx::query_as::<_, PasskeyCredential>(
        "SELECT * FROM passkey_credentials WHERE credential_id = $1 AND is_active = TRUE",
    )
    .bind(credential_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(credential)
}

/// Find all active passkey credentials for a user
pub async fn find_by_user_id(pool: &PgPool, user_id: Uuid) -> Result<Vec<PasskeyCredential>> {
    let credentials = sqlx::query_as::<_, PasskeyCredential>(
        "SELECT * FROM passkey_credentials WHERE user_id = $1 AND is_active = TRUE ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(credentials)
}

/// Find all passkey credentials for a user (including revoked)
pub async fn find_all_by_user_id(pool: &PgPool, user_id: Uuid) -> Result<Vec<PasskeyCredential>> {
    let credentials = sqlx::query_as::<_, PasskeyCredential>(
        "SELECT * FROM passkey_credentials WHERE user_id = $1 ORDER BY created_at DESC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(credentials)
}

/// Create a new passkey credential
pub async fn create_credential(
    pool: &PgPool,
    data: &CreatePasskeyCredential,
) -> Result<PasskeyCredential> {
    let credential = sqlx::query_as::<_, PasskeyCredential>(
        r#"
        INSERT INTO passkey_credentials
        (user_id, credential_id, credential_id_base64, public_key, credential_name, aaguid,
         sign_count, backup_eligible, backup_state, transports, device_type, os_version)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
        RETURNING *
        "#,
    )
    .bind(data.user_id)
    .bind(&data.credential_id)
    .bind(&data.credential_id_base64)
    .bind(&data.public_key)
    .bind(&data.credential_name)
    .bind(&data.aaguid)
    .bind(data.sign_count)
    .bind(data.backup_eligible)
    .bind(data.backup_state)
    .bind(&data.transports)
    .bind(&data.device_type)
    .bind(&data.os_version)
    .fetch_one(pool)
    .await
    .map_err(|e| {
        if e.to_string().contains("unique constraint") {
            IdentityError::PasskeyAlreadyRegistered
        } else {
            IdentityError::Database(e.to_string())
        }
    })?;

    Ok(credential)
}

/// Update sign count and last_used_at after successful authentication
pub async fn update_sign_count(
    pool: &PgPool,
    credential_id: Uuid,
    new_sign_count: i64,
) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE passkey_credentials
        SET sign_count = $1, last_used_at = $2, updated_at = $2
        WHERE id = $3
        "#,
    )
    .bind(new_sign_count)
    .bind(Utc::now())
    .bind(credential_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(())
}

/// Update backup state flags
pub async fn update_backup_state(
    pool: &PgPool,
    credential_id: Uuid,
    backup_eligible: bool,
    backup_state: bool,
) -> Result<()> {
    sqlx::query(
        r#"
        UPDATE passkey_credentials
        SET backup_eligible = $1, backup_state = $2, updated_at = NOW()
        WHERE id = $3
        "#,
    )
    .bind(backup_eligible)
    .bind(backup_state)
    .bind(credential_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(())
}

/// Update credential name
pub async fn update_credential_name(
    pool: &PgPool,
    credential_id: Uuid,
    user_id: Uuid,
    credential_name: &str,
) -> Result<()> {
    let result = sqlx::query(
        r#"
        UPDATE passkey_credentials
        SET credential_name = $1, updated_at = NOW()
        WHERE id = $2 AND user_id = $3
        "#,
    )
    .bind(credential_name)
    .bind(credential_id)
    .bind(user_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    if result.rows_affected() == 0 {
        return Err(IdentityError::PasskeyCredentialNotFound);
    }

    Ok(())
}

/// Revoke a passkey credential
pub async fn revoke_credential(
    pool: &PgPool,
    credential_id: Uuid,
    user_id: Uuid,
    reason: Option<&str>,
) -> Result<()> {
    let result = sqlx::query(
        r#"
        UPDATE passkey_credentials
        SET is_active = FALSE, revoked_at = NOW(), revoke_reason = $1, updated_at = NOW()
        WHERE id = $2 AND user_id = $3 AND is_active = TRUE
        "#,
    )
    .bind(reason)
    .bind(credential_id)
    .bind(user_id)
    .execute(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    if result.rows_affected() == 0 {
        return Err(IdentityError::PasskeyCredentialNotFound);
    }

    Ok(())
}

/// Delete a passkey credential (hard delete)
pub async fn delete_credential(pool: &PgPool, credential_id: Uuid, user_id: Uuid) -> Result<()> {
    let result = sqlx::query("DELETE FROM passkey_credentials WHERE id = $1 AND user_id = $2")
        .bind(credential_id)
        .bind(user_id)
        .execute(pool)
        .await
        .map_err(|e| IdentityError::Database(e.to_string()))?;

    if result.rows_affected() == 0 {
        return Err(IdentityError::PasskeyCredentialNotFound);
    }

    Ok(())
}

/// Check if user has any active passkey credentials
pub async fn has_passkey_credentials(pool: &PgPool, user_id: Uuid) -> Result<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM passkey_credentials WHERE user_id = $1 AND is_active = TRUE)",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(exists)
}

/// Count active passkey credentials for a user
pub async fn count_credentials(pool: &PgPool, user_id: Uuid) -> Result<i64> {
    let count = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM passkey_credentials WHERE user_id = $1 AND is_active = TRUE",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(count)
}

/// Check if credential ID already exists (for preventing duplicate registration)
pub async fn credential_exists(pool: &PgPool, credential_id_base64: &str) -> Result<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM passkey_credentials WHERE credential_id_base64 = $1)",
    )
    .bind(credential_id_base64)
    .fetch_one(pool)
    .await
    .map_err(|e| IdentityError::Database(e.to_string()))?;

    Ok(exists)
}
