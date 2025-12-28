/// Accounts Service API endpoints - Multi-account & Alias Management
///
/// GET  /api/v2/accounts                  - List all accounts (primary + aliases)
/// POST /api/v2/accounts/switch           - Switch to a different account
/// POST /api/v2/accounts/alias            - Create a new alias account
/// PUT  /api/v2/accounts/alias/:id        - Update an alias account
/// GET  /api/v2/accounts/alias/:id        - Get alias account details
/// DELETE /api/v2/accounts/alias/:id      - Delete an alias account
use actix_web::{web, HttpMessage, HttpRequest, HttpResponse, Result};
use serde::{Deserialize, Serialize};
use tracing::{error, info};

use crate::clients::proto::identity::{
    CreateAliasAccountRequest, DeleteAliasAccountRequest, Gender, GetAliasAccountRequest,
    ListAccountsRequest, SwitchAccountRequest, UpdateAliasAccountRequest,
};
use crate::clients::ServiceClients;
use crate::middleware::jwt::AuthenticatedUser;
use crate::rest_api::models::ErrorResponse;

// ============================================================================
// Request/Response Models
// ============================================================================

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct SwitchAccountBody {
    pub target_account_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct CreateAliasBody {
    pub alias_name: String,
    #[serde(default)]
    pub avatar_url: Option<String>,
    #[serde(default)]
    pub date_of_birth: Option<String>,
    #[serde(default)]
    pub gender: Option<String>,
    #[serde(default)]
    pub profession: Option<String>,
    #[serde(default)]
    pub location: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct UpdateAliasBody {
    #[serde(default)]
    pub alias_name: Option<String>,
    #[serde(default)]
    pub avatar_url: Option<String>,
    #[serde(default)]
    pub date_of_birth: Option<String>,
    #[serde(default)]
    pub gender: Option<String>,
    #[serde(default)]
    pub profession: Option<String>,
    #[serde(default)]
    pub location: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct AccountResponse {
    pub id: String,
    pub user_id: String,
    pub username: String,
    pub display_name: String,
    pub avatar_url: String,
    pub is_primary: bool,
    pub is_active: bool,
    pub is_alias: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub alias_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub date_of_birth: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gender: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profession: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub location: Option<String>,
    pub created_at: i64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct ListAccountsResponse {
    pub accounts: Vec<AccountResponse>,
    pub current_account_id: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
pub struct SwitchAccountResponse {
    pub success: bool,
    pub access_token: String,
    pub refresh_token: String,
    pub account: AccountResponse,
}

// ============================================================================
// Helper Functions
// ============================================================================

fn gender_to_string(gender: i32) -> Option<String> {
    match Gender::try_from(gender) {
        Ok(Gender::Male) => Some("male".to_string()),
        Ok(Gender::Female) => Some("female".to_string()),
        Ok(Gender::Other) => Some("other".to_string()),
        Ok(Gender::PreferNotToSay) => Some("prefer_not_to_say".to_string()),
        _ => None,
    }
}

fn string_to_gender(s: &str) -> Gender {
    match s.to_lowercase().as_str() {
        "male" => Gender::Male,
        "female" => Gender::Female,
        "other" => Gender::Other,
        "prefer_not_to_say" | "prefernotosay" => Gender::PreferNotToSay,
        _ => Gender::Unspecified,
    }
}

fn proto_account_to_response(
    account: &crate::clients::proto::identity::Account,
) -> AccountResponse {
    AccountResponse {
        id: account.id.clone(),
        user_id: account.user_id.clone(),
        username: account.username.clone(),
        display_name: account.display_name.clone(),
        avatar_url: account.avatar_url.clone(),
        is_primary: account.is_primary,
        is_active: account.is_active,
        is_alias: account.is_alias,
        alias_name: if account.is_alias && !account.alias_name.is_empty() {
            Some(account.alias_name.clone())
        } else {
            None
        },
        date_of_birth: if account.is_alias && !account.date_of_birth.is_empty() {
            Some(account.date_of_birth.clone())
        } else {
            None
        },
        gender: if account.is_alias {
            gender_to_string(account.gender)
        } else {
            None
        },
        profession: if account.is_alias && !account.profession.is_empty() {
            Some(account.profession.clone())
        } else {
            None
        },
        location: if account.is_alias && !account.location.is_empty() {
            Some(account.location.clone())
        } else {
            None
        },
        created_at: account.created_at,
    }
}

// ============================================================================
// Handlers
// ============================================================================

/// GET /api/v2/accounts
/// List all accounts for the authenticated user (primary + aliases)
pub async fn list_accounts(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    info!(user_id = %user_id, "GET /api/v2/accounts");

    let mut identity_client = clients.identity_client();

    let grpc_request = tonic::Request::new(ListAccountsRequest {
        user_id: user_id.clone(),
    });

    match identity_client.list_accounts(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();
            let accounts: Vec<AccountResponse> = inner
                .accounts
                .iter()
                .map(proto_account_to_response)
                .collect();

            Ok(HttpResponse::Ok().json(ListAccountsResponse {
                accounts,
                current_account_id: inner.current_account_id,
            }))
        }
        Err(status) => {
            error!(user_id = %user_id, error = %status, "Failed to list accounts");

            let response = match status.code() {
                tonic::Code::NotFound => HttpResponse::NotFound().json(
                    ErrorResponse::with_message("User not found", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to list accounts",
                    status.message(),
                )),
            };

            Ok(response)
        }
    }
}

/// POST /api/v2/accounts/switch
/// Switch to a different account (primary or alias)
pub async fn switch_account(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<SwitchAccountBody>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    info!(
        user_id = %user_id,
        target_account_id = %body.target_account_id,
        "POST /api/v2/accounts/switch"
    );

    let mut identity_client = clients.identity_client();

    let grpc_request = tonic::Request::new(SwitchAccountRequest {
        user_id: user_id.clone(),
        target_account_id: body.target_account_id.clone(),
    });

    match identity_client.switch_account(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            if let Some(account) = inner.account {
                info!(
                    user_id = %user_id,
                    target_account_id = %body.target_account_id,
                    "Account switched successfully"
                );

                Ok(HttpResponse::Ok().json(SwitchAccountResponse {
                    success: inner.success,
                    access_token: inner.access_token,
                    refresh_token: inner.refresh_token,
                    account: proto_account_to_response(&account),
                }))
            } else {
                Ok(
                    HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                        "Account switch failed",
                        "No account returned from service",
                    )),
                )
            }
        }
        Err(status) => {
            error!(user_id = %user_id, error = %status, "Failed to switch account");

            let response = match status.code() {
                tonic::Code::NotFound => HttpResponse::NotFound().json(
                    ErrorResponse::with_message("Account not found", status.message()),
                ),
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid request", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to switch account",
                    status.message(),
                )),
            };

            Ok(response)
        }
    }
}

