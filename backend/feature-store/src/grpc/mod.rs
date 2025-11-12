// gRPC module - exports server implementation

mod server;

pub use server::{feature_store, AppState, FeatureStoreImpl};

// Re-export proto types for convenience
pub use feature_store::feature_store_server::FeatureStoreServer;
