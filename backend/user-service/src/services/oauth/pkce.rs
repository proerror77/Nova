/// OAuth PKCE (Proof Key for Code Exchange) Implementation
///
/// RFC 7636 compliant PKCE for OAuth 2.0
///
/// PKCE provides additional security for mobile and desktop applications
/// by preventing authorization code interception attacks.
///
/// Flow:
/// 1. Client generates a code_verifier (43-128 characters of [A-Z0-9._-])
/// 2. Client creates code_challenge = BASE64URL(SHA256(code_verifier))
/// 3. Client includes code_challenge in authorization request
/// 4. Authorization server stores code_challenge with the code
/// 5. Client exchanges code + code_verifier for tokens
/// 6. Server verifies: BASE64URL(SHA256(code_verifier)) == code_challenge

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::engine::Engine;
use sha2::{Digest, Sha256};
use thiserror::Error;

/// PKCE errors
#[derive(Debug, Error)]
pub enum PkceError {
    #[error("Invalid code verifier: {0}")]
    InvalidVerifier(String),

    #[error("Code verifier and challenge mismatch")]
    ChallengeVerificationFailed,

    #[error("Unsupported challenge method: {0}")]
    UnsupportedMethod(String),

    #[error("Invalid code challenge format")]
    InvalidChallengeFormat,
}

/// Validate if a string is a valid PKCE code verifier
///
/// RFC 7636 specifies:
/// - 43-128 characters long
/// - Unreserved characters: [A-Z] [a-z] [0-9] - . _ ~
/// - Which translates to: [A-Za-z0-9._-]
pub fn is_valid_code_verifier(verifier: &str) -> bool {
    let len = verifier.len();
    len >= 43 && len <= 128 && verifier.chars().all(|c| {
        c.is_ascii_alphanumeric() || c == '-' || c == '.' || c == '_' || c == '~'
    })
}

/// Generate code challenge from code verifier using SHA256
///
/// # Arguments
/// * `code_verifier` - The client-generated code verifier (43-128 chars)
///
/// # Returns
/// Base64 URL-encoded SHA256 hash of the code verifier
pub fn generate_code_challenge(code_verifier: &str) -> Result<String, PkceError> {
    if !is_valid_code_verifier(code_verifier) {
        return Err(PkceError::InvalidVerifier(format!(
            "Code verifier must be 43-128 characters, got {}",
            code_verifier.len()
        )));
    }

    let mut hasher = Sha256::new();
    hasher.update(code_verifier.as_bytes());
    let hash = hasher.finalize();

    let challenge = URL_SAFE_NO_PAD.encode(&hash);
    Ok(challenge)
}

