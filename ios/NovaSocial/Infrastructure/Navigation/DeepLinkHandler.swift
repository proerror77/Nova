import Foundation

/// Handles parsing of deep links and universal links into AppRoute
final class DeepLinkHandler {
    static let shared = DeepLinkHandler()

    /// Custom URL scheme for the app
    private let customScheme = "icered"

    /// Universal link host
    private let universalLinkHost = "icered.com"

    private init() {}

    /// Parse a URL into an AppRoute
    /// Supports both custom scheme (icered://) and universal links (https://icered.com/)
    func parse(url: URL) -> AppRoute? {
        // Check if it's a custom scheme URL
        if url.scheme == customScheme {
            return parseCustomScheme(url: url)
        }

        // Check if it's a universal link
        if url.scheme == "https" && url.host == universalLinkHost {
            return parseUniversalLink(url: url)
        }

        #if DEBUG
        print("[DeepLinkHandler] Unknown URL scheme: \(url.absoluteString)")
        #endif

        return nil
    }

    // MARK: - Custom Scheme Parsing

    /// Parse custom scheme URLs (icered://path/to/content)
    private func parseCustomScheme(url: URL) -> AppRoute? {
        guard let host = url.host else {
            return parsePathComponents(path: url.path, queryItems: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        }

        // icered://post/123 or icered://profile/user123
        let path = "/" + host + url.path
        return parsePathComponents(path: path, queryItems: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }

    // MARK: - Universal Link Parsing

    /// Parse universal links (https://icered.com/path/to/content)
    private func parseUniversalLink(url: URL) -> AppRoute? {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        return parsePathComponents(path: url.path, queryItems: queryItems)
    }

    // MARK: - Path Parsing

    /// Parse URL path components into an AppRoute
    private func parsePathComponents(path: String, queryItems: [URLQueryItem]?) -> AppRoute? {
        let components = path.split(separator: "/").map(String.init)

        guard !components.isEmpty else {
            return .home
        }

        let firstComponent = components[0].lowercased()
        let secondComponent = components.count > 1 ? components[1] : nil

        switch firstComponent {
        // MARK: - Content Routes
        case "post", "p":
            guard let postId = secondComponent else { return .home }
            return .post(id: postId)

        case "profile", "user", "u":
            guard let userId = secondComponent else { return .account }
            return .profile(userId: userId)

        case "chat", "conversation", "c":
            guard let roomId = secondComponent else { return .message }
            return .chat(roomId: roomId)

        case "channel", "ch":
            guard let channelId = secondComponent else { return .home }
            return .channel(id: channelId)

        case "comment":
            guard let postId = secondComponent else { return .home }
            return .comment(postId: postId)

        // MARK: - Main Routes
        case "home", "feed":
            return .home

        case "message", "messages", "dm":
            return .message

        case "alice", "ai":
            return .alice

        case "account", "me":
            return .account

        // MARK: - Settings Routes
        case "settings", "setting":
            if let subRoute = secondComponent?.lowercased() {
                switch subRoute {
                case "profile": return .profileSetting
                case "devices": return .devices
                case "passkeys": return .passkeys
                case "verify", "verified": return .getVerified
                default: return .settings
                }
            }
            return .settings

        // MARK: - Discovery Routes
        case "search":
            let query = queryItems?.first(where: { $0.name == "q" })?.value
            return .search(query: query)

        case "ranking", "rankings", "leaderboard":
            return .rankingList

        case "notification", "notifications":
            return .notification

        // MARK: - Social Routes
        case "invite":
            return .inviteFriends

        case "friends", "add-friends":
            return .addFriends

        case "channels", "my-channels":
            return .myChannels

        case "new-chat", "newchat":
            return .newChat

        case "group", "group-chat":
            return .groupChat

        case "new-post", "newpost", "create":
            return .newPost

        case "write":
            return .write

        // MARK: - Auth Routes
        case "login":
            return .login

        case "signup", "register", "create-account":
            return .createAccount

        case "reset-password", "resetpassword":
            if let token = queryItems?.first(where: { $0.name == "token" })?.value {
                return .resetPassword(token: token)
            }
            return .forgotPassword

        case "forgot-password", "forgotpassword":
            return .forgotPassword

        default:
            #if DEBUG
            print("[DeepLinkHandler] Unknown path: \(path)")
            #endif
            return nil
        }
    }
}

// MARK: - URL Generation

extension DeepLinkHandler {
    /// Generate a shareable URL for a route
    func generateURL(for route: AppRoute) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = universalLinkHost

        switch route {
        case .post(let id):
            components.path = "/post/\(id)"
        case .profile(let userId):
            components.path = "/user/\(userId)"
        case .chat(let roomId):
            components.path = "/chat/\(roomId)"
        case .channel(let id):
            components.path = "/channel/\(id)"
        case .search(let query):
            components.path = "/search"
            if let query = query {
                components.queryItems = [URLQueryItem(name: "q", value: query)]
            }
        case .home:
            components.path = "/home"
        case .message:
            components.path = "/messages"
        case .account:
            components.path = "/account"
        case .settings:
            components.path = "/settings"
        case .rankingList:
            components.path = "/ranking"
        default:
            return nil
        }

        return components.url
    }

    /// Generate a custom scheme URL for internal navigation
    func generateInternalURL(for route: AppRoute) -> URL? {
        var components = URLComponents()
        components.scheme = customScheme

        switch route {
        case .post(let id):
            components.host = "post"
            components.path = "/\(id)"
        case .profile(let userId):
            components.host = "user"
            components.path = "/\(userId)"
        case .chat(let roomId):
            components.host = "chat"
            components.path = "/\(roomId)"
        case .home:
            components.host = "home"
        case .message:
            components.host = "messages"
        case .account:
            components.host = "account"
        case .settings:
            components.host = "settings"
        default:
            return nil
        }

        return components.url
    }
}
