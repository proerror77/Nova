// ============================================
// Background Jobs Module (後台任務模組)
// ============================================
//
// Contains background job runners for:
// 1. Profile batch updates
// 2. Interest aggregation
// 3. Feature store refresh
//
// These jobs can be triggered via:
// - CronJob (Kubernetes)
// - Command line argument (--mode profile-batch)
// - gRPC API (BatchUpdateProfiles)

pub mod profile_batch;

pub use profile_batch::{run_profile_batch_job, ProfileBatchConfig, ProfileBatchJob};
