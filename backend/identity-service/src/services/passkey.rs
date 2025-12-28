//! Passkey (WebAuthn/FIDO2) Service
//!
//! Implements WebAuthn registration and authentication flows using webauthn-rs.
//! Challenges are stored in Redis with TTL for security.

use crate::config::PasskeySettings;
use crate::db;
use crate::error::{IdentityError, Result};
use crate::models::{CreatePasskeyCredential, PasskeyInfo, User};
use crate::services::{KafkaEventProducer, ZitadelService, ZitadelUserInfo};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use redis::AsyncCommands;
use redis_utils::SharedConnectionManager;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use tracing::{debug, error, info, warn};
use uuid::Uuid;
use webauthn_rs::prelude::*;

/// Redis key prefix for registration challenges
const REDIS_KEY_PREFIX_REG: &str = "nova:passkey:reg:";
/// Redis key prefix for authentication challenges
const REDIS_KEY_PREFIX_AUTH: &str = "nova:passkey:auth:";

/// Passkey Service for WebAuthn registration and authentication
pub struct PasskeyService {
    webauthn: Webauthn,
    db: PgPool,
    redis: SharedConnectionManager,
    challenge_ttl_secs: u64,
    #[allow(dead_code)]
    kafka: Option<KafkaEventProducer>,
    zitadel: Option<ZitadelService>,
}

/// Registration challenge state stored in Redis
#[derive(Debug, Serialize, Deserialize)]
struct RegistrationState {
    user_id: Uuid,
    passkey_registration: PasskeyRegistration,
    credential_name: Option<String>,
    device_type: Option<String>,
    os_version: Option<String>,
}

/// Authentication challenge state stored in Redis
#[derive(Debug, Serialize, Deserialize)]
struct AuthenticationState {
    passkey_authentication: PasskeyAuthentication,
    /// For discoverable credentials, user is determined after auth
    expected_user_id: Option<Uuid>,
}

/// Result of passkey registration
#[derive(Debug)]
pub struct PasskeyRegistrationResult {
    pub credential_id: Uuid,
    pub credential_name: Option<String>,
}

/// Result of passkey authentication
#[derive(Debug)]
pub struct PasskeyAuthenticationResult {
    pub user: User,
    pub credential_id: Uuid,
    pub is_new_session: bool,
}

impl PasskeyService {
    /// Create a new PasskeyService
    pub fn new(
        db: PgPool,
        redis: SharedConnectionManager,
        kafka: Option<KafkaEventProducer>,
        settings: PasskeySettings,
        zitadel: Option<ZitadelService>,
    ) -> Result<Self> {
        let rp_id = settings.rp_id.clone();
        let rp_origin = Url::parse(&settings.origin)
            .map_err(|e| IdentityError::Configuration(format!("Invalid PASSKEY_ORIGIN: {}", e)))?;

        let builder = WebauthnBuilder::new(&rp_id, &rp_origin)
            .map_err(|e| IdentityError::Configuration(format!("WebAuthn builder error: {}", e)))?
            .rp_name(&settings.rp_name);

        let webauthn = builder
            .build()
            .map_err(|e| IdentityError::Configuration(format!("WebAuthn build error: {}", e)))?;

        info!(
            rp_id = %settings.rp_id,
            rp_name = %settings.rp_name,
            origin = %settings.origin,
            "PasskeyService initialized"
        );

        Ok(Self {
            webauthn,
            db,
            redis,
            challenge_ttl_secs: settings.challenge_ttl_secs,
            kafka,
            zitadel,
        })
    }

