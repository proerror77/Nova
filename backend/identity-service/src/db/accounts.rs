/// Alias accounts database operations for identity-service
/// Handles CRUD operations for user alias (sub) accounts
use crate::error::{IdentityError, Result};
use crate::models::user::Gender;
use chrono::{DateTime, NaiveDate, Utc};
use sqlx::PgPool;
use uuid::Uuid;

/// Alias account database record
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct AliasAccountRecord {
    pub id: Uuid,
    pub user_id: Uuid,
    pub alias_name: String,
    pub avatar_url: Option<String>,
    pub date_of_birth: Option<NaiveDate>,
    pub gender: Option<Gender>,
    pub profession: Option<String>,
    pub location: Option<String>,
    pub is_active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub deleted_at: Option<DateTime<Utc>>,
}

/// Fields for creating an alias account
#[derive(Debug)]
pub struct CreateAliasAccountFields {
    pub user_id: Uuid,
    pub alias_name: String,
    pub avatar_url: Option<String>,
    pub date_of_birth: Option<NaiveDate>,
    pub gender: Option<Gender>,
    pub profession: Option<String>,
    pub location: Option<String>,
}

/// Fields for updating an alias account
#[derive(Debug, Default)]
pub struct UpdateAliasAccountFields {
    pub alias_name: Option<String>,
    pub avatar_url: Option<String>,
    pub date_of_birth: Option<NaiveDate>,
    pub gender: Option<Gender>,
    pub profession: Option<String>,
    pub location: Option<String>,
}

/// Maximum number of alias accounts per user
pub const MAX_ALIAS_ACCOUNTS_PER_USER: i64 = 5;

/// Create a new alias account
pub async fn create_alias_account(
    pool: &PgPool,
    fields: CreateAliasAccountFields,
) -> Result<AliasAccountRecord> {
    // Check if user has reached the limit
    let count = count_alias_accounts(pool, fields.user_id).await?;
    if count >= MAX_ALIAS_ACCOUNTS_PER_USER {
        return Err(IdentityError::Validation(format!(
            "Maximum {} alias accounts allowed per user",
            MAX_ALIAS_ACCOUNTS_PER_USER
        )));
    }

    let record = sqlx::query_as::<_, AliasAccountRecord>(
        r#"
        INSERT INTO alias_accounts (user_id, alias_name, avatar_url, date_of_birth, gender, profession, location)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        RETURNING *
        "#,
    )
    .bind(fields.user_id)
    .bind(&fields.alias_name)
    .bind(&fields.avatar_url)
    .bind(fields.date_of_birth)
    .bind(fields.gender.as_ref().map(|g| g.as_str()))
    .bind(&fields.profession)
    .bind(&fields.location)
    .fetch_one(pool)
    .await?;

    Ok(record)
}

