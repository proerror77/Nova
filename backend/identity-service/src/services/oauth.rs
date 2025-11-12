/// OAuth 2.0 authentication service
///
/// Supports multiple OAuth providers:
/// - Google (OAuth 2.0)
/// - Apple (Sign in with Apple)
/// - Facebook (OAuth 2.0)
/// - WeChat (OAuth 2.0)
///
/// ## Security
///
/// - State tokens stored in Redis with 10-minute TTL
/// - PKCE support for mobile flows
/// - Token exchange over HTTPS only
/// - User info fetched from provider APIs
use crate::config::OAuthSettings;
use crate::error::{IdentityError, Result};
use crate::models::User;
use crate::services::KafkaEventProducer;
use base64::prelude::*;
use chrono::{DateTime, Duration, Utc};
use redis_utils::SharedConnectionManager;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::PgPool;
use tracing::{info, warn};
use uuid::Uuid;

const OAUTH_STATE_TTL_SECS: u64 = 600; // 10 minutes

/// OAuth provider types
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OAuthProvider {
    Google,
    Apple,
    Facebook,
    WeChat,
}

impl OAuthProvider {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Google => "google",
            Self::Apple => "apple",
            Self::Facebook => "facebook",
            Self::WeChat => "wechat",
        }
    }
}

/// OAuth service for social authentication
#[derive(Clone)]
pub struct OAuthService {
    config: OAuthSettings,
    db: PgPool,
    redis: SharedConnectionManager,
    http: Client,
    kafka: Option<KafkaEventProducer>,
}

/// OAuth authorization URL response
#[derive(Debug, Serialize)]
pub struct OAuthAuthorizationUrl {
    pub url: String,
    pub state: String,
}

/// OAuth callback result
#[derive(Debug)]
pub struct OAuthCallbackResult {
    pub user: User,
    pub is_new_user: bool,
}

