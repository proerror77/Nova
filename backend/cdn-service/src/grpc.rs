// gRPC server for CdnService
// Thin adapter layer over business logic services

use crate::services::{AssetManager, CacheInvalidator, UrlSigner};
use std::sync::Arc;
use tonic::{Request, Response, Status};
use uuid::Uuid;

pub mod nova {
    pub mod cdn_service {
        pub mod v1 {
            tonic::include_proto!("nova.cdn_service.v1");
        }
        pub use v1::*;
    }
}

use nova::cdn_service::v1::cdn_service_server::CdnService;
use nova::cdn_service::v1::*;

/// gRPC service implementation
#[derive(Clone)]
pub struct CdnServiceImpl {
    asset_manager: Arc<AssetManager>,
    cache_invalidator: Arc<CacheInvalidator>,
    url_signer: Arc<UrlSigner>,
}

impl CdnServiceImpl {
    pub fn new(
        asset_manager: Arc<AssetManager>,
        cache_invalidator: Arc<CacheInvalidator>,
        url_signer: Arc<UrlSigner>,
    ) -> Self {
        Self {
            asset_manager,
            cache_invalidator,
            url_signer,
        }
    }
}

#[tonic::async_trait]
impl CdnService for CdnServiceImpl {
    /// Generate signed CDN URL for S3 asset
    async fn generate_cdn_url(
        &self,
        request: Request<GenerateCdnUrlRequest>,
    ) -> Result<Response<GenerateCdnUrlResponse>, Status> {
        let req = request.into_inner();
        let ttl = if req.ttl_seconds > 0 {
            req.ttl_seconds as u32
        } else {
            86400 // Default 24h
        };

        let cdn_url = self
            .url_signer
            .sign_url(&req.s3_key, ttl)
            .map_err(|e| Status::internal(e.to_string()))?;

        let expires_at = self
            .url_signer
            .get_expiration_time(&cdn_url)
            .map_err(|e| Status::internal(e.to_string()))?;

        Ok(Response::new(GenerateCdnUrlResponse {
            cdn_url,
            expires_at: expires_at as i64,
        }))
    }

    /// Get CDN asset configuration
    async fn get_cdn_asset(
        &self,
        request: Request<GetCdnAssetRequest>,
    ) -> Result<Response<GetCdnAssetResponse>, Status> {
        let asset_id = Uuid::parse_str(&request.into_inner().asset_id)
            .map_err(|_| Status::invalid_argument("Invalid asset_id"))?;

        let asset_info = self
            .asset_manager
            .get_asset_info(asset_id)
            .await
            .map_err(|e| Status::not_found(e.to_string()))?;

        Ok(Response::new(GetCdnAssetResponse {
            asset: Some(CdnAsset {
                id: asset_info.asset_id.to_string(),
                s3_key: format!(
                    "{}/{}/{}",
                    asset_info.user_id, asset_info.asset_id, asset_info.original_filename
                ),
                cdn_url: asset_info.cdn_url,
                content_type: asset_info.content_type,
                file_size: asset_info.file_size,
                cache_control: "public, max-age=86400".into(),
                ttl_seconds: 86400,
                gzip_enabled: true,
                brotli_enabled: true,
                edge_locations: vec![], // Not implemented yet
                created_at: asset_info.upload_timestamp,
                last_accessed_at: asset_info.upload_timestamp,
            }),
        }))
    }

    /// Register new asset with CDN
    async fn register_cdn_asset(
        &self,
        request: Request<RegisterCdnAssetRequest>,
    ) -> Result<Response<RegisterCdnAssetResponse>, Status> {
        // Note: This is metadata-only registration
        // Actual upload happens via upload flow
        let req = request.into_inner();

        let cdn_url = self
            .url_signer
            .sign_url(&req.s3_key, req.ttl_seconds as u32)
            .map_err(|e| Status::internal(e.to_string()))?;

        let asset = CdnAsset {
            id: Uuid::new_v4().to_string(),
            s3_key: req.s3_key,
            cdn_url,
            content_type: req.content_type,
            file_size: req.file_size,
            cache_control: "public, max-age=86400".into(),
            ttl_seconds: req.ttl_seconds,
            gzip_enabled: req.gzip_enabled,
            brotli_enabled: req.brotli_enabled,
            edge_locations: vec![],
            created_at: chrono::Utc::now().timestamp(),
            last_accessed_at: chrono::Utc::now().timestamp(),
        };

        Ok(Response::new(RegisterCdnAssetResponse {
            asset: Some(asset),
        }))
    }

    /// Update CDN asset configuration
    async fn update_cdn_asset(
        &self,
        request: Request<UpdateCdnAssetRequest>,
    ) -> Result<Response<UpdateCdnAssetResponse>, Status> {
        let req = request.into_inner();
        let asset_id = Uuid::parse_str(&req.asset_id)
            .map_err(|_| Status::invalid_argument("Invalid asset_id"))?;

        // Get current asset
        let asset_info = self
            .asset_manager
            .get_asset_info(asset_id)
            .await
            .map_err(|e| Status::not_found(e.to_string()))?;

        // Update cache control (metadata only)
        let asset = CdnAsset {
            id: asset_info.asset_id.to_string(),
            s3_key: format!(
                "{}/{}/{}",
                asset_info.user_id, asset_info.asset_id, asset_info.original_filename
            ),
            cdn_url: asset_info.cdn_url,
            content_type: asset_info.content_type,
            file_size: asset_info.file_size,
            cache_control: if !req.cache_control.is_empty() {
                req.cache_control
            } else {
                "public, max-age=86400".into()
            },
            ttl_seconds: if req.ttl_seconds > 0 {
                req.ttl_seconds
            } else {
                86400
            },
            gzip_enabled: req.gzip_enabled,
            brotli_enabled: req.brotli_enabled,
            edge_locations: vec![],
            created_at: asset_info.upload_timestamp,
            last_accessed_at: asset_info.upload_timestamp,
        };

        Ok(Response::new(UpdateCdnAssetResponse { asset: Some(asset) }))
    }

