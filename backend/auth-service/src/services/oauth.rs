use crate::config::OAuthConfig;
use crate::db::{oauth as oauth_repo, users};
use crate::error::{AuthError, AuthResult};
use crate::metrics::{record_oauth_login, record_registration};
use crate::models::oauth::{OAuthProvider, OAuthUserInfo};
use crate::security::{jwt, password};
use crate::services::KafkaEventProducer;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine as _;
use chrono::{DateTime, Utc};
use redis_utils::SharedConnectionManager;
use reqwest::Client;
use serde::{de::DeserializeOwned, Deserialize};
use sqlx::PgPool;
use std::collections::HashMap;
use uuid::Uuid;

const OAUTH_STATE_TTL_SECONDS: usize = 600;

#[derive(Clone)]
pub struct OAuthService {
    config: OAuthConfig,
    db: PgPool,
    redis: SharedConnectionManager,
    http: Client,
    kafka: Option<KafkaEventProducer>,
}

pub struct OAuthLogin {
    pub user_id: Uuid,
    pub email: String,
    pub access_token: String,
    pub refresh_token: String,
    pub is_new_user: bool,
}

#[derive(Deserialize, serde::Serialize)]
struct OAuthStatePayload {
    provider: OAuthProvider,
    redirect_uri: String,
}

impl OAuthService {
    pub fn new(
        config: OAuthConfig,
        db: PgPool,
        redis: SharedConnectionManager,
        kafka: Option<KafkaEventProducer>,
    ) -> Self {
        Self {
            config,
            db,
            redis,
            http: Client::new(),
            kafka,
        }
    }

    pub async fn start_flow(
        &self,
        provider: OAuthProvider,
        redirect_uri: Option<String>,
    ) -> AuthResult<(String, String)> {
        let redirect = redirect_uri
            .or_else(|| self.default_redirect_uri(&provider))
            .ok_or_else(|| {
                AuthError::OAuthError(format!("{:?} redirect URI not configured", provider))
            })?;

        let state = Uuid::new_v4().to_string();
        let payload = OAuthStatePayload {
            provider,
            redirect_uri: redirect.clone(),
        };
        self.store_state(&state, &payload).await?;

        let auth_url = match provider {
            OAuthProvider::Google => self.google_authorize_url(&redirect, &state)?,
            OAuthProvider::Apple => self.apple_authorize_url(&redirect, &state)?,
            OAuthProvider::Facebook => self.facebook_authorize_url(&redirect, &state)?,
            OAuthProvider::WeChat => self.wechat_authorize_url(&redirect, &state)?,
        };

        Ok((state, auth_url))
    }

    pub async fn complete_flow(
        &self,
        provider: OAuthProvider,
        code: &str,
        state: &str,
    ) -> AuthResult<OAuthLogin> {
        let state_data = self.consume_state(state).await?;
        if state_data.provider != provider {
            return Err(AuthError::InvalidOAuthState);
        }

        let timer = std::time::Instant::now();
        let user_info = match provider {
            OAuthProvider::Google => self.exchange_google(code, &state_data.redirect_uri).await?,
            OAuthProvider::Apple => self.exchange_apple(code, &state_data.redirect_uri).await?,
            OAuthProvider::Facebook => {
                self.exchange_facebook(code, &state_data.redirect_uri)
                    .await?
            }
            OAuthProvider::WeChat => self.exchange_wechat(code, &state_data.redirect_uri).await?,
        };

        let (user, is_new_user) = self.upsert_user(provider, &user_info).await?;
        let token_pair = jwt::generate_token_pair(user.id, &user.email, &user.username)?;

        if let Some(producer) = &self.kafka {
            if is_new_user {
                if let Err(err) = producer
                    .publish_user_created(user.id, &user.email, &user.username)
                    .await
                {
                    tracing::warn!("Failed to publish user created event: {:?}", err);
                }
            }
        }

        record_oauth_login(provider.as_str(), true, timer.elapsed().as_millis() as u64);
        Ok(OAuthLogin {
            user_id: user.id,
            email: user.email,
            access_token: token_pair.access_token,
            refresh_token: token_pair.refresh_token,
            is_new_user,
        })
    }

    fn default_redirect_uri(&self, provider: &OAuthProvider) -> Option<String> {
        match provider {
            OAuthProvider::Google => self.config.google_redirect_uri.clone(),
            OAuthProvider::Apple => self.config.apple_redirect_uri.clone(),
            OAuthProvider::Facebook => self.config.facebook_redirect_uri.clone(),
            OAuthProvider::WeChat => self.config.wechat_redirect_uri.clone(),
        }
    }

