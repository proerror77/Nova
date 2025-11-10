//! Secret strength validation module
//!
//! Validates JWT secrets for cryptographic strength to prevent weak key attacks

use anyhow::{anyhow, Result};
use ring::rand::{SecureRandom, SystemRandom};

const MIN_SECRET_LENGTH: usize = 32; // 256 bits minimum
const RECOMMENDED_SECRET_LENGTH: usize = 64; // 512 bits recommended

/// Secret strength classification
#[derive(Debug, PartialEq, Eq)]
pub enum SecretStrength {
    /// Weak secret - REJECT
    Weak,
    /// Acceptable secret - WARN
    Acceptable,
    /// Strong secret - OK
    Strong,
}

/// Validate secret strength for HS256/HS512 (not used in RS256, but kept for reference)
///
/// **Criteria**:
/// - Minimum 32 bytes (256 bits)
/// - Recommended 64 bytes (512 bits)
/// - Shannon entropy > 4.0 bits/byte
/// - No obvious patterns (repeating characters, sequential)
pub fn validate_secret_strength(secret: &str) -> Result<SecretStrength> {
    let bytes = secret.as_bytes();

    // 1. Length check
    if bytes.len() < MIN_SECRET_LENGTH {
        return Ok(SecretStrength::Weak);
    }

    // 2. Entropy check (Shannon entropy)
    let entropy = calculate_shannon_entropy(bytes);
    if entropy < 4.0 {
        return Ok(SecretStrength::Weak);
    }

    // 3. Pattern detection
    if has_obvious_patterns(bytes) {
        return Ok(SecretStrength::Weak);
    }

    // 4. Classify based on length
    if bytes.len() >= RECOMMENDED_SECRET_LENGTH && entropy >= 5.0 {
        Ok(SecretStrength::Strong)
    } else {
        Ok(SecretStrength::Acceptable)
    }
}

/// Calculate Shannon entropy of byte sequence
///
/// Returns bits per byte (0-8 scale)
fn calculate_shannon_entropy(data: &[u8]) -> f64 {
    let mut freq = [0u32; 256];
    let len = data.len() as f64;

    // Count byte frequencies
    for &byte in data {
        freq[byte as usize] += 1;
    }

    // Calculate entropy
    let mut entropy = 0.0;
    for &count in freq.iter() {
        if count > 0 {
            let p = count as f64 / len;
            entropy -= p * p.log2();
        }
    }

    entropy
}

/// Detect obvious patterns in secret
fn has_obvious_patterns(data: &[u8]) -> bool {
    if data.len() < 4 {
        return false;
    }

    // Check for repeating characters (e.g., "aaaa", "1111")
    let mut consecutive_same = 1;
    for window in data.windows(2) {
        if window[0] == window[1] {
            consecutive_same += 1;
            if consecutive_same >= 4 {
                return true;
            }
        } else {
            consecutive_same = 1;
        }
    }

    // Check for sequential patterns (e.g., "abcd", "1234")
    let mut consecutive_seq = 1;
    for window in data.windows(2) {
        if window[1] as i16 - window[0] as i16 == 1 {
            consecutive_seq += 1;
            if consecutive_seq >= 4 {
                return true;
            }
        } else {
            consecutive_seq = 1;
        }
    }

    false
}

/// Generate cryptographically secure random secret
///
/// **Usage**: For generating strong secrets in development/testing
pub fn generate_secure_secret(length: usize) -> Result<String> {
    if length < MIN_SECRET_LENGTH {
        return Err(anyhow!(
            "Secret length must be at least {} bytes",
            MIN_SECRET_LENGTH
        ));
    }

    let rng = SystemRandom::new();
    let mut buffer = vec![0u8; length];
    rng.fill(&mut buffer)
        .map_err(|_| anyhow!("Failed to generate random bytes"))?;

    // Encode as base64 for safe transmission
    use base64::{engine::general_purpose::STANDARD, Engine};
    Ok(STANDARD.encode(&buffer))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_weak_secret_too_short() {
        let weak = "short";
        assert_eq!(validate_secret_strength(weak).unwrap(), SecretStrength::Weak);
    }

    #[test]
    fn test_weak_secret_low_entropy() {
        let weak = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; // 32 'a's
        assert_eq!(validate_secret_strength(weak).unwrap(), SecretStrength::Weak);
    }

    #[test]
    fn test_weak_secret_sequential_pattern() {
        let weak = "abcdefghijklmnopqrstuvwxyzabcdef"; // Sequential alphabet
        assert_eq!(validate_secret_strength(weak).unwrap(), SecretStrength::Weak);
    }

    #[test]
    fn test_acceptable_secret() {
        let acceptable = "J8Kq2mPvRx4TnZs9YwLcGf7DhBe3Xa6W"; // 32 random-looking chars
        let strength = validate_secret_strength(acceptable).unwrap();
        assert!(
            strength == SecretStrength::Acceptable || strength == SecretStrength::Strong
        );
    }

    #[test]
    fn test_strong_secret() {
        let strong = "y9K$mP2vRx#TnZ@s4Yw!cGf7Dh&e3Xa6Wq8Lj5BtNu1Zp0MkYhVgCxFbAsSdQwEr"; // 64 random chars
        assert_eq!(
            validate_secret_strength(strong).unwrap(),
            SecretStrength::Strong
        );
    }

    #[test]
    fn test_generate_secure_secret() {
        let secret = generate_secure_secret(64).unwrap();
        assert!(secret.len() >= 64);
        assert_eq!(
            validate_secret_strength(&secret).unwrap(),
            SecretStrength::Strong
        );
    }

    #[test]
    fn test_shannon_entropy() {
        // All same characters = 0 entropy
        let low_entropy = &[b'a'; 100];
        assert!(calculate_shannon_entropy(low_entropy) < 0.1);

        // Uniform distribution = ~8 entropy
        let high_entropy: Vec<u8> = (0..=255).collect();
        let entropy = calculate_shannon_entropy(&high_entropy);
        assert!(entropy > 7.5); // Close to 8 bits per byte
    }

    #[test]
    fn test_pattern_detection() {
        assert!(has_obvious_patterns(b"aaaa"));
        assert!(has_obvious_patterns(b"abcd"));
        assert!(has_obvious_patterns(b"1234"));
        assert!(!has_obvious_patterns(b"aZ3$"));
    }
}
