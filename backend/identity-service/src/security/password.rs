/// Password hashing and verification using Argon2id
use crate::error::{IdentityError, Result};
use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use zxcvbn::zxcvbn;

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

/// Validate password strength using composition rules and zxcvbn
///
/// ## Requirements
///
/// - Minimum 8 characters
/// - At least one uppercase letter
/// - At least one lowercase letter
/// - At least one digit
/// - At least one special character
/// - zxcvbn entropy score >= 3 (strong)
///
/// ## Arguments
///
/// * `password` - Password to validate
///
/// ## Errors
///
/// Returns `IdentityError::WeakPassword` with specific failure reason
fn validate_password_strength(password: &str) -> Result<()> {
    // Length check
    if password.len() < 8 {
        return Err(IdentityError::WeakPassword(
            "Password must be at least 8 characters".to_string(),
        ));
    }

    // Composition checks
    let has_uppercase = password.chars().any(|c| c.is_ascii_uppercase());
    let has_lowercase = password.chars().any(|c| c.is_ascii_lowercase());
    let has_digit = password.chars().any(|c| c.is_ascii_digit());
    let has_special = password.chars().any(|c| !c.is_alphanumeric());

    if !has_uppercase {
        return Err(IdentityError::WeakPassword(
            "Password must contain at least one uppercase letter".to_string(),
        ));
    }

    if !has_lowercase {
        return Err(IdentityError::WeakPassword(
            "Password must contain at least one lowercase letter".to_string(),
        ));
    }

    if !has_digit {
        return Err(IdentityError::WeakPassword(
            "Password must contain at least one digit".to_string(),
        ));
    }

    if !has_special {
        return Err(IdentityError::WeakPassword(
            "Password must contain at least one special character".to_string(),
        ));
    }

    // Entropy check using zxcvbn
    let entropy = zxcvbn(password, &[]).map_err(|e| {
        IdentityError::Internal(format!("Password entropy calculation failed: {}", e))
    })?;

    if entropy.score() < 3 {
        return Err(IdentityError::WeakPassword(
            "Password is too weak. Please use a stronger password with higher entropy.".to_string(),
        ));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_and_verify_valid_password() {
        let password = "StrongP@ssw0rd!";
        let hash = hash_password(password).expect("should hash password successfully");
        assert!(verify_password(password, &hash).expect("should verify successfully"));
    }

    #[test]
    fn test_verify_wrong_password() {
        let password = "StrongP@ssw0rd!";
        let hash = hash_password(password).expect("should hash password successfully");
        assert!(!verify_password("WrongPassword123!", &hash).expect("verification should succeed"));
    }

    #[test]
    fn test_weak_password_too_short() {
        let result = hash_password("Short1!");
        assert!(matches!(result, Err(IdentityError::WeakPassword(_))));
    }

    #[test]
    fn test_weak_password_no_uppercase() {
        let result = hash_password("weakpassword123!");
        assert!(matches!(result, Err(IdentityError::WeakPassword(_))));
    }

    #[test]
    fn test_weak_password_no_digit() {
        let result = hash_password("StrongPassword!");
        assert!(matches!(result, Err(IdentityError::WeakPassword(_))));
    }

    #[test]
    fn test_weak_password_no_special() {
        let result = hash_password("StrongPassword123");
        assert!(matches!(result, Err(IdentityError::WeakPassword(_))));
    }

    #[test]
    fn test_different_hashes_for_same_password() {
        let password = "StrongP@ssw0rd!";
        let hash1 = hash_password(password).expect("should hash successfully");
        let hash2 = hash_password(password).expect("should hash successfully");
        // Different salts should produce different hashes
        assert_ne!(hash1, hash2);
    }
}
