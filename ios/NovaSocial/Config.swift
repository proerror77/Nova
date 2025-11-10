import Foundation

/// Environment Configuration
enum Environment {
    case development
    case staging
    case production

    /// Current environment (can be overridden in build settings)
    static var current: Environment {
        #if DEBUG
        return .development
        #else
        // Check for staging build configuration
        #if STAGING
        return .staging
        #else
        return .production
        #endif
        #endif
    }
}

/// API Configuration
enum APIConfig {
    /// Base GraphQL endpoint
    static let baseURL: String = {
        switch Environment.current {
        case .development:
            // Local development: kubectl port-forward -n nova-gateway svc/graphql-gateway 8080:8080
            return "http://localhost:8080/graphql"

        case .staging:
            // Staging environment (when ALB is ready)
            return "https://api-staging.nova.social/graphql"

        case .production:
            // Production environment
            return "https://api.nova.social/graphql"
        }
    }()

    /// WebSocket endpoint for real-time messaging
    static let websocketURL: String = {
        switch Environment.current {
        case .development:
            return "ws://localhost:8080/ws"

        case .staging:
            return "wss://api-staging.nova.social/ws"

        case .production:
            return "wss://api.nova.social/ws"
        }
    }()

    /// Health check endpoint
    static let healthCheckURL: String = {
        switch Environment.current {
        case .development:
            return "http://localhost:8080/health"

        case .staging:
            return "https://api-staging.nova.social/health"

        case .production:
            return "https://api.nova.social/health"
        }
    }()

    /// GraphQL Playground URL (for debugging)
    static let playgroundURL: String = {
        switch Environment.current {
        case .development:
            return "http://localhost:8080/playground"

        case .staging:
            return "https://api-staging.nova.social/playground"

        case .production:
            // Playground disabled in production
            return ""
        }
    }()

    /// Request timeout
    static let timeoutInterval: TimeInterval = {
        switch Environment.current {
        case .development:
            return 60.0  // Longer timeout for debugging

        case .staging, .production:
            return 30.0
        }
    }()

    /// Enable debug logging
    static let enableLogging: Bool = {
        switch Environment.current {
        case .development, .staging:
            return true

        case .production:
            return false
        }
    }()

    /// Enable GraphQL query logging
    static let logGraphQLQueries: Bool = {
        switch Environment.current {
        case .development:
            return true

        case .staging, .production:
            return false
        }
    }()

    /// Enable performance monitoring
    static let enablePerformanceMonitoring: Bool = {
        switch Environment.current {
        case .development:
            return false

        case .staging, .production:
            return true
        }
    }()
}

/// Authentication Storage Keys
enum AuthKeys {
    static let accessToken = "nova.auth.accessToken"
    static let refreshToken = "nova.auth.refreshToken"
    static let userId = "nova.auth.userId"
}
