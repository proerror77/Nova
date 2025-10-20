/// Password hashing and verification tests (AUTH-1002)
/// Tests for Argon2 password hashing and verification
/// Modern password hashing algorithm: memory-hard, time-hard, resistant to GPU attacks

#[cfg(test)]
mod tests {
    use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
    use argon2::password_hash::SaltString;
    use rand::Rng;

    /// Test helper: Hash a password using Argon2
    fn hash_password(password: &str) -> Result<String, argon2::password_hash::Error> {
        let salt = SaltString::generate(rand::thread_rng());
        let argon2 = Argon2::default();
        let password_hash = argon2
            .hash_password(password.as_bytes(), &salt)?
            .to_string();
        Ok(password_hash)
    }

    /// Test helper: Verify a password against its hash
    fn verify_password(password: &str, hash: &str) -> Result<(), argon2::password_hash::Error> {
        let parsed_hash = PasswordHash::new(hash)?;
        Argon2::default().verify_password(password.as_bytes(), &parsed_hash)
    }

    #[test]
    fn test_hash_password_creates_valid_hash() {
        let password = "MySecurePassword123!";
        let hash_result = hash_password(password);

        assert!(hash_result.is_ok());
        let hash = hash_result.unwrap();

        // Hash should contain Argon2 parameters
        assert!(hash.contains("$argon2"));
        // Hash should not contain plaintext password
        assert!(!hash.contains(password));
    }

    #[test]
    fn test_hash_password_different_salts() {
        let password = "SamePassword";
        let hash1 = hash_password(password).unwrap();
        let hash2 = hash_password(password).unwrap();

        // Same password with different salts should produce different hashes
        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_verify_password_correct() {
        let password = "CorrectPassword123";
        let hash = hash_password(password).unwrap();

        let result = verify_password(password, &hash);
        assert!(result.is_ok());
    }

    #[test]
    fn test_verify_password_incorrect() {
        let password = "CorrectPassword123";
        let wrong_password = "WrongPassword123";
        let hash = hash_password(password).unwrap();

        let result = verify_password(wrong_password, &hash);
        assert!(result.is_err());
    }

    #[test]
    fn test_verify_password_case_sensitive() {
        let password = "MyPassword";
        let different_case = "mypassword";
        let hash = hash_password(password).unwrap();

        let result = verify_password(different_case, &hash);
        assert!(result.is_err());
    }

    #[test]
    fn test_hash_never_returns_plaintext() {
        let password = "SecretPassword123";
        let hash = hash_password(password).unwrap();

        // Hash should never contain the plaintext password anywhere
        assert!(!hash.to_lowercase().contains(&password.to_lowercase()));
    }

    #[test]
    fn test_hash_with_long_password() {
        let long_password = "a".repeat(128);
        let hash_result = hash_password(&long_password);

        assert!(hash_result.is_ok());
        let hash = hash_result.unwrap();
        let verify_result = verify_password(&long_password, &hash);
        assert!(verify_result.is_ok());
    }

    #[test]
    fn test_hash_with_special_characters() {
        let special_password = "P@ssw0rd!#$%^&*()_+-=[]{}|;:',.<>?/~`";
        let hash_result = hash_password(special_password);

        assert!(hash_result.is_ok());
        let hash = hash_result.unwrap();
        let verify_result = verify_password(special_password, &hash);
        assert!(verify_result.is_ok());
    }

    #[test]
    fn test_hash_with_unicode_characters() {
        let unicode_password = "Пароль密码🔐";
        let hash_result = hash_password(unicode_password);

        assert!(hash_result.is_ok());
        let hash = hash_result.unwrap();
        let verify_result = verify_password(unicode_password, &hash);
        assert!(verify_result.is_ok());
    }

    #[test]
    fn test_verify_with_empty_hash() {
        let password = "SomePassword";
        let result = verify_password(password, "");

        assert!(result.is_err());
    }

    #[test]
    fn test_verify_with_corrupted_hash() {
        let password = "SomePassword";
        let corrupted_hash = "$argon2id$v=19$m=19456,t=2,p=1$corrupted$hash";
        let result = verify_password(password, corrupted_hash);

        assert!(result.is_err());
    }

    #[test]
    fn test_hash_password_empty_string() {
        let empty_password = "";
        let hash_result = hash_password(empty_password);

        // Should still hash, but be aware this is a weak password
        assert!(hash_result.is_ok());
    }

    #[test]
    fn test_verify_password_trailing_space() {
        let password = "MyPassword";
        let password_with_space = "MyPassword ";
        let hash = hash_password(password).unwrap();

        // Different string (with trailing space) should fail verification
        let result = verify_password(password_with_space, &hash);
        assert!(result.is_err());
    }

    #[test]
    fn test_hash_deterministic_with_same_salt() {
        // Note: Argon2 uses random salt, so we can't easily test determinism
        // But we can test that the algorithm is consistent
        let password = "TestPassword";
        let hash1 = hash_password(password).unwrap();
        let hash2 = hash_password(password).unwrap();

        // Different hashes due to different salts, but both should verify
        assert!(verify_password(password, &hash1).is_ok());
        assert!(verify_password(password, &hash2).is_ok());
    }

    #[test]
    fn test_hash_output_format_argon2id() {
        let password = "TestPassword";
        let hash = hash_password(password).unwrap();

        // Argon2id is the default algorithm
        assert!(hash.contains("$argon2id$") || hash.contains("$argon2i$"));
        // Should contain v=19 (PHC format version 1.3)
        assert!(hash.contains("v=19"));
    }

    #[test]
    fn test_multiple_verify_same_hash() {
        let password = "TestPassword";
        let hash = hash_password(password).unwrap();

        // Verify the same password multiple times against same hash
        for _ in 0..5 {
            assert!(verify_password(password, &hash).is_ok());
        }
    }
}