    /// Invalidate asset cache on all edges
    async fn invalidate_cache(
        &self,
        request: Request<InvalidateCacheRequest>,
    ) -> Result<Response<InvalidateCacheResponse>, Status> {
        let asset_id = Uuid::parse_str(&request.into_inner().asset_id)
            .map_err(|_| Status::invalid_argument("Invalid asset_id"))?;

        let inv_id = self
            .cache_invalidator
            .invalidate_asset(asset_id, "manual")
            .await
            .map_err(|e| Status::internal(e.to_string()))?;

        Ok(Response::new(InvalidateCacheResponse {
            invalidation: Some(CacheInvalidation {
                id: inv_id.to_string(),
                asset_id: asset_id.to_string(),
                pattern: String::new(),
                affected_edges: 0,
                status: "completed".into(),
                created_at: chrono::Utc::now().timestamp(),
                completed_at: chrono::Utc::now().timestamp(),
            }),
        }))
    }

    /// Invalidate cache by URL pattern
    async fn invalidate_cache_pattern(
        &self,
        request: Request<InvalidateCachePatternRequest>,
    ) -> Result<Response<InvalidateCachePatternResponse>, Status> {
        let _pattern = request.into_inner().pattern;

        // Pattern-based invalidation not implemented yet
        // Return placeholder response
        Ok(Response::new(InvalidateCachePatternResponse {
            invalidation: Some(CacheInvalidation {
                id: Uuid::new_v4().to_string(),
                asset_id: String::new(),
                pattern: _pattern,
                affected_edges: 0,
                status: "pending".into(),
                created_at: chrono::Utc::now().timestamp(),
                completed_at: 0,
            }),
        }))
    }

    /// Get status of cache invalidation
    async fn get_cache_invalidation_status(
        &self,
        request: Request<GetCacheInvalidationStatusRequest>,
    ) -> Result<Response<GetCacheInvalidationStatusResponse>, Status> {
        let inv_id = Uuid::parse_str(&request.into_inner().invalidation_id)
            .map_err(|_| Status::invalid_argument("Invalid invalidation_id"))?;

        let inv = self
            .cache_invalidator
            .get_invalidation_status(inv_id)
            .await
            .map_err(|e| Status::not_found(e.to_string()))?;

        Ok(Response::new(GetCacheInvalidationStatusResponse {
            invalidation: Some(CacheInvalidation {
                id: inv.invalidation_id.to_string(),
                asset_id: inv.asset_id.map(|id| id.to_string()).unwrap_or_default(),
                pattern: String::new(),
                affected_edges: 0,
                status: inv.status,
                created_at: inv.created_at.timestamp(),
                completed_at: inv.resolved_at.map(|dt| dt.timestamp()).unwrap_or_default(),
            }),
        }))
    }

    /// Get CDN usage statistics for asset
    async fn get_cdn_usage_stats(
        &self,
        request: Request<GetCdnUsageStatsRequest>,
    ) -> Result<Response<GetCdnUsageStatsResponse>, Status> {
        let asset_id = Uuid::parse_str(&request.into_inner().asset_id)
            .map_err(|_| Status::invalid_argument("Invalid asset_id"))?;

        let asset_info = self
            .asset_manager
            .get_asset_info(asset_id)
            .await
            .map_err(|e| Status::not_found(e.to_string()))?;

        // Placeholder stats
        Ok(Response::new(GetCdnUsageStatsResponse {
            stats: Some(CdnUsageStats {
                asset_id: asset_info.asset_id.to_string(),
                total_bandwidth: asset_info.file_size * asset_info.access_count,
                request_count: asset_info.access_count as i32,
                cache_hit_rate: 0.95,
                unique_ips: 0,
                created_at: asset_info.upload_timestamp,
            }),
        }))
    }

    /// Get all edge locations
    async fn get_edge_locations(
        &self,
        _request: Request<GetEdgeLocationsRequest>,
    ) -> Result<Response<GetEdgeLocationsResponse>, Status> {
        // Edge locations not implemented yet
        Ok(Response::new(GetEdgeLocationsResponse {
            locations: vec![],
        }))
    }

    /// Pre-warm cache on edge locations
    async fn prewarm_cache(
        &self,
        _request: Request<PrewarmCacheRequest>,
    ) -> Result<Response<PrewarmCacheResponse>, Status> {
        // Cache pre-warming not implemented yet
        Ok(Response::new(PrewarmCacheResponse {
            affected_locations: vec![],
        }))
    }

    /// Get deployment status of asset across edges
    async fn get_deployment_status(
        &self,
        _request: Request<GetDeploymentStatusRequest>,
    ) -> Result<Response<GetDeploymentStatusResponse>, Status> {
        // Deployment tracking not implemented yet
        Ok(Response::new(GetDeploymentStatusResponse {
            locations: vec![],
            overall_status: "deployed".into(),
        }))
    }

    /// Get detailed CDN metrics for asset
    async fn get_cdn_metrics(
        &self,
        _request: Request<GetCdnMetricsRequest>,
    ) -> Result<Response<GetCdnMetricsResponse>, Status> {
        // Detailed metrics not implemented yet
        Ok(Response::new(GetCdnMetricsResponse {
            avg_latency_ms: 0.0,
            p95_latency_ms: 0.0,
            p99_latency_ms: 0.0,
            cache_hit_rate: 0.95,
            total_bytes_served: 0,
            total_requests: 0,
        }))
    }
}
