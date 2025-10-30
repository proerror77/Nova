/// Two-Factor Authentication (2FA) using TOTP (Time-based One-Time Password)
use totp_lite::{totp, Sha1};
use rand::Rng;
use base64::{engine::general_purpose::STANDARD as base64_engine, Engine as _};
use crate::error::{AuthError, AuthResult};

pub struct TOTPGenerator;

impl TOTPGenerator {
    /// Generate a new TOTP secret and provisioning URI for QR code
    pub fn generate_secret_and_uri(email: &str) -> AuthResult<(String, String)> {
        let mut rng = rand::thread_rng();
        let mut secret_bytes = [0u8; 20];
        rng.fill(&mut secret_bytes);

        let secret = base64_engine.encode(&secret_bytes);

        // Create provisioning URI for QR code
        let uri = format!(
            "otpauth://totp/Nova:{}?secret={}&issuer=Nova",
            urlencoding::encode(email),
            secret
        );

        Ok((secret, uri))
    }

    /// Verify a TOTP code
    pub fn verify_code(secret: &str, code: &str) -> AuthResult<bool> {
        if code.len() != 6 {
            return Ok(false);
        }

        let secret_bytes = base64_engine
            .decode(secret)
            .map_err(|_| AuthError::InvalidTwoFACode)?;

        if secret_bytes.len() != 20 {
            return Err(AuthError::InvalidTwoFACode);
        }

        // Use totp-lite's totp function for verification
        // This generates the current TOTP code and checks if it matches
        let current_time = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|_| AuthError::InvalidTwoFACode)?
            .as_secs();

        let time_step = current_time / 30; // 30-second time window
        let generated_code = totp::<Sha1>(&secret_bytes, time_step);

        // Format the generated code as a 6-digit string
        let generated_code_str = format!("{:06}", generated_code);

        Ok(generated_code_str == code)
    }

    /// Generate backup codes (8 codes, 8 characters each)
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
        let (secret, uri) = result.unwrap();
        assert!(!secret.is_empty());
        assert!(uri.contains("otpauth://totp/Nova"));
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
}
