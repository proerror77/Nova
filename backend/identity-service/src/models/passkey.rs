//! Passkey (WebAuthn/FIDO2) data models

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

/// Passkey credential record in database
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct PasskeyCredential {
    pub id: Uuid,
    pub user_id: Uuid,
    /// Raw credential ID from authenticator
    pub credential_id: Vec<u8>,
    /// Base64URL encoded credential ID for efficient lookups
    pub credential_id_base64: String,
    /// COSE encoded public key for signature verification
    pub public_key: Vec<u8>,
    /// User-friendly name (e.g., "iPhone 15 Pro")
    pub credential_name: Option<String>,
    /// Authenticator Attestation GUID (16 bytes)
    pub aaguid: Option<Vec<u8>>,
    /// Signature counter for clone detection
    pub sign_count: i64,
    /// Whether credential can be backed up (iCloud Keychain)
    pub backup_eligible: bool,
    /// Whether credential is currently backed up
    pub backup_state: bool,
    /// Supported transports: internal, hybrid, usb, ble, nfc
    pub transports: Option<serde_json::Value>,
    /// Device type: iPhone, iPad, Mac, etc.
    pub device_type: Option<String>,
    /// OS version: e.g., '18.0'
    pub os_version: Option<String>,
    /// Is credential active
    pub is_active: bool,
    /// When the credential was revoked
    pub revoked_at: Option<DateTime<Utc>>,
    /// Reason for revocation
    pub revoke_reason: Option<String>,
    /// When the credential was created
    pub created_at: DateTime<Utc>,
    /// When the credential was last updated
    pub updated_at: DateTime<Utc>,
    /// When the credential was last used
    pub last_used_at: Option<DateTime<Utc>>,
}

impl PasskeyCredential {
    /// Check if credential is usable for authentication
    pub fn is_usable(&self) -> bool {
        self.is_active && self.revoked_at.is_none()
    }

    /// Get transports as a list of strings
    pub fn get_transports(&self) -> Vec<String> {
        self.transports
            .as_ref()
            .and_then(|v| serde_json::from_value::<Vec<String>>(v.clone()).ok())
            .unwrap_or_default()
    }
}

/// DTO for creating a new passkey credential
#[derive(Debug, Clone)]
pub struct CreatePasskeyCredential {
    pub user_id: Uuid,
    pub credential_id: Vec<u8>,
    pub credential_id_base64: String,
    pub public_key: Vec<u8>,
    pub credential_name: Option<String>,
    pub aaguid: Option<Vec<u8>>,
    pub sign_count: i64,
    pub backup_eligible: bool,
    pub backup_state: bool,
    pub transports: Option<serde_json::Value>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
}

/// DTO for passkey list response (excludes sensitive data)
#[derive(Debug, Clone, Serialize)]
pub struct PasskeyInfo {
    pub id: Uuid,
    pub credential_name: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
    pub backup_eligible: bool,
    pub backup_state: bool,
    pub transports: Vec<String>,
    pub created_at: DateTime<Utc>,
    pub last_used_at: Option<DateTime<Utc>>,
    pub is_active: bool,
}

impl From<PasskeyCredential> for PasskeyInfo {
    fn from(cred: PasskeyCredential) -> Self {
        // Extract transports first (before any field moves)
        let transports = cred.get_transports();
        Self {
            id: cred.id,
            credential_name: cred.credential_name,
            device_type: cred.device_type,
            os_version: cred.os_version,
            backup_eligible: cred.backup_eligible,
            backup_state: cred.backup_state,
            transports,
            created_at: cred.created_at,
            last_used_at: cred.last_used_at,
            is_active: cred.is_active,
        }
    }
}

/// Passkey registration request from client
#[derive(Debug, Deserialize)]
pub struct StartPasskeyRegistrationRequest {
    pub credential_name: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
}

/// Passkey registration options response
#[derive(Debug, Serialize)]
pub struct PasskeyRegistrationOptions {
    /// JSON-encoded PublicKeyCredentialCreationOptions
    pub options: serde_json::Value,
    /// Challenge identifier for correlation
    pub challenge_id: String,
}

/// Passkey registration completion request
#[derive(Debug, Deserialize)]
pub struct CompletePasskeyRegistrationRequest {
    /// Challenge identifier from start
    pub challenge_id: String,
    /// Attestation response from authenticator (JSON-encoded)
    pub attestation_response: serde_json::Value,
    pub credential_name: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
}

/// Passkey authentication start request
#[derive(Debug, Deserialize)]
pub struct StartPasskeyAuthenticationRequest {
    /// Optional user identifier (for non-discoverable flow)
    pub user_id: Option<String>,
}

/// Passkey authentication options response
#[derive(Debug, Serialize)]
pub struct PasskeyAuthenticationOptions {
    /// JSON-encoded PublicKeyCredentialRequestOptions
    pub options: serde_json::Value,
    /// Challenge identifier for correlation
    pub challenge_id: String,
}

/// Passkey authentication completion request
#[derive(Debug, Deserialize)]
pub struct CompletePasskeyAuthenticationRequest {
    /// Challenge identifier from start
    pub challenge_id: String,
    /// Assertion response from authenticator (JSON-encoded)
    pub assertion_response: serde_json::Value,
}