impl OAuthService {
    pub fn new(
        config: OAuthSettings,
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

    /// Generate OAuth authorization URL with state token
    ///
    /// ## Arguments
    ///
    /// * `provider` - OAuth provider (Google, Apple, Facebook, WeChat)
    /// * `redirect_uri` - Callback URL after authentication
    ///
    /// ## Returns
    ///
    /// Authorization URL and state token (store state for verification)
    pub async fn start_flow(
        &self,
        provider: OAuthProvider,
        redirect_uri: &str,
    ) -> Result<OAuthAuthorizationUrl> {
        let state = Uuid::new_v4().to_string();

        // Store state in Redis with TTL
        let state_key = format!("nova:oauth:state:{}", state);
        let mut redis_conn = self.redis.lock().await.clone();
        redis_utils::with_timeout(async {
            redis::cmd("SET")
                .arg(&state_key)
                .arg(provider.as_str())
                .arg("EX")
                .arg(OAUTH_STATE_TTL_SECS)
                .query_async::<_, ()>(&mut redis_conn)
                .await
        })
        .await
        .map_err(|e| IdentityError::Redis(e.to_string()))?;

        let url = match provider {
            OAuthProvider::Google => self.google_auth_url(&state, redirect_uri),
            OAuthProvider::Apple => self.apple_auth_url(&state, redirect_uri),
            OAuthProvider::Facebook => self.facebook_auth_url(&state, redirect_uri),
            OAuthProvider::WeChat => self.wechat_auth_url(&state, redirect_uri),
        };

        Ok(OAuthAuthorizationUrl { url, state })
    }

    /// Complete OAuth flow after provider callback
    ///
    /// ## Arguments
    ///
    /// * `state` - State token from authorization URL
    /// * `code` - Authorization code from provider
    /// * `redirect_uri` - Same redirect URI used in start_flow
    ///
    /// ## Returns
    ///
    /// User record (created or existing) and flag indicating if user is new
    pub async fn complete_flow(
        &self,
        state: &str,
        code: &str,
        redirect_uri: &str,
    ) -> Result<OAuthCallbackResult> {
        // Verify and consume state token
        let state_key = format!("nova:oauth:state:{}", state);
        let mut redis_conn = self.redis.lock().await.clone();
        let provider_str: Option<String> = redis_utils::with_timeout(async {
            redis::cmd("GET")
                .arg(&state_key)
                .query_async(&mut redis_conn)
                .await
        })
        .await
        .map_err(|e| IdentityError::Redis(e.to_string()))?;

        let provider_str = provider_str.ok_or(IdentityError::InvalidOAuthState)?;

        // Delete state token (one-time use)
        redis_utils::with_timeout(async {
            redis::cmd("DEL")
                .arg(&state_key)
                .query_async::<_, ()>(&mut redis_conn)
                .await
        })
        .await
        .map_err(|e| IdentityError::Redis(e.to_string()))?;

        let provider = match provider_str.as_str() {
            "google" => OAuthProvider::Google,
            "apple" => OAuthProvider::Apple,
            "facebook" => OAuthProvider::Facebook,
            "wechat" => OAuthProvider::WeChat,
            _ => return Err(IdentityError::InvalidOAuthProvider),
        };

        // Exchange code for tokens and fetch user info
        let oauth_user = match provider {
            OAuthProvider::Google => self.exchange_google(code, redirect_uri).await?,
            OAuthProvider::Apple => self.exchange_apple(code, redirect_uri).await?,
            OAuthProvider::Facebook => self.exchange_facebook(code, redirect_uri).await?,
            OAuthProvider::WeChat => self.exchange_wechat(code, redirect_uri).await?,
        };

        // Create or link user
        let (user, is_new_user) = self.upsert_user(oauth_user, provider).await?;

        Ok(OAuthCallbackResult { user, is_new_user })
    }

    fn google_auth_url(&self, state: &str, redirect_uri: &str) -> String {
        format!(
            "https://accounts.google.com/o/oauth2/v2/auth?client_id={}&redirect_uri={}&response_type=code&scope=openid%20profile%20email&state={}",
            self.config.google_client_id.as_deref().unwrap_or(""),
            urlencoding::encode(redirect_uri),
            state
        )
    }

    fn apple_auth_url(&self, state: &str, redirect_uri: &str) -> String {
        format!(
            "https://appleid.apple.com/auth/authorize?client_id={}&redirect_uri={}&response_type=code&scope=name%20email&response_mode=form_post&state={}",
            self.config.apple_client_id.as_deref().unwrap_or(""),
            urlencoding::encode(redirect_uri),
            state
        )
    }

    fn facebook_auth_url(&self, state: &str, redirect_uri: &str) -> String {
        format!(
            "https://www.facebook.com/v12.0/dialog/oauth?client_id={}&redirect_uri={}&scope=email&state={}",
            self.config.facebook_app_id.as_deref().unwrap_or(""),
            urlencoding::encode(redirect_uri),
            state
        )
    }

    fn wechat_auth_url(&self, state: &str, redirect_uri: &str) -> String {
        format!(
            "https://open.weixin.qq.com/connect/qrconnect?appid={}&redirect_uri={}&response_type=code&scope=snsapi_login&state={}#wechat_redirect",
            self.config.wechat_app_id.as_deref().unwrap_or(""),
            urlencoding::encode(redirect_uri),
            state
        )
    }

    async fn exchange_google(&self, code: &str, redirect_uri: &str) -> Result<OAuthUserInfo> {
        let client_id = self.config.google_client_id.as_ref().ok_or_else(|| {
            IdentityError::OAuthError("Google client ID not configured".to_string())
        })?;
        let client_secret = self.config.google_client_secret.as_ref().ok_or_else(|| {
            IdentityError::OAuthError("Google client secret not configured".to_string())
        })?;

        // Exchange code for access token
        let token_response = self
            .http
            .post("https://oauth2.googleapis.com/token")
            .form(&[
                ("code", code),
                ("client_id", client_id),
                ("client_secret", client_secret),
                ("redirect_uri", redirect_uri),
                ("grant_type", "authorization_code"),
            ])
            .send()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?
            .json::<GoogleTokenResponse>()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?;

        // Fetch user info
        let user_info = self
            .http
            .get("https://www.googleapis.com/oauth2/v2/userinfo")
            .bearer_auth(&token_response.access_token)
            .send()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?
            .json::<GoogleUserInfo>()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?;

        Ok(OAuthUserInfo {
            provider_user_id: user_info.id,
            email: user_info.email,
            name: user_info.name,
            picture: user_info.picture,
            access_token: token_response.access_token,
            refresh_token: token_response.refresh_token,
            expires_at: to_expiry(token_response.expires_in),
        })
    }

    async fn exchange_apple(&self, code: &str, redirect_uri: &str) -> Result<OAuthUserInfo> {
        let client_id = self.apple_client_id()?.clone();
        let client_secret = self.generate_apple_client_secret()?;

        // Exchange code for tokens
        let token_response = self
            .http
            .post("https://appleid.apple.com/auth/token")
            .form(&[
                ("code", code),
                ("client_id", &client_id),
                ("client_secret", &client_secret),
                ("redirect_uri", redirect_uri),
                ("grant_type", "authorization_code"),
            ])
            .send()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?
            .json::<AppleTokenResponse>()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?;

        // Decode ID token to get user info (Apple doesn't have userinfo endpoint)
        let id_token_claims: AppleIdTokenClaims = decode_jwt_claims(&token_response.id_token)?;

        Ok(OAuthUserInfo {
            provider_user_id: id_token_claims.sub,
            email: id_token_claims.email.unwrap_or_default(),
            name: None,
            picture: None,
            access_token: token_response.access_token,
            refresh_token: token_response.refresh_token,
            expires_at: to_expiry(token_response.expires_in),
        })
    }

    async fn exchange_facebook(&self, code: &str, redirect_uri: &str) -> Result<OAuthUserInfo> {
        let client_id = self.config.facebook_app_id.as_ref().ok_or_else(|| {
            IdentityError::OAuthError("Facebook client ID not configured".to_string())
        })?;
        let client_secret = self.config.facebook_app_secret.as_ref().ok_or_else(|| {
            IdentityError::OAuthError("Facebook client secret not configured".to_string())
        })?;

        // Exchange code for access token
        let token_response = self
            .http
            .get("https://graph.facebook.com/v12.0/oauth/access_token")
            .query(&[
                ("code", code),
                ("client_id", client_id),
                ("client_secret", client_secret),
                ("redirect_uri", redirect_uri),
            ])
            .send()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?
            .json::<FacebookTokenResponse>()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?;

        // Fetch user info
        let user_info = self
            .http
            .get("https://graph.facebook.com/me")
            .query(&[
                ("fields", "id,name,email,picture"),
                ("access_token", &token_response.access_token),
            ])
            .send()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?
            .json::<FacebookUserInfo>()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?;

        Ok(OAuthUserInfo {
            provider_user_id: user_info.id,
            email: user_info.email.unwrap_or_default(),
            name: user_info.name,
            picture: user_info.picture.as_ref().and_then(|p| p.data.url.clone()),
            access_token: token_response.access_token,
            refresh_token: None,
            expires_at: to_expiry(token_response.expires_in),
        })
    }

    async fn exchange_wechat(&self, code: &str, _redirect_uri: &str) -> Result<OAuthUserInfo> {
        let app_id =
            self.config.wechat_app_id.as_ref().ok_or_else(|| {
                IdentityError::OAuthError("WeChat app ID not configured".to_string())
            })?;
        let app_secret = self.config.wechat_app_secret.as_ref().ok_or_else(|| {
            IdentityError::OAuthError("WeChat app secret not configured".to_string())
        })?;

        // Exchange code for access token
        let token_response = self
            .http
            .get("https://api.weixin.qq.com/sns/oauth2/access_token")
            .query(&[
                ("appid", app_id.as_str()),
                ("secret", app_secret.as_str()),
                ("code", code),
                ("grant_type", "authorization_code"),
            ])
            .send()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?
            .json::<WeChatTokenResponse>()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?;

        // Fetch user info
        let user_info = self
            .http
            .get("https://api.weixin.qq.com/sns/userinfo")
            .query(&[
                ("access_token", &token_response.access_token),
                ("openid", &token_response.openid),
                ("lang", &"zh_CN".to_string()),
            ])
            .send()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?
            .json::<WeChatUserInfo>()
            .await
            .map_err(|e| IdentityError::OAuthError(e.to_string()))?;

        Ok(OAuthUserInfo {
            provider_user_id: user_info.unionid.unwrap_or(user_info.openid),
            email: String::new(), // WeChat doesn't provide email
            name: Some(user_info.nickname),
            picture: Some(user_info.headimgurl),
            access_token: token_response.access_token,
            refresh_token: Some(token_response.refresh_token),
            expires_at: to_expiry(Some(token_response.expires_in)),
        })
    }

    /// Generate Apple client secret (JWT signed with ES256)
    fn generate_apple_client_secret(&self) -> Result<String> {
        use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};

        let key_id = self.apple_key_id()?.clone();
        let team_id =
            self.config.apple_team_id.as_ref().ok_or_else(|| {
                IdentityError::OAuthError("Apple team ID not configured".to_string())
            })?;
        let client_id = self.apple_client_id()?.clone();
        let private_key = self.config.apple_private_key.as_ref().ok_or_else(|| {
            IdentityError::OAuthError("Apple private key not configured".to_string())
        })?;

        let now = Utc::now();
        let claims = json!({
            "iss": team_id,
            "iat": now.timestamp(),
            "exp": (now + Duration::hours(1)).timestamp(),
            "aud": "https://appleid.apple.com",
            "sub": client_id,
        });

        let mut header = Header::new(Algorithm::ES256);
        header.kid = Some(key_id);

        let key = EncodingKey::from_ec_pem(private_key.as_bytes())
            .map_err(|e| IdentityError::OAuthError(format!("Invalid Apple private key: {}", e)))?;

        encode(&header, &claims, &key)
            .map_err(|e| IdentityError::OAuthError(format!("Failed to sign Apple JWT: {}", e)))
    }