    async fn store_state(&self, state: &str, payload: &OAuthStatePayload) -> AuthResult<()> {
        let mut conn = self.redis.lock().await.clone();
        let key = format!("nova:oauth:state:{state}");
        let value = serde_json::to_string(payload)
            .map_err(|e| AuthError::Internal(format!("Failed to serialize OAuth state: {}", e)))?;
        redis::cmd("SETEX")
            .arg(&key)
            .arg(OAUTH_STATE_TTL_SECONDS)
            .arg(value)
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| AuthError::Redis(e.to_string()))
    }

    async fn consume_state(&self, state: &str) -> AuthResult<OAuthStatePayload> {
        let mut conn = self.redis.lock().await.clone();
        let key = format!("nova:oauth:state:{state}");
        let data: Option<String> = redis::cmd("GET")
            .arg(&key)
            .query_async(&mut conn)
            .await
            .map_err(|e| AuthError::Redis(e.to_string()))?;
        if data.is_none() {
            return Err(AuthError::InvalidOAuthState);
        }
        redis::cmd("DEL")
            .arg(&key)
            .query_async::<_, ()>(&mut conn)
            .await
            .map_err(|e| AuthError::Redis(e.to_string()))?;

        serde_json::from_str::<OAuthStatePayload>(&data.unwrap())
            .map_err(|_| AuthError::InvalidOAuthState)
    }

    fn google_authorize_url(&self, redirect_uri: &str, state: &str) -> AuthResult<String> {
        let client_id = self
            .config
            .google_client_id
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("Google client ID missing".into()))?;

        let mut url = reqwest::Url::parse("https://accounts.google.com/o/oauth2/v2/auth")
            .expect("valid google auth url");
        url.query_pairs_mut()
            .append_pair("client_id", client_id)
            .append_pair("redirect_uri", redirect_uri)
            .append_pair("response_type", "code")
            .append_pair("scope", &self.config.default_scope)
            .append_pair("state", state)
            .append_pair("access_type", "offline")
            .append_pair("prompt", "consent");
        Ok(url.to_string())
    }

    fn apple_authorize_url(&self, redirect_uri: &str, state: &str) -> AuthResult<String> {
        let client_id = self.apple_client_id()?;
        let mut url = reqwest::Url::parse("https://appleid.apple.com/auth/authorize")
            .expect("valid apple auth url");
        url.query_pairs_mut()
            .append_pair("client_id", client_id)
            .append_pair("redirect_uri", redirect_uri)
            .append_pair("response_type", "code")
            .append_pair("response_mode", "form_post")
            .append_pair("scope", "name email")
            .append_pair("state", state);
        Ok(url.to_string())
    }

    fn facebook_authorize_url(&self, redirect_uri: &str, state: &str) -> AuthResult<String> {
        let app_id = self
            .config
            .facebook_app_id
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("Facebook app ID missing".into()))?;
        let mut url = reqwest::Url::parse("https://www.facebook.com/v17.0/dialog/oauth").unwrap();
        url.query_pairs_mut()
            .append_pair("client_id", app_id)
            .append_pair("redirect_uri", redirect_uri)
            .append_pair("state", state)
            .append_pair("response_type", "code")
            .append_pair("scope", "public_profile,email");
        Ok(url.to_string())
    }

    fn wechat_authorize_url(&self, redirect_uri: &str, state: &str) -> AuthResult<String> {
        let app_id = self
            .config
            .wechat_app_id
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("WeChat app ID missing".into()))?;
        let mut url = reqwest::Url::parse("https://open.weixin.qq.com/connect/qrconnect").unwrap();
        url.query_pairs_mut()
            .append_pair("appid", app_id)
            .append_pair("redirect_uri", redirect_uri)
            .append_pair("response_type", "code")
            .append_pair("scope", "snsapi_login")
            .append_pair("state", state);
        Ok(url.to_string())
    }

    async fn exchange_google(&self, code: &str, redirect_uri: &str) -> AuthResult<OAuthUserInfo> {
        #[derive(Deserialize)]
        struct TokenResponse {
            access_token: String,
            expires_in: Option<i64>,
            refresh_token: Option<String>,
            id_token: Option<String>,
            token_type: Option<String>,
        }

        #[derive(Deserialize)]
        struct GoogleUserInfo {
            sub: String,
            email: Option<String>,
            name: Option<String>,
            picture: Option<String>,
            email_verified: Option<bool>,
        }

        let client_id = self
            .config
            .google_client_id
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("Google client ID missing".into()))?;
        let client_secret = self
            .config
            .google_client_secret
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("Google client secret missing".into()))?;

        let mut params = HashMap::new();
        params.insert("code", code.to_string());
        params.insert("client_id", client_id.clone());
        params.insert("client_secret", client_secret.clone());
        params.insert("redirect_uri", redirect_uri.to_string());
        params.insert("grant_type", "authorization_code".to_string());

        let token_resp = self
            .http
            .post("https://oauth2.googleapis.com/token")
            .form(&params)
            .send()
            .await
            .map_err(|e| AuthError::OAuthError(format!("Google token request failed: {}", e)))?;

        if !token_resp.status().is_success() {
            return Err(AuthError::OAuthError(format!(
                "Google token request failed with status {}",
                token_resp.status()
            )));
        }

        let token: TokenResponse = token_resp.json().await.map_err(|e| {
            AuthError::OAuthError(format!("Failed to parse Google token response: {}", e))
        })?;

        let user_resp = self
            .http
            .get("https://openidconnect.googleapis.com/v1/userinfo")
            .bearer_auth(&token.access_token)
            .send()
            .await
            .map_err(|e| {
                AuthError::OAuthError(format!("Failed to fetch Google user info: {}", e))
            })?;

        if !user_resp.status().is_success() {
            return Err(AuthError::OAuthError(format!(
                "Google userinfo failed with status {}",
                user_resp.status()
            )));
        }

        let user: GoogleUserInfo = user_resp.json().await.map_err(|e| {
            AuthError::OAuthError(format!("Failed to parse Google user info: {}", e))
        })?;

        let email = user
            .email
            .ok_or_else(|| AuthError::OAuthError("Google response missing email".into()))?;

        Ok(OAuthUserInfo {
            provider: "google".into(),
            provider_user_id: user.sub,
            email,
            name: user.name,
            picture_url: user.picture,
            access_token: token.access_token,
            refresh_token: token.refresh_token,
            token_expires_at: token
                .expires_in
                .map(|secs| chrono::Utc::now().timestamp() + secs),
        })
    }

    async fn exchange_facebook(&self, code: &str, redirect_uri: &str) -> AuthResult<OAuthUserInfo> {
        #[derive(Deserialize)]
        struct TokenResponse {
            access_token: String,
            expires_in: Option<i64>,
            token_type: Option<String>,
        }

        #[derive(Deserialize)]
        struct FacebookUser {
            id: String,
            name: Option<String>,
            email: Option<String>,
        }

        let app_id = self
            .config
            .facebook_app_id
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("Facebook app ID missing".into()))?;
        let app_secret = self
            .config
            .facebook_app_secret
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("Facebook app secret missing".into()))?;

        let params = vec![
            ("client_id".to_string(), app_id.clone()),
            ("client_secret".to_string(), app_secret.clone()),
            ("redirect_uri".to_string(), redirect_uri.to_string()),
            ("code".to_string(), code.to_string()),
        ];

        let token_resp = self
            .http
            .get("https://graph.facebook.com/v17.0/oauth/access_token")
            .query(&params)
            .send()
            .await
            .map_err(|e| AuthError::OAuthError(format!("Facebook token request failed: {}", e)))?;

        if !token_resp.status().is_success() {
            return Err(AuthError::OAuthError(format!(
                "Facebook token request failed with status {}",
                token_resp.status()
            )));
        }

        let token: TokenResponse = token_resp.json().await.map_err(|e| {
            AuthError::OAuthError(format!("Failed to parse Facebook token response: {}", e))
        })?;

        let user_resp = self
            .http
            .get("https://graph.facebook.com/me")
            .query(&[("fields", "id,name,email")])
            .bearer_auth(&token.access_token)
            .send()
            .await
            .map_err(|e| {
                AuthError::OAuthError(format!("Failed to fetch Facebook user info: {}", e))
            })?;

        if !user_resp.status().is_success() {
            return Err(AuthError::OAuthError(format!(
                "Facebook userinfo failed with status {}",
                user_resp.status()
            )));
        }

        let user: FacebookUser = user_resp.json().await.map_err(|e| {
            AuthError::OAuthError(format!("Failed to parse Facebook user info: {}", e))
        })?;

        Ok(OAuthUserInfo {
            provider: "facebook".into(),
            provider_user_id: user.id,
            email: user
                .email
                .unwrap_or_else(|| format!("{}@facebook.com", Uuid::new_v4())),
            name: user.name,
            picture_url: None,
            access_token: token.access_token,
            refresh_token: None,
            token_expires_at: token
                .expires_in
                .map(|secs| chrono::Utc::now().timestamp() + secs),
        })
    }

    async fn exchange_wechat(&self, code: &str, _redirect_uri: &str) -> AuthResult<OAuthUserInfo> {
        #[derive(Deserialize)]
        struct TokenResponse {
            access_token: String,
            expires_in: Option<i64>,
            refresh_token: Option<String>,
            openid: String,
            scope: Option<String>,
        }

        #[derive(Deserialize)]
        struct WeChatUser {
            openid: String,
            nickname: Option<String>,
            headimgurl: Option<String>,
        }

        let app_id = self
            .config
            .wechat_app_id
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("WeChat app ID missing".into()))?;
        let app_secret = self
            .config
            .wechat_app_secret
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("WeChat app secret missing".into()))?;

        let params = vec![
            ("appid".to_string(), app_id.clone()),
            ("secret".to_string(), app_secret.clone()),
            ("code".to_string(), code.to_string()),
            ("grant_type".to_string(), "authorization_code".to_string()),
        ];

        let token_resp = self
            .http
            .get("https://api.weixin.qq.com/sns/oauth2/access_token")
            .query(&params)
            .send()
            .await
            .map_err(|e| AuthError::OAuthError(format!("WeChat token request failed: {}", e)))?;

        if !token_resp.status().is_success() {
            return Err(AuthError::OAuthError(format!(
                "WeChat token request failed with status {}",
                token_resp.status()
            )));
        }

        let token: TokenResponse = token_resp.json().await.map_err(|e| {
            AuthError::OAuthError(format!("Failed to parse WeChat token response: {}", e))
        })?;

        let user_resp = self
            .http
            .get("https://api.weixin.qq.com/sns/userinfo")
            .query(&[
                ("access_token", token.access_token.as_str()),
                ("openid", token.openid.as_str()),
            ])
            .send()
            .await
            .map_err(|e| {
                AuthError::OAuthError(format!("Failed to fetch WeChat user info: {}", e))
            })?;

        if !user_resp.status().is_success() {
            return Err(AuthError::OAuthError(format!(
                "WeChat userinfo failed with status {}",
                user_resp.status()
            )));
        }

        let user: WeChatUser = user_resp.json().await.map_err(|e| {
            AuthError::OAuthError(format!("Failed to parse WeChat user info: {}", e))
        })?;

        Ok(OAuthUserInfo {
            provider: "wechat".into(),
            provider_user_id: user.openid.clone(),
            email: format!("{}@wechat.nova", user.openid),
            name: user.nickname,
            picture_url: user.headimgurl,
            access_token: token.access_token,
            refresh_token: token.refresh_token,
            token_expires_at: token
                .expires_in
                .map(|secs| chrono::Utc::now().timestamp() + secs),
        })
    }

    async fn exchange_apple(&self, code: &str, redirect_uri: &str) -> AuthResult<OAuthUserInfo> {
        #[derive(Deserialize)]
        struct TokenResponse {
            access_token: String,
            expires_in: Option<i64>,
            refresh_token: Option<String>,
            id_token: String,
        }

        #[derive(Debug, Deserialize)]
        struct AppleIdClaims {
            sub: String,
            email: Option<String>,
        }

        let team_id = self
            .config
            .apple_team_id
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("Apple team ID missing".into()))?;
        let client_id = self.apple_client_id()?;
        let key_id = self.apple_key_id()?;
        let private_key = self
            .config
            .apple_private_key
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("Apple private key missing".into()))?;

        let client_secret = self.generate_apple_client_secret(
            team_id,
            client_id.as_str(),
            key_id.as_str(),
            private_key.as_str(),
        )?;

        let mut params = HashMap::new();
        params.insert("client_id", client_id.clone());
        params.insert("client_secret", client_secret.clone());
        params.insert("code", code.to_string());
        params.insert("grant_type", "authorization_code".to_string());
        params.insert("redirect_uri", redirect_uri.to_string());

        let token_resp = self
            .http
            .post("https://appleid.apple.com/auth/token")
            .form(&params)
            .send()
            .await
            .map_err(|e| AuthError::OAuthError(format!("Apple token request failed: {}", e)))?;

        if !token_resp.status().is_success() {
            return Err(AuthError::OAuthError(format!(
                "Apple token request failed with status {}",
                token_resp.status()
            )));
        }

        let token: TokenResponse = token_resp.json().await.map_err(|e| {
            AuthError::OAuthError(format!("Failed to parse Apple token response: {}", e))
        })?;

        let claims: AppleIdClaims = decode_jwt_claims(&token.id_token)?;

        let email = claims
            .email
            .unwrap_or_else(|| format!("{}@appleid.apple", claims.sub));

        Ok(OAuthUserInfo {
            provider: "apple".into(),
            provider_user_id: claims.sub,
            email,
            name: None,
            picture_url: None,
            access_token: token.access_token,
            refresh_token: token.refresh_token,
            token_expires_at: token
                .expires_in
                .map(|secs| chrono::Utc::now().timestamp() + secs),
        })
    }

    fn generate_apple_client_secret(
        &self,
        team_id: &str,
        client_id: &str,
        key_id: &str,
        private_key: &str,
    ) -> AuthResult<String> {
        use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
        use serde::Serialize;

        #[derive(Serialize)]
        struct Claims<'a> {
            iss: &'a str,
            sub: &'a str,
            aud: &'a str,
            iat: i64,
            exp: i64,
        }

        let now = chrono::Utc::now().timestamp();
        let claims = Claims {
            iss: team_id,
            sub: client_id,
            aud: "https://appleid.apple.com",
            iat: now,
            exp: now + 5 * 60, // 5 minutes
        };

        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(key_id.to_string());

        let key = EncodingKey::from_ec_pem(private_key.as_bytes()).map_err(|e| {
            AuthError::OAuthError(format!("Failed to parse Apple private key: {}", e))
        })?;

        encode(&header, &claims, &key).map_err(|e| {
            AuthError::OAuthError(format!("Failed to sign Apple client secret: {}", e))
        })
    }

    async fn upsert_user(
        &self,
        _provider: OAuthProvider,
        info: &OAuthUserInfo,
    ) -> AuthResult<(crate::models::user::User, bool)> {
        if let Some(existing) =
            oauth_repo::find_by_provider(&self.db, info.provider.as_str(), &info.provider_user_id)
                .await?
        {
            let user = users::find_by_id(&self.db, existing.user_id)
                .await?
                .ok_or(AuthError::UserNotFound)?;
            oauth_repo::update_tokens(
                &self.db,
                existing.id,
                &info.access_token,
                info.refresh_token.as_deref(),
                None,
                to_expiry(info.token_expires_at),
            )
            .await?;
            return Ok((user, false));
        }

        let mut is_new_user = false;

        let user = match users::find_by_email(&self.db, &info.email).await? {
            Some(user) => user,
            None => {
                let username = self.derive_username(&info.email);
                let random_password = format!("oauth-{}", Uuid::new_v4());
                let password_hash = password::hash_password(&random_password)?;
                let user =
                    users::create_user(&self.db, &info.email, &username, &password_hash).await?;
                record_registration(true);
                is_new_user = true;
                users::verify_email(&self.db, user.id).await?;
                user
            }
        };

        oauth_repo::create_connection(
            &self.db,
            user.id,
            info.provider.as_str(),
            &info.provider_user_id,
            Some(&info.email),
            info.name.as_deref(),
            info.picture_url.as_deref(),
            Some(&info.access_token),
            info.refresh_token.as_deref(),
            None,
            to_expiry(info.token_expires_at),
            None,
        )
        .await?;

        Ok((user, is_new_user))
    }

    fn derive_username(&self, email: &str) -> String {
        let base = email
            .split('@')
            .next()
            .unwrap_or("nova_user")
            .replace(['.', '+'], "_");
        format!("{base}_{}", &Uuid::new_v4().simple().to_string()[..6])
    }

    fn apple_client_id(&self) -> AuthResult<&String> {
        self.config
            .apple_client_id
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("Apple client ID missing".into()))
    }

    fn apple_key_id(&self) -> AuthResult<&String> {
        self.config
            .apple_key_id
            .as_ref()
            .ok_or_else(|| AuthError::OAuthError("Apple key ID missing".into()))
    }
}

fn to_expiry(ts: Option<i64>) -> Option<DateTime<Utc>> {
    ts.and_then(|secs| DateTime::from_timestamp(secs, 0))
}

fn decode_jwt_claims<T: DeserializeOwned>(token: &str) -> AuthResult<T> {
    let segments: Vec<&str> = token.split('.').collect();
    if segments.len() != 3 {
        return Err(AuthError::OAuthError("Invalid ID token format".into()));
    }

    let payload = URL_SAFE_NO_PAD
        .decode(segments[1])
        .map_err(|e| AuthError::OAuthError(format!("Failed to decode ID token payload: {}", e)))?;

    serde_json::from_slice(&payload)
        .map_err(|e| AuthError::OAuthError(format!("Failed to parse ID token payload: {}", e)))
}
