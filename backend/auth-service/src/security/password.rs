/// Password hashing and verification using Argon2id
use argon2::{
    password_hash::{PasswordHasher, SaltString},
    Argon2, PasswordHash, PasswordVerifier,
};
use crate::error::{AuthError, AuthResult};

/// Hash a password using Argon2id
/// Returns the hash string suitable for storage in database
pub fn hash_password(password: &str) -> AuthResult<String> {
    // Validate password strength first
    validate_password_strength(password)?;

    let salt = SaltString::generate(rand::thread_rng());
    let argon2 = Argon2::default();

    let password_hash = argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|_| AuthError::Internal("Failed to hash password".to_string()))?
        .to_string();

    Ok(password_hash)
}

/// Verify a password against a stored hash
pub fn verify_password(password: &str, hash: &str) -> AuthResult<()> {
    let parsed_hash = PasswordHash::new(hash)
        .map_err(|_| AuthError::Internal("Invalid password hash format".to_string()))?;

    Argon2::default()
        .verify_password(password.as_bytes(), &parsed_hash)
        .map_err(|_| AuthError::InvalidCredentials)
}

/// Validate password strength
/// Requirements:
/// - Minimum 8 characters
/// - At least one uppercase letter
/// - At least one lowercase letter
/// - At least one digit
/// - At least one special character
fn validate_password_strength(password: &str) -> AuthResult<()> {
    if password.len() < 8 {
        return Err(AuthError::WeakPassword);
    }

    let has_uppercase = password.chars().any(|c| c.is_uppercase());
    let has_lowercase = password.chars().any(|c| c.is_lowercase());
    let has_digit = password.chars().any(|c| c.is_ascii_digit());
    let has_special = password.chars().any(|c| !c.is_alphanumeric());

    if has_uppercase && has_lowercase && has_digit && has_special {
        Ok(())
    } else {
        Err(AuthError::WeakPassword)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_and_verify() {
        let password = "SecurePass123!";
        let hash = hash_password(password).unwrap();
        assert!(verify_password(password, &hash).is_ok());
    }

    #[test]
    fn test_wrong_password() {
        let password = "SecurePass123!";
        let hash = hash_password(password).unwrap();
        assert!(verify_password("WrongPass123!", &hash).is_err());
    }

    #[test]
    fn test_weak_password_too_short() {
        assert!(hash_password("Pass1!").is_err());
    }

    #[test]
    fn test_weak_password_no_uppercase() {
        assert!(hash_password("securepass123!").is_err());
    }

    #[test]
    fn test_weak_password_no_special() {
        assert!(hash_password("SecurePass123").is_err());
    }
}
