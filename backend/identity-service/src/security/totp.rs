/// Two-Factor Authentication (2FA) using TOTP (Time-based One-Time Password)
use crate::error::{IdentityError, Result};
use base64::{engine::general_purpose::STANDARD as base64_engine, Engine as _};
use rand::Rng;
use totp_lite::{totp, Sha1};

pub struct TOTPGenerator;

impl TOTPGenerator {
    /// Generate a new TOTP secret and provisioning URI for QR code
    ///
    /// ## Returns
    ///
    /// Tuple of (base64-encoded secret, otpauth URI for QR code generation)
    ///
    /// ## Usage
    ///
    /// 1. Generate secret and URI
    /// 2. Encode URI as QR code
    /// 3. User scans QR code with authenticator app
    /// 4. Store secret in database (encrypted)
    /// 5. User verifies by entering code
    ///
    /// ## Arguments
    ///
    /// * `email` - User's email for display in authenticator app
    pub fn generate_secret_and_uri(email: &str) -> Result<(String, String)> {
        let mut rng = rand::thread_rng();
        let mut secret_bytes = [0u8; 20];
        rng.fill(&mut secret_bytes);

        let secret = base64_engine.encode(secret_bytes);

        // Create provisioning URI for QR code
        // Format: otpauth://totp/Issuer:Account?secret=SECRET&issuer=Issuer
        let uri = format!(
            "otpauth://totp/Nova:{}?secret={}&issuer=Nova",
            urlencoding::encode(email),
            secret
        );

        Ok((secret, uri))
    }

    /// Verify a TOTP code against a stored secret
    ///
    /// ## Security
    ///
    /// - Time window: 30 seconds (standard TOTP)
    /// - Code format: 6 digits
    /// - Algorithm: TOTP-SHA1
    ///
    /// ## Arguments
    ///
    /// * `secret` - Base64-encoded TOTP secret from database
    /// * `code` - 6-digit code from user's authenticator app
    ///
    /// ## Returns
    ///
    /// `true` if code is valid for current time window, `false` otherwise
    pub fn verify_code(secret: &str, code: &str) -> Result<bool> {
        if code.len() != 6 {
            return Ok(false);
        }

        let secret_bytes = base64_engine
            .decode(secret)
            .map_err(|_| IdentityError::InvalidTwoFACode)?;

        if secret_bytes.len() != 20 {
            return Err(IdentityError::InvalidTwoFACode);
        }

        // Generate TOTP code for current time window
        let current_time = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|_| IdentityError::InvalidTwoFACode)?
            .as_secs();

        let time_step = current_time / 30; // 30-second time window
        let generated_code = totp::<Sha1>(&secret_bytes, time_step);

        // Format as 6-digit string with leading zeros
        let generated_code_str = format!("{:06}", generated_code);

        Ok(generated_code_str == code)
    }

    /// Generate backup codes for account recovery
    ///
    /// ## Returns
    ///
    /// Vector of 8 backup codes, each 8 digits long
    ///
    /// ## Usage
    ///
    /// 1. Generate backup codes during 2FA setup
    /// 2. Display to user for secure storage
    /// 3. Hash and store in database
    /// 4. User can use one code if they lose their device
    /// 5. Mark code as used after successful authentication
    ///
    /// ## Security Notes
    ///
    /// - Each code should be single-use only
    /// - Store hashed versions in database (like passwords)
    /// - Generate new set after user uses all codes
    pub fn generate_backup_codes() -> Vec<String> {
        let mut rng = rand::thread_rng();
        (0..8)
            .map(|_| {
                (0..8)
                    .map(|_| {
                        let idx = rng.gen_range(0..10);
                        (b'0' + idx as u8) as char
                    })
                    .collect()
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_secret_and_uri() {
        let result = TOTPGenerator::generate_secret_and_uri("test@example.com");
        assert!(result.is_ok());
        let (secret, uri) = result.expect("should generate secret and URI successfully");
        assert!(!secret.is_empty());
        assert!(uri.contains("otpauth://totp/Nova"));
        // Email should be percent-encoded per otpauth spec
        assert!(uri.contains("test%40example.com"));
    }

    #[test]
    fn test_generate_backup_codes() {
        let codes = TOTPGenerator::generate_backup_codes();
        assert_eq!(codes.len(), 8);
        for code in codes {
            assert_eq!(code.len(), 8);
            assert!(code.chars().all(|c| c.is_ascii_digit()));
        }
    }

    #[test]
    fn test_verify_code_invalid_length() {
        let (secret, _) = TOTPGenerator::generate_secret_and_uri("test@example.com")
            .expect("should generate secret");
        assert_eq!(TOTPGenerator::verify_code(&secret, "12345").unwrap(), false);
        assert_eq!(
            TOTPGenerator::verify_code(&secret, "1234567").unwrap(),
            false
        );
    }

    #[test]
    fn test_verify_code_invalid_secret() {
        let result = TOTPGenerator::verify_code("invalid_base64!", "123456");
        assert!(result.is_err());
    }
}
