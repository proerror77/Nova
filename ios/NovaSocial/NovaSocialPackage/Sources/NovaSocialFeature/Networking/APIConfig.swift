import Foundation

/// API Environment configuration
enum APIEnvironment: Sendable {
    case development
    case stagingLocal
    case stagingGitHub
    case stagingProxy
    case production

    var baseURL: String {
        switch self {
        case .development:
            return "http://localhost:8080"
        case .stagingLocal:
            return "http://localhost:8080"
        case .stagingGitHub:
            return "https://staging-api.nova.app"
        case .stagingProxy:
            return "http://localhost:8080"
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
        case .production:
            return "Production"
        }
    }

    var isLocalhost: Bool {
        self == .development || self == .stagingLocal || self == .stagingProxy
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
            case "production", "prod":
                return .production
            default:
                break
            }
        }

        // Default based on build configuration
        #if DEBUG
        // In debug builds, default to proxy for accessing GitHub Staging in simulator
        return .stagingProxy
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
        return "demo_token_for_testing"
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
        // Allow any certificate for localhost development
        let host = challenge.protectionSpace.host

        if (host.contains("localhost") || host.contains("127.0.0.1")) {
            if let trust = challenge.protectionSpace.serverTrust {
                let credential = URLCredential(trust: trust)
                completionHandler(.useCredential, credential)
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
