// Generated protobuf code
pub mod feature_store {
    tonic::include_proto!("feature_store");
}

pub mod config;
pub mod db;
pub mod error;
pub mod grpc;
pub mod models;
pub mod services;
pub mod utils;

// Re-export common types
pub use feature_store::{
    feature_store_server::{FeatureStore, FeatureStoreServer},
    BatchGetFeaturesRequest, BatchGetFeaturesResponse, DoubleList, FeatureType, FeatureValue,
    GetFeatureMetadataRequest, GetFeatureMetadataResponse, GetFeaturesRequest, GetFeaturesResponse,
    SetFeatureRequest, SetFeatureResponse,
};