/// POST /api/v2/accounts/alias
/// Create a new alias account
pub async fn create_alias_account(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    body: web::Json<CreateAliasBody>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    info!(
        user_id = %user_id,
        alias_name = %body.alias_name,
        "POST /api/v2/accounts/alias"
    );

    // Validate alias name
    if body.alias_name.trim().is_empty() {
        return Ok(HttpResponse::BadRequest().json(ErrorResponse::with_message(
            "Invalid alias name",
            "Alias name is required",
        )));
    }

    let mut identity_client = clients.identity_client();

    let grpc_request = tonic::Request::new(CreateAliasAccountRequest {
        user_id: user_id.clone(),
        alias_name: body.alias_name.trim().to_string(),
        avatar_url: body.avatar_url.clone().unwrap_or_default(),
        date_of_birth: body.date_of_birth.clone().unwrap_or_default(),
        gender: body
            .gender
            .as_ref()
            .map(|g| string_to_gender(g))
            .unwrap_or(Gender::Unspecified)
            .into(),
        profession: body.profession.clone().unwrap_or_default(),
        location: body.location.clone().unwrap_or_default(),
    });

    match identity_client.create_alias_account(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            if let Some(account) = inner.account {
                info!(
                    user_id = %user_id,
                    alias_id = %account.id,
                    alias_name = %body.alias_name,
                    "Alias account created successfully"
                );

                Ok(HttpResponse::Created().json(serde_json::json!({
                    "success": true,
                    "account": proto_account_to_response(&account)
                })))
            } else {
                Ok(
                    HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                        "Failed to create alias",
                        "No account returned from service",
                    )),
                )
            }
        }
        Err(status) => {
            error!(user_id = %user_id, error = %status, "Failed to create alias account");

            let response = match status.code() {
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid request", status.message()),
                ),
                tonic::Code::NotFound => HttpResponse::NotFound().json(
                    ErrorResponse::with_message("User not found", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to create alias account",
                    status.message(),
                )),
            };

            Ok(response)
        }
    }
}

