pub mod aggregates;
pub mod entities;
pub mod value_objects;
pub mod events;
pub mod errors;

// Re-export commonly used types
pub use aggregates::User;
pub use entities::{Session, RefreshToken};
pub use value_objects::{UserId, Email, HashedPassword, TokenPair};
pub use events::IdentityEvent;
pub use errors::IdentityError;