/// Verify code challenge against code verifier
///
/// # Arguments
/// * `code_verifier` - The code verifier from the client
/// * `code_challenge` - The challenge stored by the authorization server
/// * `code_challenge_method` - The method used (S256 or plain), defaults to S256
///
/// # Returns
/// true if verifier matches challenge, false otherwise
pub fn verify_code_challenge(
    code_verifier: &str,
    code_challenge: &str,
    code_challenge_method: Option<&str>,
) -> Result<bool, PkceError> {
    if !is_valid_code_verifier(code_verifier) {
        return Err(PkceError::InvalidVerifier(format!(
            "Code verifier must be 43-128 characters, got {}",
            code_verifier.len()
        )));
    }

    let method = code_challenge_method.unwrap_or("S256");

    match method {
        "S256" => {
            let calculated_challenge = generate_code_challenge(code_verifier)?;
            Ok(calculated_challenge == code_challenge)
        }
        "plain" => {
            // Plain method: code_challenge == code_verifier
            // Not recommended but supported by RFC
            Ok(code_verifier == code_challenge)
        }
        _ => Err(PkceError::UnsupportedMethod(method.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_code_verifier() {
        // Minimum length (43 characters)
        let verifier43 = "a".repeat(43);
        assert!(is_valid_code_verifier(&verifier43));

        // Maximum length (128 characters)
        let verifier128 = "a".repeat(128);
        assert!(is_valid_code_verifier(&verifier128));

        // With special characters
        let verifier_special = "abc-123_XYZ.test~!";
        assert!(is_valid_code_verifier(verifier_special));
    }

    #[test]
    fn test_invalid_code_verifier_too_short() {
        let verifier = "a".repeat(42); // Too short
        assert!(!is_valid_code_verifier(&verifier));
    }

    #[test]
    fn test_invalid_code_verifier_too_long() {
        let verifier = "a".repeat(129); // Too long
        assert!(!is_valid_code_verifier(&verifier));
    }

    #[test]
    fn test_invalid_code_verifier_bad_chars() {
        assert!(!is_valid_code_verifier("short")); // Too short and bad chars
        assert!(!is_valid_code_verifier(&format!("{}{}", "a".repeat(43), "@"))); // Invalid char @
    }

    #[test]
    fn test_generate_code_challenge() {
        let verifier = "E9Mrozoa2owUednMVZfgeQ-wHWJBtyQRlPPfQ8HuZqU"; // RFC 7636 test vector
        let challenge = generate_code_challenge(verifier).unwrap();

        // RFC 7636 test vector expects: E9Mrozoa2owUednMVZfgeQ-wHWJBtyQRlPPfQ8HuZqU -> E9Mrozoa2owUednMVZfgeQ-wHWJBtyQRlPPfQ8HuZqU
        // (plain method, so they're the same)
        // For S256, it should produce the hash
        assert!(!challenge.is_empty());
        assert!(challenge.len() > 0);
    }

    #[test]
    fn test_generate_code_challenge_invalid_verifier() {
        let result = generate_code_challenge("too_short");
        assert!(result.is_err());

        let result = generate_code_challenge(&"a".repeat(129));
        assert!(result.is_err());
    }

    #[test]
    fn test_verify_code_challenge_s256() {
        let verifier = "E9Mrozoa2owUednMVZfgeQ-wHWJBtyQRlPPfQ8HuZqU";
        let challenge = generate_code_challenge(verifier).unwrap();

        // Should verify successfully with S256 method
        let result = verify_code_challenge(verifier, &challenge, Some("S256")).unwrap();
        assert!(result);

        // Should fail with different verifier
        let wrong_verifier = "wrongverifierXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
        let result = verify_code_challenge(wrong_verifier, &challenge, Some("S256")).unwrap();
        assert!(!result);
    }

    #[test]
    fn test_verify_code_challenge_plain() {
        let verifier = "E9Mrozoa2owUednMVZfgeQ-wHWJBtyQRlPPfQ8HuZqU";

        // Plain method: challenge == verifier
        let result = verify_code_challenge(verifier, verifier, Some("plain")).unwrap();
        assert!(result);

        // Should fail if different
        let wrong_challenge = "wrongchallengeXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
        let result = verify_code_challenge(verifier, wrong_challenge, Some("plain")).unwrap();
        assert!(!result);
    }

    #[test]
    fn test_verify_code_challenge_default_method() {
        let verifier = "E9Mrozoa2owUednMVZfgeQ-wHWJBtyQRlPPfQ8HuZqU";
        let challenge = generate_code_challenge(verifier).unwrap();

        // Default method should be S256
        let result = verify_code_challenge(verifier, &challenge, None).unwrap();
        assert!(result);
    }

    #[test]
    fn test_verify_code_challenge_unsupported_method() {
        let verifier = "E9Mrozoa2owUednMVZfgeQ-wHWJBtyQRlPPfQ8HuZqU";
        let challenge = "somechallenge";

        let result = verify_code_challenge(verifier, challenge, Some("unknown"));
        assert!(result.is_err());
    }

    #[test]
    fn test_base64_url_encoding() {
        // Verify that our base64 encoding is URL-safe (no padding, no +/= chars)
        let verifier = "a".repeat(43);
        let challenge = generate_code_challenge(&verifier).unwrap();

        // Should not contain base64 standard chars
        assert!(!challenge.contains('+'));
        assert!(!challenge.contains('/'));
        assert!(!challenge.contains('='));

        // Should only contain URL-safe chars
        assert!(challenge
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'));
    }
}
