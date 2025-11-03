import Foundation

/// API Environment configuration
enum APIEnvironment: Sendable {
    case development
    case stagingLocal
    case stagingGitHub
    case stagingProxy
    case stagingAWS
    case production

    var baseURL: String {
        switch self {
        case .development:
            // iOS Simulator: Use host.docker.internal to access Docker on host
            // iOS Device: Use localhost:3000 (device connects directly to host in local dev)
            #if targetEnvironment(simulator)
            return "http://host.docker.internal:3000"
            #else
            return "http://localhost:3000"
            #endif
        case .stagingLocal:
            // Docker local setup - same as development
            #if targetEnvironment(simulator)
            return "http://host.docker.internal:3000"
            #else
            return "http://localhost:3000"
            #endif
        case .stagingGitHub:
            return "https://staging-api.nova.app"
        case .stagingProxy:
            // Proxy server for GitHub staging access
            #if targetEnvironment(simulator)
            return "http://host.docker.internal:3000"
            #else
            return "http://localhost:3000"
            #endif
        case .stagingAWS:
            // AWS backend via port-forward
            // You need to run: kubectl port-forward -n nova svc/content-service 8081:8081
            // For complete functionality, you may also need:
            //   - kubectl port-forward -n nova svc/user-service 8083:8083 (for feed/users endpoints)
            // Note: kubectl port-forward binds to localhost, so both simulator and device use localhost
            return "http://localhost:8081"
        case .production:
            return "https://api.nova.app"
        }
    }

    var description: String {
        switch self {
        case .development:
            return "Development (Local REST API)"
        case .stagingLocal:
            return "Staging (Local Docker)"
        case .stagingGitHub:
            return "Staging (GitHub - Remote)"
        case .stagingProxy:
            return "Staging (GitHub via Local Proxy)"
        case .stagingAWS:
            return "Staging (AWS via Port-Forward)"
        case .production:
            return "Production"
        }
    }

    var isLocalhost: Bool {
        self == .development || self == .stagingLocal || self == .stagingProxy || self == .stagingAWS
    }
}

/// API Configuration for Nova Social backend
enum APIConfig {
    /// Current environment (change this to switch environments)
    /// Set via environment variable: API_ENV=stagingLocal or API_ENV=stagingGitHub or API_ENV=production
    static let environment: APIEnvironment = {
        if let envString = ProcessInfo.processInfo.environment["API_ENV"] {
            // Try to match by case name (e.g., "stagingLocal", "stagingGitHub")
            switch envString.lowercased() {
            case "development", "dev", "local":
                return .development
            case "staging_local", "staginglocal", "docker":
                return .stagingLocal
            case "staging_github", "staginggithub", "staging":
                return .stagingGitHub
            case "staging_proxy", "stagingproxy", "proxy":
                return .stagingProxy
            case "staging_aws", "stagingaws", "aws":
                return .stagingAWS
            case "production", "prod":
                return .production
            default:
                break
            }
        }

        // Default based on build configuration
        #if DEBUG
        // In debug builds, default to AWS staging for accessing real data
        return .stagingAWS
        #else
        return .production
        #endif
    }()

    static let baseURL = URL(string: environment.baseURL)!

    /// Demo token for testing - replace with real token in production
    static let authToken: String = {
        if let token = ProcessInfo.processInfo.environment["API_TOKEN"] {
            return token
        }
        // Real JWT token from auth-service (registered user: testios@nova.app)
        // Expires: ~1 hour after generation (2025-11-03)
        return "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxYzBkNWM4ZC02NmEwLTRjNTItYWEyZS05ODJlNWUxZDA4NWUiLCJpYXQiOjE3NjIxNTAwODgsImV4cCI6MTc2MjE1MzY4OCwidG9rZW5fdHlwZSI6ImFjY2VzcyIsImVtYWlsIjoidGVzdGlvc0Bub3ZhLmFwcCIsInVzZXJuYW1lIjoidGVzdGlvcyJ9.KhH5JCCYzXMZSZk7k5XNF4k6zYmyjcgxh_wvbS2u-qmN85QrUnv1cyoLsbuEohsHICRWvtKVNkYuv8jLS2HycE3AJ5XUjrJPT1lvEUI35GLIf6iZz7a2m-puGv0l9PSI_pjXcPCIGHV6O9xooowUXSq2lP79B1wuglR0uQ8O-y-116208ij_P21_22WF7yPeogDY7U-T-nMTPcjOt7W3WGmum4WRS-VdhXtKWET-WgCdVF324f79i_k8vGC8xyl7tplhUsRjJtTxm9Owh_EreRRi-0lDJmWKn0kXjm2GFDZNmoh2KC9Cf6Di3Lj34QeOTQXyJjRUAre-NMH7hYO_QA"
    }()

    static let requestTimeout: TimeInterval = 10.0

    /// URLSession configuration that allows HTTP for localhost testing
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = requestTimeout
        config.waitsForConnectivity = true

        // Allow HTTP for localhost/development
        if environment.isLocalhost {
            let delegate = LocalDevelopmentDelegate()
            return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        }

        return URLSession(configuration: config)
    }()

    static func makeHeaders() -> [String: String] {
        [
            "Authorization": "Bearer \(authToken)",
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }

    /// Debug info showing current configuration
    static var debugInfo: String {
        """
        API Configuration:
        - Environment: \(environment.description)
        - Base URL: \(baseURL.absoluteString)
        - Timeout: \(requestTimeout)s
        - Auth Token: \(authToken.prefix(20))...
        """
    }
}

// MARK: - Local Development TLS Handling

/// URLSessionDelegate that allows HTTP connections for localhost development
private final class LocalDevelopmentDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Allow any certificate for localhost/host.docker.internal development
        let host = challenge.protectionSpace.host

        if (host.contains("localhost") || host.contains("127.0.0.1") || host.contains("host.docker.internal")) {
            if let trust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: trust)
                completionHandler(.useCredential, credential)
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