/// PUT /api/v2/accounts/alias/{id}
/// Update an alias account
pub async fn update_alias_account(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
    body: web::Json<UpdateAliasBody>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    let account_id = path.into_inner();
    info!(
        user_id = %user_id,
        account_id = %account_id,
        "PUT /api/v2/accounts/alias/{{id}}"
    );

    let mut identity_client = clients.identity_client();

    let grpc_request = tonic::Request::new(UpdateAliasAccountRequest {
        account_id: account_id.clone(),
        user_id: user_id.clone(),
        alias_name: body.alias_name.clone().unwrap_or_default(),
        avatar_url: body.avatar_url.clone().unwrap_or_default(),
        date_of_birth: body.date_of_birth.clone().unwrap_or_default(),
        gender: body
            .gender
            .as_ref()
            .map(|g| string_to_gender(g))
            .unwrap_or(Gender::Unspecified)
            .into(),
        profession: body.profession.clone().unwrap_or_default(),
        location: body.location.clone().unwrap_or_default(),
    });

    match identity_client.update_alias_account(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            if let Some(account) = inner.account {
                info!(
                    user_id = %user_id,
                    account_id = %account_id,
                    "Alias account updated successfully"
                );

                Ok(HttpResponse::Ok().json(serde_json::json!({
                    "success": true,
                    "account": proto_account_to_response(&account)
                })))
            } else {
                Ok(
                    HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                        "Failed to update alias",
                        "No account returned from service",
                    )),
                )
            }
        }
        Err(status) => {
            error!(user_id = %user_id, error = %status, "Failed to update alias account");

            let response = match status.code() {
                tonic::Code::NotFound => HttpResponse::NotFound().json(
                    ErrorResponse::with_message("Alias account not found", status.message()),
                ),
                tonic::Code::InvalidArgument => HttpResponse::BadRequest().json(
                    ErrorResponse::with_message("Invalid request", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to update alias account",
                    status.message(),
                )),
            };

            Ok(response)
        }
    }
}

/// GET /api/v2/accounts/alias/{id}
/// Get alias account details
pub async fn get_alias_account(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    let account_id = path.into_inner();
    info!(
        user_id = %user_id,
        account_id = %account_id,
        "GET /api/v2/accounts/alias/{{id}}"
    );

    let mut identity_client = clients.identity_client();

    let grpc_request = tonic::Request::new(GetAliasAccountRequest {
        account_id: account_id.clone(),
        user_id: user_id.clone(),
    });

    match identity_client.get_alias_account(grpc_request).await {
        Ok(response) => {
            let inner = response.into_inner();

            if let Some(account) = inner.account {
                Ok(HttpResponse::Ok().json(proto_account_to_response(&account)))
            } else {
                Ok(HttpResponse::NotFound().json(ErrorResponse::with_message(
                    "Alias account not found",
                    "Account does not exist or is not owned by user",
                )))
            }
        }
        Err(status) => {
            error!(user_id = %user_id, error = %status, "Failed to get alias account");

            let response = match status.code() {
                tonic::Code::NotFound => HttpResponse::NotFound().json(
                    ErrorResponse::with_message("Alias account not found", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to get alias account",
                    status.message(),
                )),
            };

            Ok(response)
        }
    }
}

/// DELETE /api/v2/accounts/alias/{id}
/// Delete an alias account (soft delete)
pub async fn delete_alias_account(
    req: HttpRequest,
    clients: web::Data<ServiceClients>,
    path: web::Path<String>,
) -> Result<HttpResponse> {
    let user = match req.extensions().get::<AuthenticatedUser>().copied() {
        Some(u) => u,
        None => return Ok(HttpResponse::Unauthorized().finish()),
    };

    let user_id = user.0.to_string();
    let account_id = path.into_inner();
    info!(
        user_id = %user_id,
        account_id = %account_id,
        "DELETE /api/v2/accounts/alias/{{id}}"
    );

    let mut identity_client = clients.identity_client();

    let grpc_request = tonic::Request::new(DeleteAliasAccountRequest {
        account_id: account_id.clone(),
        user_id: user_id.clone(),
    });

    match identity_client.delete_alias_account(grpc_request).await {
        Ok(_) => {
            info!(
                user_id = %user_id,
                account_id = %account_id,
                "Alias account deleted successfully"
            );

            Ok(HttpResponse::Ok().json(serde_json::json!({
                "success": true,
                "message": "Alias account deleted successfully"
            })))
        }
        Err(status) => {
            error!(user_id = %user_id, error = %status, "Failed to delete alias account");

            let response = match status.code() {
                tonic::Code::NotFound => HttpResponse::NotFound().json(
                    ErrorResponse::with_message("Alias account not found", status.message()),
                ),
                _ => HttpResponse::InternalServerError().json(ErrorResponse::with_message(
                    "Failed to delete alias account",
                    status.message(),
                )),
            };

            Ok(response)
        }
    }
}
