/// Security module for authentication and authorization
///
/// Provides core security primitives for identity-service:
/// - Password hashing and verification (Argon2id)
/// - JWT token generation and validation (RS256 via crypto-core)
/// - Two-factor authentication (TOTP)
/// - Token revocation (Redis-based blacklist)
///
/// ## Architecture
///
/// - **crypto-core::jwt**: Shared JWT implementation (RS256 only)
/// - **password**: Argon2id password hashing
/// - **totp**: TOTP 2FA generation and verification
/// - **token_revocation**: Real-time token blacklisting via Redis
// Re-export JWT functionality from shared crypto-core library
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