/// Get alias account by ID (excluding soft-deleted)
pub async fn find_by_id(pool: &PgPool, account_id: Uuid) -> Result<Option<AliasAccountRecord>> {
    let record = sqlx::query_as::<_, AliasAccountRecord>(
        "SELECT * FROM alias_accounts WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(account_id)
    .fetch_optional(pool)
    .await?;

    Ok(record)
}

/// Get alias account by ID and verify ownership
pub async fn find_by_id_and_user(
    pool: &PgPool,
    account_id: Uuid,
    user_id: Uuid,
) -> Result<Option<AliasAccountRecord>> {
    let record = sqlx::query_as::<_, AliasAccountRecord>(
        "SELECT * FROM alias_accounts WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
    )
    .bind(account_id)
    .bind(user_id)
    .fetch_optional(pool)
    .await?;

    Ok(record)
}

/// List all alias accounts for a user (excluding soft-deleted)
pub async fn list_by_user(pool: &PgPool, user_id: Uuid) -> Result<Vec<AliasAccountRecord>> {
    let records = sqlx::query_as::<_, AliasAccountRecord>(
        "SELECT * FROM alias_accounts WHERE user_id = $1 AND deleted_at IS NULL ORDER BY created_at ASC",
    )
    .bind(user_id)
    .fetch_all(pool)
    .await?;

    Ok(records)
}

/// Count alias accounts for a user
pub async fn count_alias_accounts(pool: &PgPool, user_id: Uuid) -> Result<i64> {
    let count: (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM alias_accounts WHERE user_id = $1 AND deleted_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(pool)
    .await?;

    Ok(count.0)
}

/// Update an alias account
pub async fn update_alias_account(
    pool: &PgPool,
    account_id: Uuid,
    user_id: Uuid,
    fields: UpdateAliasAccountFields,
) -> Result<AliasAccountRecord> {
    // Build dynamic update query
    let mut set_clauses = Vec::new();
    let mut param_index = 3; // Start after account_id and user_id

    if fields.alias_name.is_some() {
        set_clauses.push(format!("alias_name = ${}", param_index));
        param_index += 1;
    }
    if fields.avatar_url.is_some() {
        set_clauses.push(format!("avatar_url = ${}", param_index));
        param_index += 1;
    }
    if fields.date_of_birth.is_some() {
        set_clauses.push(format!("date_of_birth = ${}", param_index));
        param_index += 1;
    }
    if fields.gender.is_some() {
        set_clauses.push(format!("gender = ${}", param_index));
        param_index += 1;
    }
    if fields.profession.is_some() {
        set_clauses.push(format!("profession = ${}", param_index));
        param_index += 1;
    }
    if fields.location.is_some() {
        set_clauses.push(format!("location = ${}", param_index));
        // param_index += 1;  // Not needed for last parameter
    }

    if set_clauses.is_empty() {
        // No updates, just return current record
        return find_by_id_and_user(pool, account_id, user_id)
            .await?
            .ok_or_else(|| IdentityError::NotFoundError("Alias account not found".to_string()));
    }

    let query = format!(
        "UPDATE alias_accounts SET {} WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL RETURNING *",
        set_clauses.join(", ")
    );

    // Build and execute query with dynamic bindings
    let mut query_builder = sqlx::query_as::<_, AliasAccountRecord>(&query)
        .bind(account_id)
        .bind(user_id);

    if let Some(ref alias_name) = fields.alias_name {
        query_builder = query_builder.bind(alias_name);
    }
    if let Some(ref avatar_url) = fields.avatar_url {
        query_builder = query_builder.bind(avatar_url);
    }
    if let Some(date_of_birth) = fields.date_of_birth {
        query_builder = query_builder.bind(date_of_birth);
    }
    if let Some(ref gender) = fields.gender {
        query_builder = query_builder.bind(gender.as_str());
    }
    if let Some(ref profession) = fields.profession {
        query_builder = query_builder.bind(profession);
    }
    if let Some(ref location) = fields.location {
        query_builder = query_builder.bind(location);
    }

    let record = query_builder.fetch_optional(pool).await?.ok_or_else(|| {
        IdentityError::NotFoundError("Alias account not found or not owned by user".to_string())
    })?;

    Ok(record)
}

/// Soft delete an alias account
pub async fn delete_alias_account(pool: &PgPool, account_id: Uuid, user_id: Uuid) -> Result<()> {
    let result = sqlx::query(
        "UPDATE alias_accounts SET deleted_at = NOW(), is_active = false WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(IdentityError::NotFoundError(
            "Alias account not found or not owned by user".to_string(),
        ));
    }

    Ok(())
}

/// Set an alias account as active (deactivates others)
pub async fn set_active_alias(pool: &PgPool, account_id: Uuid, user_id: Uuid) -> Result<()> {
    // First, deactivate all alias accounts for this user
    sqlx::query("UPDATE alias_accounts SET is_active = false WHERE user_id = $1")
        .bind(user_id)
        .execute(pool)
        .await?;

    // Then activate the specified account
    let result = sqlx::query(
        "UPDATE alias_accounts SET is_active = true WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(pool)
    .await?;

    if result.rows_affected() == 0 {
        return Err(IdentityError::NotFoundError(
            "Alias account not found or not owned by user".to_string(),
        ));
    }

    Ok(())
}

/// Deactivate all alias accounts for a user (switch back to primary)
pub async fn deactivate_all_aliases(pool: &PgPool, user_id: Uuid) -> Result<()> {
    sqlx::query("UPDATE alias_accounts SET is_active = false WHERE user_id = $1")
        .bind(user_id)
        .execute(pool)
        .await?;

    Ok(())
}

/// Update user's current account tracking
pub async fn update_user_current_account(
    pool: &PgPool,
    user_id: Uuid,
    current_account_id: Option<Uuid>,
    account_type: &str,
) -> Result<()> {
    sqlx::query(
        "UPDATE users SET current_account_id = $1, current_account_type = $2 WHERE id = $3",
    )
    .bind(current_account_id)
    .bind(account_type)
    .bind(user_id)
    .execute(pool)
    .await?;

    Ok(())
}
