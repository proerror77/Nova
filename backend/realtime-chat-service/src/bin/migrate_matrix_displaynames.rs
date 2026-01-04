//! Migration script to update Matrix user display names
//!
//! This script fixes existing Matrix users who have "Nova User {uuid}" as their display name
//! by fetching their actual username from identity-service and updating Matrix.
//!
//! ## Usage
//!
//! ```bash
//! # Set environment variables
//! export SYNAPSE_HOMESERVER_URL="http://matrix-synapse:8008"
//! export SYNAPSE_ADMIN_TOKEN="syt_xxx"
//! export SYNAPSE_SERVER_NAME="staging.nova.app"
//! export IDENTITY_SERVICE_URL="http://identity-service:50051"
//!
//! # Run the migration
//! cargo run --bin migrate-matrix-displaynames
//!
//! # Dry run (default) - shows what would be updated without making changes
//! cargo run --bin migrate-matrix-displaynames -- --dry-run
//!
//! # Actually perform the migration
//! cargo run --bin migrate-matrix-displaynames -- --execute
//! ```
//!
//! ## Running in Kubernetes
//!
//! ```bash
//! kubectl run matrix-migration --rm -it --restart=Never \
//!   --image=asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/realtime-chat-service:latest \
//!   --env="SYNAPSE_HOMESERVER_URL=http://matrix-synapse:8008" \
//!   --env="SYNAPSE_ADMIN_TOKEN=$ADMIN_TOKEN" \
//!   --env="SYNAPSE_SERVER_NAME=staging.nova.app" \
//!   --env="IDENTITY_SERVICE_URL=http://identity-service:50051" \
//!   --command -- /app/migrate-matrix-displaynames --execute
//! ```

use grpc_clients::AuthClient;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use uuid::Uuid;

/// Response from Synapse Admin API list users endpoint
#[derive(Debug, Deserialize)]
struct ListUsersResponse {
    users: Vec<MatrixUser>,
    #[serde(default)]
    next_token: Option<String>,
    #[serde(default)]
    total: Option<u64>,
}

/// Matrix user from Admin API
#[derive(Debug, Deserialize)]
struct MatrixUser {
    name: String,
    #[serde(default)]
    displayname: Option<String>,
    #[serde(default)]
    deactivated: bool,
}

/// Request body for updating display name via Admin API
#[derive(Debug, Serialize)]
struct UpdateUserRequest {
    displayname: String,
}

/// Migration configuration
struct MigrationConfig {
    homeserver_url: String,
    admin_token: String,
    server_name: String,
    identity_service_url: String,
    dry_run: bool,
}

impl MigrationConfig {
    fn from_env() -> Result<Self, String> {
        Ok(Self {
            homeserver_url: env::var("SYNAPSE_HOMESERVER_URL")
                .unwrap_or_else(|_| "http://matrix-synapse:8008".to_string()),
            admin_token: env::var("SYNAPSE_ADMIN_TOKEN")
                .map_err(|_| "SYNAPSE_ADMIN_TOKEN environment variable is required")?,
            server_name: env::var("SYNAPSE_SERVER_NAME")
                .unwrap_or_else(|_| "staging.nova.app".to_string()),
            identity_service_url: env::var("IDENTITY_SERVICE_URL")
                .unwrap_or_else(|_| "http://identity-service:50051".to_string()),
            dry_run: true, // Default to dry run for safety
        })
    }
}

/// Extract Nova user UUID from Matrix user ID (MXID)
/// Format: @nova-{uuid}:{server_name}
fn extract_nova_user_id(mxid: &str) -> Option<Uuid> {
    // Expected format: @nova-{uuid}:{server}
    if !mxid.starts_with("@nova-") {
        return None;
    }

    let without_prefix = mxid.strip_prefix("@nova-")?;
    let uuid_part = without_prefix.split(':').next()?;
    Uuid::parse_str(uuid_part).ok()
}

/// Check if display name matches "Nova User {uuid}" pattern
fn is_placeholder_displayname(displayname: &str) -> bool {
    // Match patterns like:
    // - "Nova User 123e4567"
    // - "Nova User 123e4567-e89b-41d4-a716-446655440000"
    // - "User 123e4567"
    displayname.starts_with("Nova User ") ||
    (displayname.starts_with("User ") && displayname.len() > 5)
}

