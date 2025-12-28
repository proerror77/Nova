/// Zitadel User Synchronization Service
///
/// Provisions users to Zitadel when they register via Nova OAuth (Google/Apple).
/// This enables unified SSO: users can login to Matrix via Zitadel using the
/// same identity they used to sign up with Nova.
///
/// ## Architecture
///
/// Nova (OAuth) -> User DB -> Zitadel (OIDC provider) -> Matrix Synapse
///
/// When a user signs up via Google/Apple OAuth in Nova:
/// 1. Nova creates/updates user in its database
/// 2. Nova calls Zitadel Management API to import the user
/// 3. User can now SSO into Matrix via Zitadel
///
/// ## API Reference
///
/// Zitadel Management API v2:
/// - Import Human User: POST /management/v1/users/_import
/// - Add IdP Link: POST /management/v1/users/{userId}/links/_idp

use crate::config::ZitadelSettings;
use crate::error::{IdentityError, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use tracing::{debug, error, info, warn};
use uuid::Uuid;

/// Zitadel user provisioning service
#[derive(Clone)]
pub struct ZitadelService {
    config: ZitadelSettings,
    http: Client,
}

impl ZitadelService {
    pub fn new(config: ZitadelSettings) -> Option<Self> {
        if !config.is_configured() {
            info!("Zitadel sync is disabled or not configured");
            return None;
        }

        // Safety: is_configured() already verified api_url is Some
        info!(
            api_url = %config.api_url.as_ref().expect("api_url verified by is_configured"),
            "Zitadel user sync service initialized"
        );

        Some(Self {
            config,
            http: Client::new(),
        })
    }

    /// Provision a user to Zitadel
    ///
    /// Creates or updates a user in Zitadel based on their Nova profile.
    /// Uses the "Import Human User" API to create users with pre-verified emails.
    pub async fn provision_user(&self, user: &ZitadelUserInfo) -> Result<ZitadelProvisionResult> {
        let api_url = self.config.api_url.as_ref().ok_or_else(|| {
            IdentityError::Configuration("Zitadel API URL not configured".to_string())
        })?;
        let token = self.config.service_token.as_ref().ok_or_else(|| {
            IdentityError::Configuration("Zitadel service token not configured".to_string())
        })?;
        let org_id = self.config.org_id.as_ref().ok_or_else(|| {
            IdentityError::Configuration("Zitadel org ID not configured".to_string())
        })?;

        // First, check if user already exists by email
        if let Some(existing_user_id) = self.find_user_by_email(user.email.as_str()).await? {
            info!(
                nova_user_id = %user.nova_user_id,
                zitadel_user_id = %existing_user_id,
                email = %user.email,
                "User already exists in Zitadel"
            );
            return Ok(ZitadelProvisionResult {
                zitadel_user_id: existing_user_id,
                is_new: false,
            });
        }

        // Build import user request
        let import_request = ImportUserRequest {
            user_name: user.username.clone(),
            profile: ImportUserProfile {
                given_name: user.given_name.clone().unwrap_or_else(|| user.username.clone()),
                family_name: user.family_name.clone().unwrap_or_else(|| "User".to_string()),
                display_name: user.display_name.clone(),
                nick_name: Some(user.username.clone()),
                preferred_language: Some("en".to_string()),
            },
            email: ImportUserEmail {
                email: user.email.clone(),
                is_email_verified: true, // Email verified via OAuth provider
            },
            // Use Nova user ID as external ID for correlation
            idps: user.idp_link.as_ref().map(|link| {
                vec![ImportUserIdp {
                    config_id: link.idp_config_id.clone(),
                    external_user_id: link.external_user_id.clone(),
                    display_name: link.display_name.clone(),
                }]
            }),
        };

        let url = format!("{}/management/v1/users/human/_import", api_url);

        debug!(
            url = %url,
            username = %user.username,
            email = %user.email,
            "Importing user to Zitadel"
        );

        let response = self
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
            .header("x-zitadel-orgid", org_id)
            .header("Content-Type", "application/json")
            .json(&import_request)
            .send()
            .await
            .map_err(|e| IdentityError::ZitadelError(format!("HTTP request failed: {}", e)))?;

        let status = response.status();
        let body = response
            .text()
            .await
            .unwrap_or_else(|_| "Failed to read response body".to_string());

        if !status.is_success() {
            // Check if user already exists (conflict)
            if status.as_u16() == 409 {
                warn!(
                    email = %user.email,
                    "User already exists in Zitadel (conflict)"
                );
                // Try to find the existing user
                if let Some(existing_id) = self.find_user_by_email(&user.email).await? {
                    return Ok(ZitadelProvisionResult {
                        zitadel_user_id: existing_id,
                        is_new: false,
                    });
                }
            }

            error!(
                status = %status,
                body = %body,
                email = %user.email,
                "Failed to import user to Zitadel"
            );
            return Err(IdentityError::ZitadelError(format!(
                "User import failed ({}): {}",
                status, body
            )));
        }

        // Parse response to get user ID
        let import_response: ImportUserResponse = serde_json::from_str(&body).map_err(|e| {
            IdentityError::ZitadelError(format!("Failed to parse import response: {}", e))
        })?;

        info!(
            nova_user_id = %user.nova_user_id,
            zitadel_user_id = %import_response.user_id,
            email = %user.email,
            "Successfully provisioned user to Zitadel"
        );

        Ok(ZitadelProvisionResult {
            zitadel_user_id: import_response.user_id,
            is_new: true,
        })
    }

    /// Find a user in Zitadel by email
    async fn find_user_by_email(&self, email: &str) -> Result<Option<String>> {
        let api_url = self.config.api_url.as_ref().ok_or_else(|| {
            IdentityError::Configuration("Zitadel API URL not configured".to_string())
        })?;
        let token = self.config.service_token.as_ref().ok_or_else(|| {
            IdentityError::Configuration("Zitadel service token not configured".to_string())
        })?;
        let org_id = self.config.org_id.as_ref().ok_or_else(|| {
            IdentityError::Configuration("Zitadel org ID not configured".to_string())
        })?;

        let search_request = SearchUserRequest {
            queries: vec![UserQuery {
                email_query: Some(EmailQuery {
                    email_address: email.to_string(),
                    method: "TEXT_QUERY_METHOD_EQUALS".to_string(),
                }),
            }],
        };

        let url = format!("{}/management/v1/users/_search", api_url);

        let response = self
            .http
            .post(&url)
            .header("Authorization", format!("Bearer {}", token))
            .header("x-zitadel-orgid", org_id)
            .header("Content-Type", "application/json")
            .json(&search_request)
            .send()
            .await
            .map_err(|e| IdentityError::ZitadelError(format!("User search failed: {}", e)))?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            debug!(
                status = %status,
                body = %body,
                email = %email,
                "User search returned non-success status"
            );
            return Ok(None);
        }

        let search_response: SearchUserResponse = response.json().await.map_err(|e| {
            IdentityError::ZitadelError(format!("Failed to parse search response: {}", e))
        })?;

        if let Some(user) = search_response.result.into_iter().next() {
            Ok(Some(user.id))
        } else {
            Ok(None)
        }
    }
}

