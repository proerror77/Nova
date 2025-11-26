// Integration tests for Content Service gRPC API
//
// These tests verify the implementation of all gRPC RPC methods including:
// - GetPostsByIds (batch operation)
// - GetPostsByAuthor (with pagination)
// - UpdatePost (with cache invalidation)
// - DeletePost (soft delete)
// - DecrementLikeCount (unlike operation)
// - CheckPostExists (existence check)
//
// To run these tests with actual gRPC services:
//   docker-compose -f docker-compose.dev.yml up -d
//   cargo test --test grpc_content_service_test -- --nocapture
//   docker-compose -f docker-compose.dev.yml down
//
// NOTE: These tests are temporarily disabled as they reference proto types
// (GetPostsByAuthorRequest, CheckPostExistsRequest, etc.) that are not yet
// defined in the centralized grpc-clients crate.
//
// The following types need to be added to grpc-clients before re-enabling:
// - GetPostsByAuthorRequest / GetPostsByAuthorResponse
// - CheckPostExistsRequest / CheckPostExistsResponse
// - IncrementLikeCountRequest / UpdatePostRequest / DeletePostRequest
//
// TODO: Update tests once proto definitions are synchronized with grpc-clients.
// See git history for original test implementations.
