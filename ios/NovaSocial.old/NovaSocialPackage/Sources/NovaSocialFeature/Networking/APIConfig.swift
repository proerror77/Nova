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
            // Note: kubectl port-forward binds to localhost, so both simulator and device use localhost
            // Using content-service for posts/feed data
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
        // Real JWT token from auth-service (registered user: iostest@nova.app)
        // Expires: ~1 hour after generation (2025-11-03 21:33:03 UTC)
        return "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.eyJzdWIiOiI0ZjI4YTQ3OC05ODUzLTRkZDgtYTE2Yy0xNDU4NjUwNGYwZTYiLCJpYXQiOjE3NjIyMTc5ODMsImV4cCI6MTc2MjIyMTU4MywidG9rZW5fdHlwZSI6ImFjY2VzcyIsImVtYWlsIjoiaW9zdGVzdEBub3ZhLmFwcCIsInVzZXJuYW1lIjoiaW9zdGVzdCJ9.evJyrE3mPg8RdhaK_RbVI6ftVWT6bYoL6-yjn8vWqbVkZtanBAsgszT4YtTjMlOZFsiCfeHeyrZvFlyCMSHjKFR3fblboxM_dRdFTBT1TwVAAVcprhAx7JLm00528JkWfwa_IbOjwoWNrJ0NFk8Y7Jly8qDB23sF-FMAE4MM4mVQQVSlbbxRnR43C5UTFz27ADxoi3Yrx6aB_oDUiR9qRZrCGlupA0-u-V8r6-BYuP9eeskj_gtxxFrXFpx2WtyiINOymenJCG6YVYGRFI9QpxWO_nThg6vAnIwS9g4WK6khnLRwETNzxaqL3Y-IxCoVIERnafxfsoATQ7_FE4qtcw"
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
