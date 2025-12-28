/// APNs Authentication Mode
#[derive(Debug, Clone)]
pub enum ApnsAuthMode {
    /// Certificate-based authentication (.p12 file)
    Certificate {
        path: String,
        passphrase: Option<String>,
    },
    /// Token-based (JWT) authentication (.p8 key file)
    Token {
        key_path: String,
        key_id: String,
        team_id: String,
    },
}

/// APNs Configuration
#[derive(Debug, Clone)]
pub struct ApnsConfig {
    pub auth_mode: ApnsAuthMode,
    pub bundle_id: String,
    pub is_production: bool,
}

impl ApnsConfig {
    /// Create new APNs configuration with certificate authentication (legacy .p12)
    pub fn new(certificate_path: String, bundle_id: String, is_production: bool) -> Self {
        Self {
            auth_mode: ApnsAuthMode::Certificate {
                path: certificate_path,
                passphrase: None,
            },
            bundle_id,
            is_production,
        }
    }

    /// Create new APNs configuration with token-based JWT authentication (.p8 key)
    pub fn with_token(
        key_path: String,
        key_id: String,
        team_id: String,
        bundle_id: String,
        is_production: bool,
    ) -> Self {
        Self {
            auth_mode: ApnsAuthMode::Token {
                key_path,
                key_id,
                team_id,
            },
            bundle_id,
            is_production,
        }
    }

    /// Set certificate passphrase (only applies to Certificate auth mode)
    pub fn with_passphrase(mut self, pass: String) -> Self {
        if let ApnsAuthMode::Certificate {
            passphrase: ref mut p,
            ..
        } = self.auth_mode
        {
            *p = Some(pass);
        }
        self
    }

    /// Get APNs API endpoint based on environment
    pub fn endpoint(&self) -> &str {
        if self.is_production {
            "api.push.apple.com"
        } else {
            "api.sandbox.push.apple.com"
        }
    }
}
