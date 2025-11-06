/// Test module for auth-service
///
/// This module provides comprehensive unit tests for the auth service core business logic.
/// Tests follow the TDD red-green-refactor cycle.
pub mod fixtures;
pub mod unit_tests;

// Integration tests that require database
// Run these with: DATABASE_URL=... cargo test --package auth-service
#[cfg(feature = "integration-tests")]
pub mod auth_tests;