/// List all Matrix users via Synapse Admin API
async fn list_all_users(
    client: &Client,
    config: &MigrationConfig,
) -> Result<Vec<MatrixUser>, String> {
    let mut all_users = Vec::new();
    let mut from: u64 = 0;
    let limit: u64 = 100;

    loop {
        let url = format!(
            "{}/_synapse/admin/v2/users?from={}&limit={}&guests=false",
            config.homeserver_url, from, limit
        );

        let response = client
            .get(&url)
            .header("Authorization", format!("Bearer {}", config.admin_token))
            .send()
            .await
            .map_err(|e| format!("Failed to list users: {}", e))?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(format!("Synapse API error: {} - {}", status, body));
        }

        let list_response: ListUsersResponse = response
            .json()
            .await
            .map_err(|e| format!("Failed to parse response: {}", e))?;

        let user_count = list_response.users.len();
        all_users.extend(list_response.users);

        println!(
            "Fetched {} users (total so far: {})",
            user_count,
            all_users.len()
        );

        // Check if we have more users
        if user_count < limit as usize {
            break;
        }

        from += limit;
    }

    Ok(all_users)
}

/// Update a user's display name via Synapse Admin API
async fn update_displayname(
    client: &Client,
    config: &MigrationConfig,
    mxid: &str,
    new_displayname: &str,
) -> Result<(), String> {
    let url = format!(
        "{}/_synapse/admin/v2/users/{}",
        config.homeserver_url,
        urlencoding::encode(mxid)
    );

    let request_body = UpdateUserRequest {
        displayname: new_displayname.to_string(),
    };

    let response = client
        .put(&url)
        .header("Authorization", format!("Bearer {}", config.admin_token))
        .json(&request_body)
        .send()
        .await
        .map_err(|e| format!("Failed to update user {}: {}", mxid, e))?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!(
            "Failed to update {} display name: {} - {}",
            mxid, status, body
        ));
    }

    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    // Parse command line arguments
    let args: Vec<String> = env::args().collect();
    let mut config = MigrationConfig::from_env()?;

    for arg in &args[1..] {
        match arg.as_str() {
            "--execute" | "-e" => config.dry_run = false,
            "--dry-run" | "-d" => config.dry_run = true,
            "--help" | "-h" => {
                println!(
                    r#"Matrix Display Name Migration Script

Updates Matrix users with "Nova User {{uuid}}" display names to their actual username.

USAGE:
    migrate-matrix-displaynames [OPTIONS]

OPTIONS:
    --dry-run, -d     Show what would be updated without making changes (default)
    --execute, -e     Actually perform the migration
    --help, -h        Show this help message

ENVIRONMENT VARIABLES:
    SYNAPSE_HOMESERVER_URL    Synapse server URL (default: http://matrix-synapse:8008)
    SYNAPSE_ADMIN_TOKEN       Admin access token (required)
    SYNAPSE_SERVER_NAME       Matrix server name (default: staging.nova.app)
    IDENTITY_SERVICE_URL      Identity service gRPC URL (default: http://identity-service:50051)
"#
                );
                return Ok(());
            }
            _ => {
                eprintln!("Unknown argument: {}", arg);
                return Err("Invalid argument".into());
            }
        }
    }

    println!("=== Matrix Display Name Migration ===");
    println!("Homeserver: {}", config.homeserver_url);
    println!("Server name: {}", config.server_name);
    println!("Identity service: {}", config.identity_service_url);
    println!("Mode: {}", if config.dry_run { "DRY RUN" } else { "EXECUTE" });
    println!();

    // Create HTTP client for Synapse Admin API
    let http_client = Client::new();

    // Create gRPC client for identity service
    println!("Connecting to identity service...");
    let auth_client = AuthClient::from_url(&config.identity_service_url)
        .await
        .map_err(|e| format!("Failed to connect to identity service: {}", e))?;
    println!("Connected to identity service");

    // Step 1: List all Matrix users
    println!("\nStep 1: Fetching all Matrix users...");
    let all_users = list_all_users(&http_client, &config).await?;
    println!("Total users found: {}", all_users.len());

    // Step 2: Filter for users with placeholder display names
    println!("\nStep 2: Filtering users with placeholder display names...");
    let mut users_to_migrate: Vec<(String, Uuid, String)> = Vec::new(); // (mxid, nova_id, old_displayname)

    for user in &all_users {
        // Skip deactivated users
        if user.deactivated {
            continue;
        }

        // Check if display name is a placeholder
        let displayname = user.displayname.as_deref().unwrap_or("");
        if !is_placeholder_displayname(displayname) {
            continue;
        }

        // Extract Nova user ID from MXID
        if let Some(nova_user_id) = extract_nova_user_id(&user.name) {
            users_to_migrate.push((user.name.clone(), nova_user_id, displayname.to_string()));
        }
    }

    println!(
        "Found {} users with placeholder display names",
        users_to_migrate.len()
    );

    if users_to_migrate.is_empty() {
        println!("\nNo users need migration. Done!");
        return Ok(());
    }

    // Step 3: Batch fetch usernames from identity service
    println!("\nStep 3: Fetching actual usernames from identity service...");
    let nova_user_ids: Vec<Uuid> = users_to_migrate.iter().map(|(_, id, _)| *id).collect();

    // Batch in groups of 100 to avoid overwhelming the service
    let mut username_map: HashMap<Uuid, String> = HashMap::new();
    for chunk in nova_user_ids.chunks(100) {
        match auth_client.get_users_by_ids(chunk).await {
            Ok(results) => {
                username_map.extend(results);
            }
            Err(e) => {
                eprintln!("Warning: Failed to fetch some usernames: {}", e);
            }
        }
    }

    println!("Fetched {} usernames", username_map.len());

    // Step 4: Update display names
    println!("\nStep 4: Updating display names...");
    let mut success_count = 0;
    let mut skip_count = 0;
    let mut error_count = 0;

    for (mxid, nova_user_id, old_displayname) in &users_to_migrate {
        // Look up the actual username
        let new_displayname = match username_map.get(nova_user_id) {
            Some(username) => username.clone(),
            None => {
                println!(
                    "  SKIP: {} - username not found for {}",
                    mxid, nova_user_id
                );
                skip_count += 1;
                continue;
            }
        };

        // Skip if already correct
        if old_displayname == &new_displayname {
            skip_count += 1;
            continue;
        }

        if config.dry_run {
            println!(
                "  [DRY RUN] Would update: {} \"{}\" -> \"{}\"",
                mxid, old_displayname, new_displayname
            );
            success_count += 1;
        } else {
            match update_displayname(&http_client, &config, mxid, &new_displayname).await {
                Ok(()) => {
                    println!(
                        "  Updated: {} \"{}\" -> \"{}\"",
                        mxid, old_displayname, new_displayname
                    );
                    success_count += 1;
                }
                Err(e) => {
                    eprintln!("  ERROR: {} - {}", mxid, e);
                    error_count += 1;
                }
            }
        }
    }

    // Summary
    println!("\n=== Migration Summary ===");
    println!("Total users scanned: {}", all_users.len());
    println!("Users with placeholder names: {}", users_to_migrate.len());
    println!(
        "Successfully {}: {}",
        if config.dry_run { "would update" } else { "updated" },
        success_count
    );
    println!("Skipped (no username found): {}", skip_count);
    if error_count > 0 {
        println!("Errors: {}", error_count);
    }

    if config.dry_run {
        println!("\n** This was a dry run. Use --execute to actually update display names. **");
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_nova_user_id() {
        // Valid format
        let mxid = "@nova-550e8400-e29b-41d4-a716-446655440000:staging.nova.app";
        let result = extract_nova_user_id(mxid);
        assert!(result.is_some());
        assert_eq!(
            result.unwrap().to_string(),
            "550e8400-e29b-41d4-a716-446655440000"
        );

        // Invalid prefix
        let mxid = "@user-123:staging.nova.app";
        assert!(extract_nova_user_id(mxid).is_none());

        // Invalid UUID
        let mxid = "@nova-invalid:staging.nova.app";
        assert!(extract_nova_user_id(mxid).is_none());
    }

    #[test]
    fn test_is_placeholder_displayname() {
        assert!(is_placeholder_displayname("Nova User 550e8400"));
        assert!(is_placeholder_displayname("Nova User 550e8400-e29b-41d4-a716-446655440000"));
        assert!(is_placeholder_displayname("User 550e8400"));

        assert!(!is_placeholder_displayname("john_doe"));
        assert!(!is_placeholder_displayname("Alice"));
        assert!(!is_placeholder_displayname("User")); // Too short to be placeholder
    }
}