    /// Start passkey registration for a user
    ///
    /// Returns PublicKeyCredentialCreationOptions to send to the client
    pub async fn start_registration(
        &self,
        user: &User,
        credential_name: Option<String>,
        device_type: Option<String>,
        os_version: Option<String>,
    ) -> Result<(CreationChallengeResponse, String)> {
        // Get existing credentials to exclude
        let existing_creds = db::passkey::find_by_user_id(&self.db, user.id).await?;
        let exclude_credentials: Vec<CredentialID> = existing_creds
            .iter()
            .map(|c| CredentialID::from(c.credential_id.clone()))
            .collect();

        // Create user unique ID from Nova user ID
        let user_unique_id = user.id.as_bytes().to_vec();

        // Start registration ceremony
        let (ccr, reg_state) = self
            .webauthn
            .start_passkey_registration(
                Uuid::from_bytes(
                    user_unique_id
                        .try_into()
                        .map_err(|_| IdentityError::Internal("Invalid user ID bytes".into()))?,
                ),
                &user.username,
                &user.username,
                Some(exclude_credentials),
            )
            .map_err(|e| {
                error!(error = %e, "Failed to start passkey registration");
                IdentityError::PasskeyRegistrationFailed(e.to_string())
            })?;

        // Generate challenge ID
        let challenge_id = Uuid::new_v4().to_string();

        // Store state in Redis
        let state = RegistrationState {
            user_id: user.id,
            passkey_registration: reg_state,
            credential_name,
            device_type,
            os_version,
        };

        let state_json = serde_json::to_string(&state).map_err(|e| {
            IdentityError::Internal(format!("Failed to serialize registration state: {}", e))
        })?;

        let key = format!("{}{}", REDIS_KEY_PREFIX_REG, challenge_id);
        let mut conn = self.redis.lock().await.clone();
        conn.set_ex::<_, _, ()>(&key, state_json, self.challenge_ttl_secs)
            .await
            .map_err(|e| IdentityError::Redis(e.to_string()))?;

        debug!(
            user_id = %user.id,
            challenge_id = %challenge_id,
            "Started passkey registration"
        );

        Ok((ccr, challenge_id))
    }

    /// Complete passkey registration
    ///
    /// Verifies the attestation response and stores the credential
    pub async fn complete_registration(
        &self,
        challenge_id: &str,
        attestation: RegisterPublicKeyCredential,
    ) -> Result<PasskeyRegistrationResult> {
        // Retrieve and delete state from Redis (one-time use)
        let key = format!("{}{}", REDIS_KEY_PREFIX_REG, challenge_id);
        let mut conn = self.redis.lock().await.clone();

        let state_json: Option<String> = conn
            .get_del(&key)
            .await
            .map_err(|e| IdentityError::Redis(e.to_string()))?;

        let state_json = state_json.ok_or(IdentityError::PasskeyChallengeExpired)?;

        let state: RegistrationState = serde_json::from_str(&state_json)
            .map_err(|_| IdentityError::InvalidPasskeyChallenge)?;

        // Complete registration ceremony
        let passkey = self
            .webauthn
            .finish_passkey_registration(&attestation, &state.passkey_registration)
            .map_err(|e| {
                warn!(error = %e, "Failed to complete passkey registration");
                IdentityError::PasskeyRegistrationFailed(e.to_string())
            })?;

        // Extract credential data
        let credential_id = passkey.cred_id().to_vec();
        let credential_id_base64 = URL_SAFE_NO_PAD.encode(&credential_id);

        // Check if credential already exists
        if db::passkey::credential_exists(&self.db, &credential_id_base64).await? {
            return Err(IdentityError::PasskeyAlreadyRegistered);
        }

        // Serialize passkey for storage (contains public key and credential metadata)
        let public_key = serde_json::to_vec(&passkey)
            .map_err(|e| IdentityError::Internal(format!("Failed to serialize passkey: {}", e)))?;

        // Create credential record
        // Note: backup_eligible and backup_state from attestation are not directly
        // accessible in webauthn-rs 0.5; we get them from AuthenticationResult during auth
        let create_data = CreatePasskeyCredential {
            user_id: state.user_id,
            credential_id,
            credential_id_base64,
            public_key,
            credential_name: state.credential_name.clone(),
            aaguid: None,           // AAGUID not directly accessible in this API version
            sign_count: 0,          // Initial sign count
            backup_eligible: false, // Updated after first authentication
            backup_state: false,
            transports: None,
            device_type: state.device_type,
            os_version: state.os_version,
        };

        let credential = db::passkey::create_credential(&self.db, &create_data).await?;

        info!(
            user_id = %state.user_id,
            credential_id = %credential.id,
            "Passkey registration completed"
        );

        Ok(PasskeyRegistrationResult {
            credential_id: credential.id,
            credential_name: state.credential_name,
        })
    }

