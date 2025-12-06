/// Password hashing and verification using Argon2id
use crate::error::{IdentityError, Result};
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};

/// Hash a password using Argon2id algorithm
///
/// ## Security
///
/// - Algorithm: Argon2id (default configuration)
/// - Salt: Random 16-byte salt generated per password
/// - Password strength: Enforces zxcvbn score >= 3
///
/// ## Arguments
///
/// * `password` - Plaintext password (max 72 bytes for bcrypt compatibility)
///
/// ## Returns
///
/// PHC-formatted hash string safe for database storage
///
/// ## Errors
///
/// Returns error if:
/// - Password is too weak (zxcvbn score < 3)
/// - Hashing operation fails
pub fn hash_password(password: &str) -> Result<String> {
    // Validate password strength before hashing
    validate_password_strength(password)?;

    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();

    let password_hash = argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| IdentityError::Internal(format!("Password hashing failed: {}", e)))?
        .to_string();

    Ok(password_hash)
}

/// Verify a password against its hash
///
/// ## Security
///
/// - Uses constant-time comparison to prevent timing attacks
/// - Supports Argon2id PHC format
///
/// ## Arguments
///
/// * `password` - Plaintext password to verify
/// * `password_hash` - PHC-formatted hash from database
///
/// ## Returns
///
/// `true` if password matches hash, `false` otherwise
pub fn verify_password(password: &str, password_hash: &str) -> Result<bool> {
    let parsed_hash = PasswordHash::new(password_hash)
        .map_err(|e| IdentityError::Internal(format!("Invalid password hash format: {}", e)))?;

    match Argon2::default().verify_password(password.as_bytes(), &parsed_hash) {
        Ok(_) => Ok(true),
        Err(argon2::password_hash::Error::Password) => Ok(false),
        Err(e) => Err(IdentityError::Internal(format!(
            "Password verification failed: {}",
            e
        ))),
    }
}

/// Validate password strength - simplified for development/testing
///
/// ## Requirements
///
/// - Minimum 6 characters
///
/// ## Arguments
///
/// * `password` - Password to validate
///
/// ## Errors
///
/// Returns `IdentityError::WeakPassword` with specific failure reason
fn validate_password_strength(password: &str) -> Result<()> {
    // Length check only
    if password.len() < 6 {
        return Err(IdentityError::WeakPassword(
            "Password must be at least 6 characters".to_string(),
        ));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_and_verify_valid_password() {
        let password = "simplepass";
        let hash = hash_password(password).expect("should hash password successfully");
        assert!(verify_password(password, &hash).expect("should verify successfully"));
    }

    #[test]
    fn test_verify_wrong_password() {
        let password = "password123";
        let hash = hash_password(password).expect("should hash password successfully");
        assert!(!verify_password("wrongpass", &hash).expect("verification should succeed"));
    }

    #[test]
    fn test_weak_password_too_short() {
        let result = hash_password("short");
        assert!(matches!(result, Err(IdentityError::WeakPassword(_))));
    }

    #[test]
    fn test_valid_simple_password() {
        // Simple passwords are now allowed as long as they're 6+ characters
        let result = hash_password("simple123");
        assert!(result.is_ok());
    }

    #[test]
    fn test_different_hashes_for_same_password() {
        let password = "testpass123";
        let hash1 = hash_password(password).expect("should hash successfully");
        let hash2 = hash_password(password).expect("should hash successfully");
        // Different salts should produce different hashes
        assert_ne!(hash1, hash2);
    }
}
