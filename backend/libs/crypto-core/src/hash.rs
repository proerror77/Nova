use sha2::{Digest, Sha256};

/// Compute SHA256 hash of input bytes
pub fn sha256(input: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(input);
    hasher.finalize().into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sha256() {
        let input = b"hello world";
        let hash = sha256(input);
        assert_eq!(hash.len(), 32);

        // Verify deterministic
        let hash2 = sha256(input);
        assert_eq!(hash, hash2);
    }
}
