//! Authentication GraphQL Schema

use async_graphql::{Context, Object, Result, SimpleObject, Error};
use crate::clients::ServiceClients;

/// Extract JWT token from Authorization header
fn extract_token(ctx: &Context<'_>) -> Result<String> {
    ctx.data_opt::<String>()
        .ok_or_else(|| Error::new("Authorization token not found"))
        .map(|s| s.clone())
}

/// User type for authentication responses
#[derive(SimpleObject, Clone)]
pub struct AuthUser {
    pub id: String,
    pub username: String,
    pub email: String,
    #[graphql(name = "displayName")]
    pub display_name: Option<String>,
    #[graphql(name = "avatarUrl")]
    pub avatar_url: Option<String>,
    #[graphql(name = "isVerified")]
    pub is_verified: bool,
}

/// Authentication response with tokens
#[derive(SimpleObject)]
pub struct AuthResponse {
    #[graphql(name = "accessToken")]
    pub access_token: String,
    #[graphql(name = "refreshToken")]
    pub refresh_token: String,
    pub user: AuthUser,
}

/// Authentication queries
#[derive(Default)]
pub struct AuthQuery;

#[Object]
impl AuthQuery {
    /// Get current authenticated user
    async fn me(&self, ctx: &Context<'_>) -> Result<AuthUser> {
        use crate::clients::proto::auth::{VerifyTokenRequest, GetUserRequest};

        let token = extract_token(ctx)?;

        let clients = ctx.data::<ServiceClients>()
            .map_err(|_| Error::new("Service clients not available"))?;

        // Verify token and get user info
        let mut client = clients.auth_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to auth service: {}", e)))?;

        let request = tonic::Request::new(VerifyTokenRequest { token });
        let verify_response = client.verify_token(request)
            .await
            .map_err(|e| Error::new(format!("Token verification failed: {}", e)))?
            .into_inner();

        if !verify_response.is_valid {
            return Err(Error::new("Invalid or expired token"));
        }

        // Get full user profile
        let user_request = tonic::Request::new(GetUserRequest {
            user_id: verify_response.user_id.clone(),
        });

        let user_response = client.get_user(user_request)
            .await
            .map_err(|e| Error::new(format!("Failed to get user: {}", e)))?
            .into_inner();

        let user = user_response.user
            .ok_or_else(|| Error::new("User not found"))?;

        Ok(AuthUser {
            id: user.id,
            username: user.username,
            email: verify_response.email,
            display_name: None,  // Basic User type doesn't have display_name
            avatar_url: None,
            is_verified: false,
        })
    }
}

/// Authentication mutations
#[derive(Default)]
pub struct AuthMutation;

#[Object]
impl AuthMutation {
    /// User login
    async fn login(
        &self,
        ctx: &Context<'_>,
        email: String,
        password: String,
    ) -> Result<AuthResponse> {
        use crate::clients::proto::auth::{LoginRequest};

        let clients = ctx.data::<ServiceClients>()
            .map_err(|_| Error::new("Service clients not available"))?;

        let mut client = clients.auth_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to auth service: {}", e)))?;

        let request = tonic::Request::new(LoginRequest {
            email: email.clone(),
            password,
        });

        let response = client.login(request)
            .await
            .map_err(|e| Error::new(format!("Login failed: {}", e)))?
            .into_inner();

        // Get user profile for additional fields
        let user_profile = {
            use crate::clients::proto::auth::GetUserRequest;
            let mut client = clients.auth_client().await?;
            let request = tonic::Request::new(GetUserRequest {
                user_id: response.user_id.clone(),
            });
            client.get_user(request).await.ok().and_then(|r| r.into_inner().user)
        };

        Ok(AuthResponse {
            access_token: response.token,
            refresh_token: response.refresh_token,
            user: AuthUser {
                id: response.user_id.clone(),
                username: user_profile.as_ref().map(|u| u.username.clone()).unwrap_or_default(),
                email: email.clone(),
                display_name: None,
                avatar_url: None,
                is_verified: false,
            },
        })
    }

    /// User registration
    async fn register(
        &self,
        ctx: &Context<'_>,
        email: String,
        username: String,
        password: String,
    ) -> Result<AuthResponse> {
        use crate::clients::proto::auth::RegisterRequest;

        let clients = ctx.data::<ServiceClients>()
            .map_err(|_| Error::new("Service clients not available"))?;

        let mut client = clients.auth_client()
            .await
            .map_err(|e| Error::new(format!("Failed to connect to auth service: {}", e)))?;

        let request = tonic::Request::new(RegisterRequest {
            email: email.clone(),
            username: username.clone(),
            password,
        });

        let response = client.register(request)
            .await
            .map_err(|e| Error::new(format!("Registration failed: {}", e)))?
            .into_inner();

        Ok(AuthResponse {
            access_token: response.token,
            refresh_token: response.refresh_token,
            user: AuthUser {
                id: response.user_id,
                username: username.clone(),
                email: email.clone(),
                display_name: Some(username),
                avatar_url: None,
                is_verified: false,
            },
        })
    }

    /// User logout
    async fn logout(&self, ctx: &Context<'_>) -> Result<bool> {
        // TODO: Call auth-service to revoke token
        Ok(true)
    }
}
