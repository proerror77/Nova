/// Security module for authentication
/// Provides password hashing, JWT token management, and 2FA support
// Re-export JWT module from shared crypto-core library
pub use crypto_core::jwt;
pub use crypto_core::jwt::{
    generate_token_pair, initialize_jwt_keys, validate_token, Claims, TokenResponse,
};
pub use jsonwebtoken::TokenData;

pub mod password;
pub mod token_revocation;
pub mod totp;

pub use password::{hash_password, verify_password};
pub use totp::TOTPGenerator;
