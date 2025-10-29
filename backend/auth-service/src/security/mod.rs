/// Security module for authentication
/// Provides password hashing, JWT token management, and 2FA support

// Re-export JWT module from shared crypto-core library
pub use crypto_core::jwt;
pub use crypto_core::jwt::{Claims, TokenResponse, initialize_jwt_keys, generate_token_pair, validate_token};
pub use jsonwebtoken::TokenData;

pub mod password;
pub mod totp;
pub mod token_revocation;

pub use password::{hash_password, verify_password};
pub use totp::TOTPGenerator;