/// User information for Zitadel provisioning
#[derive(Debug, Clone)]
pub struct ZitadelUserInfo {
    /// Nova user ID (for correlation)
    pub nova_user_id: Uuid,
    /// Username (used as Zitadel login name)
    pub username: String,
    /// Email address
    pub email: String,
    /// Display name
    pub display_name: Option<String>,
    /// Given name (first name)
    pub given_name: Option<String>,
    /// Family name (last name)
    pub family_name: Option<String>,
    /// Profile picture URL
    pub picture_url: Option<String>,
    /// Optional IdP link for federated identity
    pub idp_link: Option<IdpLinkInfo>,
}

/// IdP link information for federated identity
#[derive(Debug, Clone)]
pub struct IdpLinkInfo {
    /// Zitadel IdP configuration ID (e.g., "google-idp-config-id")
    pub idp_config_id: String,
    /// External user ID from the IdP (e.g., Google sub)
    pub external_user_id: String,
    /// Display name from the IdP
    pub display_name: Option<String>,
}

/// Result of user provisioning
#[derive(Debug)]
pub struct ZitadelProvisionResult {
    /// Zitadel user ID
    pub zitadel_user_id: String,
    /// Whether this is a newly created user
    pub is_new: bool,
}

// ===== Zitadel API Request/Response Types =====

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ImportUserRequest {
    user_name: String,
    profile: ImportUserProfile,
    email: ImportUserEmail,
    #[serde(skip_serializing_if = "Option::is_none")]
    idps: Option<Vec<ImportUserIdp>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ImportUserProfile {
    given_name: String,
    family_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    nick_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    preferred_language: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ImportUserEmail {
    email: String,
    is_email_verified: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ImportUserIdp {
    config_id: String,
    external_user_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    display_name: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ImportUserResponse {
    user_id: String,
}

#[derive(Debug, Serialize)]
struct SearchUserRequest {
    queries: Vec<UserQuery>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct UserQuery {
    #[serde(skip_serializing_if = "Option::is_none")]
    email_query: Option<EmailQuery>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct EmailQuery {
    email_address: String,
    method: String,
}

#[derive(Debug, Deserialize)]
struct SearchUserResponse {
    #[serde(default)]
    result: Vec<SearchUserResult>,
}

#[derive(Debug, Deserialize)]
struct SearchUserResult {
    id: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_import_request_serialization() {
        let request = ImportUserRequest {
            user_name: "testuser".to_string(),
            profile: ImportUserProfile {
                given_name: "Test".to_string(),
                family_name: "User".to_string(),
                display_name: Some("Test User".to_string()),
                nick_name: Some("testuser".to_string()),
                preferred_language: Some("en".to_string()),
            },
            email: ImportUserEmail {
                email: "test@example.com".to_string(),
                is_email_verified: true,
            },
            idps: None,
        };

        let json = serde_json::to_string(&request).unwrap();
        assert!(json.contains("userName"));
        assert!(json.contains("givenName"));
        assert!(json.contains("isEmailVerified"));
    }
}