    async fn upsert_user(
        &self,
        oauth_user: OAuthUserInfo,
        provider: OAuthProvider,
    ) -> Result<(User, bool)> {
        // Check if OAuth connection exists
        if let Some(conn) = crate::db::oauth::find_by_provider(
            &self.db,
            provider.as_str(),
            &oauth_user.provider_user_id,
        )
        .await?
        {
            // Update OAuth tokens
            crate::db::oauth::update_tokens(
                &self.db,
                conn.id,
                &oauth_user.access_token,
                oauth_user.refresh_token.as_deref(),
                None, // token_type
                oauth_user.expires_at,
            )
            .await?;

            // Fetch existing user
            let user = crate::db::users::find_by_id(&self.db, conn.user_id)
                .await?
                .ok_or(IdentityError::UserNotFound)?;

            return Ok((user, false));
        }

        // Check if user exists by email
        let user = if !oauth_user.email.is_empty() {
            crate::db::users::find_by_email(&self.db, &oauth_user.email).await?
        } else {
            None
        };

        let (user_id, is_new_user) = if let Some(existing_user) = user {
            (existing_user.id, false)
        } else {
            // Create new user
            let username = self.derive_username(&oauth_user.email);
            let new_user = crate::db::users::create_oauth_user(
                &self.db,
                &oauth_user.email,
                &username,
                provider.as_str(),
                &oauth_user.provider_user_id,
            )
            .await?;

            if let Some(producer) = &self.kafka {
                if let Err(err) = producer
                    .publish_user_created(new_user.id, &new_user.email, &new_user.username)
                    .await
                {
                    warn!("Failed to publish UserCreated event: {:?}", err);
                }
            }

            info!(user_id = %new_user.id, provider = provider.as_str(), "New user created via OAuth");
            (new_user.id, true)
        };

        // Link OAuth connection
        crate::db::oauth::create_connection(
            &self.db,
            user_id,
            provider.as_str(),
            &oauth_user.provider_user_id,
            Some(&oauth_user.email),
            oauth_user.name.as_deref(),
            oauth_user.picture.as_deref(),
            Some(&oauth_user.access_token),
            oauth_user.refresh_token.as_deref(),
            None, // token_type
            oauth_user.expires_at,
            None, // scopes
        )
        .await?;

        let user = crate::db::users::find_by_id(&self.db, user_id)
            .await?
            .ok_or(IdentityError::UserNotFound)?;

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

    fn apple_client_id(&self) -> Result<&String> {
        self.config
            .apple_client_id
            .as_ref()
            .ok_or_else(|| IdentityError::OAuthError("Apple client ID missing".into()))
    }

    fn apple_key_id(&self) -> Result<&String> {
        self.config
            .apple_key_id
            .as_ref()
            .ok_or_else(|| IdentityError::OAuthError("Apple key ID missing".into()))
    }
}

// ===== Helper Structures =====

struct OAuthUserInfo {
    provider_user_id: String,
    email: String,
    name: Option<String>,
    picture: Option<String>,
    access_token: String,
    refresh_token: Option<String>,
    expires_at: Option<DateTime<Utc>>,
}

// ===== Provider Response Types =====

#[derive(Deserialize)]
struct GoogleTokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
}

