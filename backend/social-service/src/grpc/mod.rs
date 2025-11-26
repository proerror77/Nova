// gRPC server implementations for social-service
//
// server_v2.rs: Transactional Outbox integration (Phase B)
// - Uses publish_event! macro from transactional-outbox
// - Atomic PostgreSQL transactions + event publishing
// - Redis counter updates after commit

pub mod server_v2;

#[allow(unused_imports)]
pub use server_v2::{AppState, SocialServiceImpl as SocialServiceV2Impl};
