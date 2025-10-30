/// APNs Configuration
#[derive(Debug, Clone)]
pub struct ApnsConfig {
    pub certificate_path: String,
    pub certificate_passphrase: Option<String>,
    pub bundle_id: String,
    pub is_production: bool,
}

impl ApnsConfig {
    /// Create new APNs configuration
    pub fn new(
        certificate_path: String,
        bundle_id: String,
        is_production: bool,
    ) -> Self {
        Self {
            certificate_path,
            certificate_passphrase: None,
            bundle_id,
            is_production,
        }
    }

    /// Set certificate passphrase
    pub fn with_passphrase(mut self, passphrase: String) -> Self {
        self.certificate_passphrase = Some(passphrase);
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
