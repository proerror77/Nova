import Foundation

/// Deep link parser supporting backward compatibility
/// Handles nova://app/* and https://nova.app/* URLs
struct DeepLinkHandler {
    // MARK: - Supported URL Schemes
    private static let appScheme = "nova"
    private static let webHost = "nova.app"

    // MARK: - Parse Deep Link
    static func parse(_ url: URL) -> AppRoute? {
        // Validate scheme
        guard url.scheme == appScheme || url.scheme == "https" else {
            return nil
        }

        // Validate host for web URLs
        if url.scheme == "https", url.host != webHost {
            return nil
        }

        // Extract path components
        let path = url.path
        let components = path.split(separator: "/").map(String.init)

        // Parse route
        return parseRoute(components: components, queryItems: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }

    // MARK: - Route Parser
    private static func parseRoute(components: [String], queryItems: [URLQueryItem]?) -> AppRoute? {
        guard !components.isEmpty else {
            return .feed // Root path → Feed
        }

        switch components[0] {
        // Auth
        case "onboarding":
            return .onboarding
        case "auth":
            guard components.count > 1 else { return nil }
            switch components[1] {
            case "signin": return .signIn
            case "signup": return .signUp
            case "apple": return .appleSignInGate
            default: return nil
            }

        // Post
        case "post":
            guard components.count > 1 else { return nil }
            let postId = components[1]
            if components.count > 2, components[2] == "comments" {
                return .comments(postId: postId)
            }
            return .postDetail(postId: postId)

        // Create
        case "create":
            if components.count == 1 {
                return .create
            }
            switch components[1] {
            case "picker": return .photoPicker
            case "queue": return .uploadQueue
            default: return nil
            }

        // Search
        case "search":
            if components.count > 1, components[1] == "users" {
                let query = queryItems?.first(where: { $0.name == "q" })?.value ?? ""
                return .userResults(query: query)
            }
            return .search

        // Notifications
        case "notifications":
            return .notifications

        // Profile
        case "profile":
            if components.count > 1 {
                switch components[1] {
                case "edit": return .editProfile
                default: return .profile(userId: components[1])
                }
            }
            return .profile(userId: nil)

        // Settings
        case "settings":
            if components.count > 1 {
                switch components[1] {
                case "delete": return .deleteAccount
                case "policy":
                    if let urlString = queryItems?.first(where: { $0.name == "url" })?.value,
                       let url = URL(string: urlString) {
                        return .policy(url: url)
                    }
                    return nil
                default: return nil
                }
            }
            return .settings

        default:
            return nil
        }
    }

    // MARK: - Generate Deep Link
    static func generateDeepLink(for route: AppRoute) -> URL? {
        let baseURL = "\(appScheme)://app"
        let path = route.deepLinkPath
        return URL(string: "\(baseURL)\(path)")
    }

    // MARK: - Generate Web Link (for sharing)
    static func generateWebLink(for route: AppRoute) -> URL? {
        let baseURL = "https://\(webHost)"
        let path = route.deepLinkPath
        return URL(string: "\(baseURL)\(path)")
    }
}

// MARK: - Backward Compatibility Support
extension DeepLinkHandler {
    /// Legacy URL format: nova://post?id=123 → nova://app/post/123
    static func parseLegacy(_ url: URL) -> AppRoute? {
        guard url.scheme == appScheme else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = url.host

        switch host {
        case "post":
            if let postId = components?.queryItems?.first(where: { $0.name == "id" })?.value {
                return .postDetail(postId: postId)
            }
        case "profile":
            if let userId = components?.queryItems?.first(where: { $0.name == "id" })?.value {
                return .profile(userId: userId)
            }
        default:
            break
        }

        return nil
    }
}
