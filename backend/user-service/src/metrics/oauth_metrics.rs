/// OAuth and authentication provider metrics
use lazy_static::lazy_static;
use prometheus::{
    register_counter_vec_with_registry, register_gauge_with_registry,
    register_histogram_vec_with_registry, CounterVec, Gauge, HistogramVec,
};

use super::REGISTRY;

lazy_static! {
    // ======================
    // Counters - OAuth Requests
    // ======================

    /// Total OAuth authorization code exchanges (labels: provider, status)
    /// provider: apple, google, facebook
    /// status: success, invalid_code, invalid_state, network_error, timeout
    pub static ref OAUTH_TOKEN_EXCHANGES_TOTAL: CounterVec = register_counter_vec_with_registry!(
        "oauth_token_exchanges_total",
        "Total OAuth token exchange attempts",
        &["provider", "status"],
        REGISTRY
    )
    .unwrap();

    /// Total OAuth user links (labels: provider, status)
    /// status: success, already_linked, conflict, error
    pub static ref OAUTH_LINK_OPERATIONS_TOTAL: CounterVec = register_counter_vec_with_registry!(
        "oauth_link_operations_total",
        "Total OAuth provider link operations",
        &["provider", "status"],
        REGISTRY
    )
    .unwrap();

    /// Total OAuth provider unlinks (labels: provider, status)
    pub static ref OAUTH_UNLINK_OPERATIONS_TOTAL: CounterVec = register_counter_vec_with_registry!(
        "oauth_unlink_operations_total",
        "Total OAuth provider unlink operations",
        &["provider", "status"],
        REGISTRY
    )
    .unwrap();

    /// Total OAuth state validations (labels: provider, result)
    /// result: valid, invalid, expired
    pub static ref OAUTH_STATE_VALIDATIONS_TOTAL: CounterVec = register_counter_vec_with_registry!(
        "oauth_state_validations_total",
        "Total OAuth state parameter validations",
        &["provider", "result"],
        REGISTRY
    )
    .unwrap();

    /// Total JWKS cache operations (labels: provider, operation, result)
    /// operation: get, set, refresh
    /// result: hit, miss, success, error
    pub static ref JWKS_CACHE_OPERATIONS_TOTAL: CounterVec = register_counter_vec_with_registry!(
        "jwks_cache_operations_total",
        "Total JWKS cache operations",
        &["provider", "operation", "result"],
        REGISTRY
    )
    .unwrap();

    /// Total ID token validations (labels: provider, status)
    /// status: valid, invalid_signature, invalid_audience, invalid_issuer, expired
    pub static ref OAUTH_ID_TOKEN_VALIDATIONS_TOTAL: CounterVec = register_counter_vec_with_registry!(
        "oauth_id_token_validations_total",
        "Total ID token validation attempts",
        &["provider", "status"],
        REGISTRY
    )
    .unwrap();

    /// Total OAuth token refreshes (labels: provider, status)
    /// status: success, token_expired, invalid_refresh_token, network_error
    pub static ref OAUTH_TOKEN_REFRESHES_TOTAL: CounterVec = register_counter_vec_with_registry!(
        "oauth_token_refreshes_total",
        "Total OAuth token refresh attempts",
        &["provider", "status"],
        REGISTRY
    )
    .unwrap();

    /// Total new users created via OAuth (labels: provider)
    pub static ref OAUTH_NEW_USERS_CREATED_TOTAL: CounterVec = register_counter_vec_with_registry!(
        "oauth_new_users_created_total",
        "Total new users created via OAuth",
        &["provider"],
        REGISTRY
    )
    .unwrap();

    // ======================
    // Histograms - OAuth Latency
    // ======================

    /// OAuth token exchange latency (labels: provider)
    /// Measures time from code submission to token receipt
    pub static ref OAUTH_TOKEN_EXCHANGE_DURATION_SECONDS: HistogramVec = register_histogram_vec_with_registry!(
        "oauth_token_exchange_duration_seconds",
        "OAuth token exchange latency in seconds",
        &["provider"],
        vec![0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
        REGISTRY
    )
    .unwrap();

    /// ID token validation latency (labels: provider)
    /// Measures time to validate JWT signature and claims
    pub static ref OAUTH_ID_TOKEN_VALIDATION_DURATION_SECONDS: HistogramVec = register_histogram_vec_with_registry!(
        "oauth_id_token_validation_duration_seconds",
        "ID token validation latency in seconds",
        &["provider"],
        vec![0.0001, 0.0005, 0.001, 0.005, 0.01, 0.025, 0.05, 0.1],
        REGISTRY
    )
    .unwrap();

    /// JWKS fetch latency (labels: provider, source)
    /// source: cache_hit, cache_miss_fetch
    pub static ref JWKS_FETCH_DURATION_SECONDS: HistogramVec = register_histogram_vec_with_registry!(
        "jwks_fetch_duration_seconds",
        "JWKS fetch latency in seconds",
        &["provider", "source"],
        vec![0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0],
        REGISTRY
    )
    .unwrap();

    /// OAuth provider API response latency (labels: provider, endpoint)
    /// endpoint: token, userinfo, authorize
    pub static ref OAUTH_PROVIDER_API_DURATION_SECONDS: HistogramVec = register_histogram_vec_with_registry!(
        "oauth_provider_api_duration_seconds",
        "OAuth provider API response latency in seconds",
        &["provider", "endpoint"],
        vec![0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
        REGISTRY
    )
    .unwrap();

    // ======================
    // Gauges - OAuth State
    // ======================

    /// Current number of cached JWKS sets (labels: provider)
    pub static ref JWKS_CACHE_SIZE: Gauge = register_gauge_with_registry!(
        "jwks_cache_size",
        "Number of JWKS sets in cache",
        REGISTRY
    )
    .unwrap();

    /// Current number of JWKS keys in memory (labels: provider)
    pub static ref JWKS_KEYS_LOADED: Gauge = register_gauge_with_registry!(
        "jwks_keys_loaded",
        "Number of JWKS keys currently loaded",
        REGISTRY
    )
    .unwrap();
}

// Helper functions for recording metrics
pub mod helpers {
    use super::*;
    use std::time::Instant;

    /// Scope for measuring operation duration
    pub struct TimingScope {
        start: Instant,
        provider: String,
        endpoint: String,
    }

    impl TimingScope {
        /// Create a new timing scope for OAuth provider API
        pub fn new_provider_api(provider: &str, endpoint: &str) -> Self {
            Self {
                start: Instant::now(),
                provider: provider.to_string(),
                endpoint: endpoint.to_string(),
            }
        }

        /// Record the elapsed time to metrics
        pub fn record(self) {
            let duration = self.start.elapsed().as_secs_f64();
            OAUTH_PROVIDER_API_DURATION_SECONDS
                .with_label_values(&[&self.provider, &self.endpoint])
                .observe(duration);
        }
    }

    /// Record OAuth token exchange success
    pub fn record_token_exchange_success(provider: &str, duration_secs: f64) {
        OAUTH_TOKEN_EXCHANGES_TOTAL
            .with_label_values(&[provider, "success"])
            .inc();
        OAUTH_TOKEN_EXCHANGE_DURATION_SECONDS
            .with_label_values(&[provider])
            .observe(duration_secs);
    }

    /// Record OAuth token exchange failure
    pub fn record_token_exchange_error(provider: &str, reason: &str) {
        OAUTH_TOKEN_EXCHANGES_TOTAL
            .with_label_values(&[provider, reason])
            .inc();
    }

    /// Record ID token validation result
    pub fn record_id_token_validation(provider: &str, status: &str, duration_secs: f64) {
        OAUTH_ID_TOKEN_VALIDATIONS_TOTAL
            .with_label_values(&[provider, status])
            .inc();
        OAUTH_ID_TOKEN_VALIDATION_DURATION_SECONDS
            .with_label_values(&[provider])
            .observe(duration_secs);
    }

    /// Record JWKS cache operation
    pub fn record_jwks_cache_operation(provider: &str, operation: &str, result: &str) {
        JWKS_CACHE_OPERATIONS_TOTAL
            .with_label_values(&[provider, operation, result])
            .inc();
    }

    /// Record JWKS fetch with source (cache or fetch)
    pub fn record_jwks_fetch(provider: &str, source: &str, duration_secs: f64) {
        JWKS_FETCH_DURATION_SECONDS
            .with_label_values(&[provider, source])
            .observe(duration_secs);
    }

    /// Record OAuth link operation
    pub fn record_link_operation(provider: &str, status: &str) {
        OAUTH_LINK_OPERATIONS_TOTAL
            .with_label_values(&[provider, status])
            .inc();
    }

    /// Record OAuth unlink operation
    pub fn record_unlink_operation(provider: &str, status: &str) {
        OAUTH_UNLINK_OPERATIONS_TOTAL
            .with_label_values(&[provider, status])
            .inc();
    }

    /// Record token refresh
    pub fn record_token_refresh(provider: &str, status: &str) {
        OAUTH_TOKEN_REFRESHES_TOTAL
            .with_label_values(&[provider, status])
            .inc();
    }

    /// Record new user created via OAuth
    pub fn record_new_user_created(provider: &str) {
        OAUTH_NEW_USERS_CREATED_TOTAL
            .with_label_values(&[provider])
            .inc();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_oauth_metrics_initialization() {
        // Verify metrics can be recorded without panicking
        helpers::record_token_exchange_success("google", 0.5);
        helpers::record_id_token_validation("apple", "valid", 0.01);
        helpers::record_jwks_cache_operation("google", "get", "hit");
    }
}
