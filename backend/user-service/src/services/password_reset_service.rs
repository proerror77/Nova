/// Password reset service
/// Generates and validates password reset tokens stored in database
use crate::security::{generate_token, hash_token, verify_token_hash};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::security::token::TOKEN_LENGTH;

    #[test]
    fn test_generate_token_creates_valid_length() {
        let token = generate_token();
        assert_eq!(token.len(), TOKEN_LENGTH * 2);
    }

    #[test]
    fn test_generate_token_uniqueness() {
        let token1 = generate_token();
        let token2 = generate_token();
        assert_ne!(token1, token2);
    }

    #[test]
    fn test_generate_token_is_random() {
        let tokens: Vec<String> = (0..10).map(|_| generate_token()).collect();
        let unique_tokens: std::collections::HashSet<_> = tokens.iter().collect();
        assert_eq!(unique_tokens.len(), tokens.len());
    }

    #[test]
    fn test_token_format_is_hex() {
        let token = generate_token();
        for c in token.chars() {
            assert!(
                c.is_ascii_hexdigit(),
                "Token contains non-hex character: {}",
                c
            );
        }
    }

    #[test]
    fn test_hash_token_deterministic() {
        let token = "test_token_12345";
        let hash1 = hash_token(token);
        let hash2 = hash_token(token);
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_hash_token_different_for_different_inputs() {
        let token1 = "test_token_1";
        let token2 = "test_token_2";
        let hash1 = hash_token(token1);
        let hash2 = hash_token(token2);
        assert_ne!(hash1, hash2);
    }

    #[test]
    fn test_hash_token_produces_hex() {
        let token = "test_token";
        let hash = hash_token(token);
        for c in hash.chars() {
            assert!(c.is_ascii_hexdigit());
        }
    }

    #[test]
    fn test_verify_token_hash_correct() {
        let token = "valid_token_xyz";
        let hash = hash_token(token);
        assert!(verify_token_hash(token, &hash));
    }

    #[test]
    fn test_verify_token_hash_incorrect() {
        let token = "valid_token_xyz";
        let wrong_token = "wrong_token_abc";
        let hash = hash_token(token);
        assert!(!verify_token_hash(wrong_token, &hash));
    }

    #[test]
    fn test_verify_token_hash_case_sensitive() {
        let token = "TokenXYZ";
        let different_case = "tokenxyz";
        let hash = hash_token(token);
        assert!(!verify_token_hash(different_case, &hash));
    }

    #[test]
    fn test_hash_token_sha256_format() {
        let token = "test";
        let hash = hash_token(token);
        // SHA256 produces 64 hex characters
        assert_eq!(hash.len(), 64);
    }
}
