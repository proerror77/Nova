//! Authentication schema and resolvers

use async_graphql::{Context, Object, Result as GraphQLResult, SimpleObject};
use serde::{Deserialize, Serialize};

use crate::clients::ServiceClients;

#[derive(SimpleObject, Clone, Debug, Serialize, Deserialize)]
pub struct LoginResponse {
    pub user_id: String,
    pub token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

#[derive(SimpleObject, Clone, Debug, Serialize, Deserialize)]
pub struct RegisterResponse {
    pub user_id: String,
    pub token: String,
    pub refresh_token: String,
    pub expires_in: i64,
}

#[derive(Default)]
pub struct AuthQuery;

#[Object]
impl AuthQuery {
    async fn health(&self) -> &str {
        "ok"
    }
}

#[derive(Default)]
pub struct AuthMutation;

#[Object]
impl AuthMutation {
    async fn login(
        &self,
        ctx: &Context<'_>,
        email: String,
        password: String,
    ) -> GraphQLResult<LoginResponse> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients.auth_client();

        let request = tonic::Request::new(crate::clients::proto::auth::LoginRequest { email, password });

        let response = client
            .login(request)
            .await
            .map_err(|e| format!("Login failed: {}", e))?
            .into_inner();

        Ok(LoginResponse {
            user_id: response.user_id,
            token: response.token,
            refresh_token: response.refresh_token,
            expires_in: response.expires_in,
        })
    }

    async fn register(
        &self,
        ctx: &Context<'_>,
        email: String,
        password: String,
        username: String,
    ) -> GraphQLResult<RegisterResponse> {
        let clients = ctx
            .data::<ServiceClients>()
            .map_err(|_| "Service clients not available")?;

        let mut client = clients.auth_client();

        let request = tonic::Request::new(crate::clients::proto::auth::RegisterRequest {
            email,
            password,
            username,
        });

        let response = client
            .register(request)
            .await
            .map_err(|e| format!("Registration failed: {}", e))?
            .into_inner();

        Ok(RegisterResponse {
            user_id: response.user_id,
            token: response.token,
            refresh_token: response.refresh_token,
            expires_in: response.expires_in,
        })
    }
}
