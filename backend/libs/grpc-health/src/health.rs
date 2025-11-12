//! Health status types and conversions

/// Service health status
///
/// Represents the health state of a service or component.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HealthStatus {
    /// Service is healthy and can accept traffic
    Serving,
    /// Service is unhealthy and should not accept traffic
    NotServing,
    /// Service status is unknown (not registered)
    Unknown,
}

impl From<HealthStatus> for tonic_health::ServingStatus {
    fn from(status: HealthStatus) -> Self {
        match status {
            HealthStatus::Serving => tonic_health::ServingStatus::Serving,
            HealthStatus::NotServing => tonic_health::ServingStatus::NotServing,
            HealthStatus::Unknown => tonic_health::ServingStatus::Unknown,
        }
    }
}

impl From<tonic_health::ServingStatus> for HealthStatus {
    fn from(status: tonic_health::ServingStatus) -> Self {
        match status {
            tonic_health::ServingStatus::Serving => HealthStatus::Serving,
            tonic_health::ServingStatus::NotServing => HealthStatus::NotServing,
            tonic_health::ServingStatus::Unknown => HealthStatus::Unknown,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_health_status_to_serving_status() {
        assert_eq!(
            tonic_health::ServingStatus::from(HealthStatus::Serving),
            tonic_health::ServingStatus::Serving
        );
        assert_eq!(
            tonic_health::ServingStatus::from(HealthStatus::NotServing),
            tonic_health::ServingStatus::NotServing
        );
        assert_eq!(
            tonic_health::ServingStatus::from(HealthStatus::Unknown),
            tonic_health::ServingStatus::Unknown
        );
    }

    #[test]
    fn test_serving_status_to_health_status() {
        assert_eq!(
            HealthStatus::from(tonic_health::ServingStatus::Serving),
            HealthStatus::Serving
        );
        assert_eq!(
            HealthStatus::from(tonic_health::ServingStatus::NotServing),
            HealthStatus::NotServing
        );
        assert_eq!(
            HealthStatus::from(tonic_health::ServingStatus::Unknown),
            HealthStatus::Unknown
        );
    }
}