    /// Start passkey authentication
    ///
    /// Currently requires user_id to get their credentials.
    /// Discoverable credentials (AutoFill) will be supported in a future version.
    pub async fn start_authentication(
        &self,
        user_id: Option<Uuid>,
    ) -> Result<(RequestChallengeResponse, String)> {
        // For now, we require user_id. Discoverable credentials would need
        // additional API support from webauthn-rs.
        let uid = user_id.ok_or_else(|| {
            IdentityError::PasskeyAuthenticationFailed(
                "User ID is required for authentication".to_string(),
            )
        })?;

        // Get user's credentials
        let credentials = db::passkey::find_by_user_id(&self.db, uid).await?;
        if credentials.is_empty() {
            return Err(IdentityError::NoPasskeyCredentials);
        }

        // Deserialize passkeys
        let passkeys: Vec<Passkey> = credentials
            .iter()
            .filter_map(|c| serde_json::from_slice(&c.public_key).ok())
            .collect();

        if passkeys.is_empty() {
            return Err(IdentityError::NoPasskeyCredentials);
        }

        let (rcr, auth_state) = self
            .webauthn
            .start_passkey_authentication(&passkeys)
            .map_err(|e| {
                error!(error = %e, "Failed to start passkey authentication");
                IdentityError::PasskeyAuthenticationFailed(e.to_string())
            })?;

        // Generate challenge ID
        let challenge_id = Uuid::new_v4().to_string();

        // Store state in Redis
        let state = AuthenticationState {
            passkey_authentication: auth_state,
            expected_user_id: Some(uid),
        };

        let state_json = serde_json::to_string(&state).map_err(|e| {
            IdentityError::Internal(format!("Failed to serialize auth state: {}", e))
        })?;

        let key = format!("{}{}", REDIS_KEY_PREFIX_AUTH, challenge_id);
        let mut conn = self.redis.lock().await.clone();
        conn.set_ex::<_, _, ()>(&key, state_json, self.challenge_ttl_secs)
            .await
            .map_err(|e| IdentityError::Redis(e.to_string()))?;

        debug!(
            user_id = %uid,
            challenge_id = %challenge_id,
            "Started passkey authentication"
        );

        Ok((rcr, challenge_id))
    }