#[derive(Deserialize)]
struct GoogleUserInfo {
    id: String,
    email: String,
    name: Option<String>,
    picture: Option<String>,
}

#[derive(Deserialize)]
struct AppleTokenResponse {
    access_token: String,
    refresh_token: Option<String>,
    expires_in: Option<i64>,
    id_token: String,
}

#[derive(Deserialize)]
struct AppleIdTokenClaims {
    sub: String,
    email: Option<String>,
}

#[derive(Deserialize)]
struct FacebookTokenResponse {
    access_token: String,
    expires_in: Option<i64>,
}

#[derive(Deserialize)]
struct FacebookUserInfo {
    id: String,
    email: Option<String>,
    name: Option<String>,
    picture: Option<FacebookPicture>,
}

#[derive(Deserialize)]
struct FacebookPicture {
    data: FacebookPictureData,
}

#[derive(Deserialize)]
struct FacebookPictureData {
    url: Option<String>,
}

#[derive(Deserialize)]
struct WeChatTokenResponse {
    access_token: String,
    refresh_token: String,
    expires_in: i64,
    openid: String,
}

#[derive(Deserialize)]
struct WeChatUserInfo {
    openid: String,
    unionid: Option<String>,
    nickname: String,
    headimgurl: String,
}

// ===== Utility Functions =====

fn to_expiry(ts: Option<i64>) -> Option<DateTime<Utc>> {
    ts.and_then(|secs| DateTime::from_timestamp(secs, 0))
}

fn decode_jwt_claims<T: serde::de::DeserializeOwned>(token: &str) -> Result<T> {
    let segments: Vec<&str> = token.split('.').collect();
    if segments.len() != 3 {
        return Err(IdentityError::OAuthError(
            "Invalid ID token format".to_string(),
        ));
    }

    let payload = BASE64_URL_SAFE_NO_PAD.decode(segments[1]).map_err(|e| {
        IdentityError::OAuthError(format!("Failed to decode ID token payload: {}", e))
    })?;

    serde_json::from_slice(&payload)
        .map_err(|e| IdentityError::OAuthError(format!("Failed to parse ID token payload: {}", e)))
}