    /// Complete passkey authentication
    ///
    /// Verifies the assertion and returns the authenticated user
    pub async fn complete_authentication(
        &self,
        challenge_id: &str,
        assertion: PublicKeyCredential,
    ) -> Result<PasskeyAuthenticationResult> {
        // Retrieve and delete state from Redis
        let key = format!("{}{}", REDIS_KEY_PREFIX_AUTH, challenge_id);
        let mut conn = self.redis.lock().await.clone();

        let state_json: Option<String> = conn
            .get_del(&key)
            .await
            .map_err(|e| IdentityError::Redis(e.to_string()))?;

        let state_json = state_json.ok_or(IdentityError::PasskeyChallengeExpired)?;

        let state: AuthenticationState = serde_json::from_str(&state_json)
            .map_err(|_| IdentityError::InvalidPasskeyChallenge)?;

        // Find the credential in database
        let credential_id_bytes: &[u8] = assertion.id.as_ref();
        let credential_id_base64 = URL_SAFE_NO_PAD.encode(credential_id_bytes);

        let stored_cred = db::passkey::find_by_credential_id(&self.db, &credential_id_base64)
            .await?
            .ok_or(IdentityError::PasskeyCredentialNotFound)?;

        // Deserialize stored passkey
        let passkey: Passkey = serde_json::from_slice(&stored_cred.public_key)
            .map_err(|e| IdentityError::Internal(format!("Invalid stored passkey: {}", e)))?;

        // Verify assertion
        let auth_result = self
            .webauthn
            .finish_passkey_authentication(&assertion, &state.passkey_authentication)
            .map_err(|e| {
                warn!(
                    error = %e,
                    credential_id = %credential_id_base64,
                    "Passkey authentication failed"
                );
                IdentityError::PasskeyAuthenticationFailed(e.to_string())
            })?;

        // Update credential counter if it has increased
        let new_counter = auth_result.counter();
        if new_counter > stored_cred.sign_count as u32 {
            db::passkey::update_sign_count(&self.db, stored_cred.id, new_counter as i64).await?;
        } else if new_counter > 0 && new_counter <= stored_cred.sign_count as u32 {
            // Possible cloned authenticator - log warning but allow for now
            warn!(
                credential_id = %stored_cred.id,
                stored_count = stored_cred.sign_count,
                received_count = new_counter,
                "Sign counter regression detected - possible cloned authenticator"
            );
        }

        // Update backup state if changed (webauthn-rs provides this in auth result)
        let backup_eligible = auth_result.backup_eligible();
        let backup_state = auth_result.backup_state();
        if backup_eligible != stored_cred.backup_eligible
            || backup_state != stored_cred.backup_state
        {
            db::passkey::update_backup_state(
                &self.db,
                stored_cred.id,
                backup_eligible,
                backup_state,
            )
            .await?;
        }

        // Keep passkey variable to avoid unused warning
        let _ = passkey;

        // Fetch user
        let user = db::users::find_by_id(&self.db, stored_cred.user_id)
            .await?
            .ok_or(IdentityError::UserNotFound)?;

        info!(
            user_id = %user.id,
            credential_id = %stored_cred.id,
            "Passkey authentication completed"
        );

        Ok(PasskeyAuthenticationResult {
            user,
            credential_id: stored_cred.id,
            is_new_session: true,
        })
    }

    /// List all passkey credentials for a user
    pub async fn list_credentials(&self, user_id: Uuid) -> Result<Vec<PasskeyInfo>> {
        let credentials = db::passkey::find_by_user_id(&self.db, user_id).await?;
        Ok(credentials.into_iter().map(PasskeyInfo::from).collect())
    }

    /// Revoke a passkey credential
    pub async fn revoke_credential(
        &self,
        credential_id: Uuid,
        user_id: Uuid,
        reason: Option<&str>,
    ) -> Result<()> {
        db::passkey::revoke_credential(&self.db, credential_id, user_id, reason).await?;
        info!(
            user_id = %user_id,
            credential_id = %credential_id,
            reason = ?reason,
            "Passkey credential revoked"
        );
        Ok(())
    }

    /// Rename a passkey credential
    pub async fn rename_credential(
        &self,
        credential_id: Uuid,
        user_id: Uuid,
        new_name: &str,
    ) -> Result<()> {
        db::passkey::update_credential_name(&self.db, credential_id, user_id, new_name).await?;
        debug!(
            user_id = %user_id,
            credential_id = %credential_id,
            new_name = %new_name,
            "Passkey credential renamed"
        );
        Ok(())
    }

    /// Check if user has any passkey credentials
    pub async fn user_has_passkeys(&self, user_id: Uuid) -> Result<bool> {
        db::passkey::has_passkey_credentials(&self.db, user_id).await
    }

    /// Sync new passkey user to Zitadel (if configured)
    pub async fn sync_to_zitadel(&self, user: &User) -> Result<()> {
        if let Some(zitadel) = &self.zitadel {
            let zitadel_user = ZitadelUserInfo {
                nova_user_id: user.id,
                username: user.username.clone(),
                email: user.email.clone(),
                display_name: user.display_name.clone(),
                given_name: None, // Not available from passkey registration
                family_name: None,
                picture_url: user.avatar_url.clone(),
                idp_link: None, // Passkey is local auth, no external IdP
            };

            match zitadel.provision_user(&zitadel_user).await {
                Ok(_) => {
                    info!(user_id = %user.id, "User synced to Zitadel");
                }
                Err(e) => {
                    warn!(
                        user_id = %user.id,
                        error = %e,
                        "Failed to sync user to Zitadel (non-fatal)"
                    );
                }
            }
        }
        Ok(())
    }
}
