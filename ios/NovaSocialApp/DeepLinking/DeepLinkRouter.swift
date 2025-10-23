//
//  DeepLinkRouter.swift
//  NovaSocial
//
//  Created by Nova Team
//  Deep link routing system for handling Universal Links and custom URL schemes
//

import Foundation
import SwiftUI
import Combine

// MARK: - Deep Link Route

/// Represents a deep link destination in the app
enum DeepLinkRoute: Equatable {
    // MARK: - User Routes
    case userProfile(userId: String)
    case currentUserProfile
    case editProfile

    // MARK: - Content Routes
    case post(postId: String)
    case feed
    case explore
    case notifications

    // MARK: - Search Routes
    case search(query: String?)
    case searchUsers
    case searchPosts
    case searchHashtag(tag: String)

    // MARK: - Authentication Routes
    case login
    case signup
    case emailVerification(token: String)
    case passwordReset(token: String)
    case oauth(provider: String, code: String?)

    // MARK: - Settings Routes
    case settings
    case privacySettings
    case accountSettings
    case notificationSettings

    // MARK: - Social Routes
    case followers(userId: String)
    case following(userId: String)
    case conversation(conversationId: String)

    // MARK: - Media Routes
    case camera
    case mediaLibrary

    // MARK: - Fallback
    case unknown(url: URL)
    case invalid(error: String)
}

// MARK: - Deep Link Router

/// Centralized router for handling deep links throughout the app
@MainActor
class DeepLinkRouter: ObservableObject {

    // MARK: - Published Properties

    @Published var currentRoute: DeepLinkRoute?
    @Published var isProcessingDeepLink = false

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private let analyticsService: AnalyticsService?

    // MARK: - Initialization

    init(analyticsService: AnalyticsService? = nil) {
        self.analyticsService = analyticsService
    }

    // MARK: - URL Scheme Configuration

    /// Custom URL scheme for the app
    static let customScheme = "novasocial"

    /// Universal Link domain
    static let universalLinkDomain = "nova.social"

    // MARK: - Route Parsing

    /// Parse a URL into a DeepLinkRoute
    func parse(url: URL) -> DeepLinkRoute {
        // Track deep link
        trackDeepLink(url: url)

        // Handle custom scheme: novasocial://
        if url.scheme == Self.customScheme {
            return parseCustomScheme(url: url)
        }

        // Handle Universal Links: https://nova.social/
        if url.host == Self.universalLinkDomain || url.host == "www.\(Self.universalLinkDomain)" {
            return parseUniversalLink(url: url)
        }

        // Unknown URL
        return .unknown(url: url)
    }

    /// Handle a deep link by navigating to the appropriate route
    func handle(url: URL) {
        isProcessingDeepLink = true

        let route = parse(url: url)
        currentRoute = route

        // Announce navigation for accessibility
        announceRouteChange(route: route)

        isProcessingDeepLink = false
    }

    // MARK: - Custom Scheme Parsing

    private func parseCustomScheme(url: URL) -> DeepLinkRoute {
        guard let host = url.host else {
            return .invalid(error: "Missing host in URL scheme")
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        switch host {
        // User routes
        case "user":
            if let userId = pathComponents.first {
                return .userProfile(userId: userId)
            }
            return .currentUserProfile

        // Post routes
        case "post":
            guard let postId = pathComponents.first else {
                return .invalid(error: "Missing post ID")
            }
            return .post(postId: postId)

        // Search routes
        case "search":
            let query = queryItems?.first(where: { $0.name == "q" })?.value
            return .search(query: query)

        // Notifications
        case "notifications":
            return .notifications

        // Feed
        case "feed":
            return .feed

        // Explore
        case "explore":
            return .explore

        // Auth routes
        case "auth":
            guard let action = pathComponents.first else {
                return .invalid(error: "Missing auth action")
            }

            switch action {
            case "verify":
                guard let token = queryItems?.first(where: { $0.name == "token" })?.value else {
                    return .invalid(error: "Missing verification token")
                }
                return .emailVerification(token: token)

            case "reset-password":
                guard let token = queryItems?.first(where: { $0.name == "token" })?.value else {
                    return .invalid(error: "Missing reset token")
                }
                return .passwordReset(token: token)

            case "oauth":
                guard let provider = pathComponents.dropFirst().first else {
                    return .invalid(error: "Missing OAuth provider")
                }
                let code = queryItems?.first(where: { $0.name == "code" })?.value
                let state = queryItems?.first(where: { $0.name == "state" })?.value
                return .oauth(provider: provider, code: code, state: state)

            default:
                return .invalid(error: "Unknown auth action: \(action)")
            }

        // Settings routes
        case "settings":
            if let section = pathComponents.first {
                switch section {
                case "privacy":
                    return .privacySettings
                case "account":
                    return .accountSettings
                case "notifications":
                    return .notificationSettings
                default:
                    return .settings
                }
            }
            return .settings

        // Camera
        case "camera":
            return .camera

        // Media library
        case "media":
            return .mediaLibrary

        default:
            return .invalid(error: "Unknown host: \(host)")
        }
    }

    // MARK: - Universal Link Parsing

    private func parseUniversalLink(url: URL) -> DeepLinkRoute {
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        guard !pathComponents.isEmpty else {
            return .feed // Root URL -> Feed
        }

        switch pathComponents[0] {
        // User profile: https://nova.social/user/123
        case "user", "u", "@":
            guard pathComponents.count >= 2 else {
                return .invalid(error: "Missing user ID")
            }
            let userId = pathComponents[1]

            // Followers: /user/123/followers
            if pathComponents.count >= 3 {
                switch pathComponents[2] {
                case "followers":
                    return .followers(userId: userId)
                case "following":
                    return .following(userId: userId)
                default:
                    break
                }
            }

            return .userProfile(userId: userId)

        // Post: https://nova.social/post/456
        case "post", "p":
            guard pathComponents.count >= 2 else {
                return .invalid(error: "Missing post ID")
            }
            return .post(postId: pathComponents[1])

        // Search: https://nova.social/search?q=query
        case "search":
            let query = queryItems?.first(where: { $0.name == "q" })?.value
            return .search(query: query)

        // Hashtag: https://nova.social/hashtag/swift
        case "hashtag", "tag":
            guard pathComponents.count >= 2 else {
                return .invalid(error: "Missing hashtag")
            }
            return .searchHashtag(tag: pathComponents[1])

        // Notifications: https://nova.social/notifications
        case "notifications":
            return .notifications

        // Explore: https://nova.social/explore
        case "explore":
            return .explore

        // Settings: https://nova.social/settings
        case "settings":
            if pathComponents.count >= 2 {
                switch pathComponents[1] {
                case "privacy":
                    return .privacySettings
                case "account":
                    return .accountSettings
                case "notifications":
                    return .notificationSettings
                default:
                    return .settings
                }
            }
            return .settings

        // Auth verification: https://nova.social/verify?token=xxx
        case "verify":
            guard let token = queryItems?.first(where: { $0.name == "token" })?.value else {
                return .invalid(error: "Missing verification token")
            }
            return .emailVerification(token: token)

        // Password reset: https://nova.social/reset-password?token=xxx
        case "reset-password":
            guard let token = queryItems?.first(where: { $0.name == "token" })?.value else {
                return .invalid(error: "Missing reset token")
            }
            return .passwordReset(token: token)

        default:
            return .invalid(error: "Unknown path: /\(pathComponents.joined(separator: "/"))")
        }
    }

    // MARK: - URL Generation

    /// Generate a shareable URL for a route
    func generateURL(for route: DeepLinkRoute, preferUniversalLink: Bool = true) -> URL? {
        if preferUniversalLink {
            return generateUniversalLink(for: route)
        } else {
            return generateCustomSchemeURL(for: route)
        }
    }

    private func generateUniversalLink(for route: DeepLinkRoute) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.universalLinkDomain

        switch route {
        case .userProfile(let userId):
            components.path = "/user/\(userId)"

        case .post(let postId):
            components.path = "/post/\(postId)"

        case .search(let query):
            components.path = "/search"
            if let query = query {
                components.queryItems = [URLQueryItem(name: "q", value: query)]
            }

        case .searchHashtag(let tag):
            components.path = "/hashtag/\(tag)"

        case .notifications:
            components.path = "/notifications"

        case .feed:
            components.path = "/"

        case .explore:
            components.path = "/explore"

        case .followers(let userId):
            components.path = "/user/\(userId)/followers"

        case .following(let userId):
            components.path = "/user/\(userId)/following"

        case .emailVerification(let token):
            components.path = "/verify"
            components.queryItems = [URLQueryItem(name: "token", value: token)]

        case .passwordReset(let token):
            components.path = "/reset-password"
            components.queryItems = [URLQueryItem(name: "token", value: token)]

        case .settings:
            components.path = "/settings"

        case .privacySettings:
            components.path = "/settings/privacy"

        case .accountSettings:
            components.path = "/settings/account"

        case .notificationSettings:
            components.path = "/settings/notifications"

        default:
            return nil
        }

        return components.url
    }

    private func generateCustomSchemeURL(for route: DeepLinkRoute) -> URL? {
        var components = URLComponents()
        components.scheme = Self.customScheme

        switch route {
        case .userProfile(let userId):
            components.host = "user"
            components.path = "/\(userId)"

        case .post(let postId):
            components.host = "post"
            components.path = "/\(postId)"

        case .search(let query):
            components.host = "search"
            if let query = query {
                components.queryItems = [URLQueryItem(name: "q", value: query)]
            }

        case .notifications:
            components.host = "notifications"

        case .feed:
            components.host = "feed"

        case .explore:
            components.host = "explore"

        case .emailVerification(let token):
            components.host = "auth"
            components.path = "/verify"
            components.queryItems = [URLQueryItem(name: "token", value: token)]

        case .passwordReset(let token):
            components.host = "auth"
            components.path = "/reset-password"
            components.queryItems = [URLQueryItem(name: "token", value: token)]

        case .settings:
            components.host = "settings"

        case .camera:
            components.host = "camera"

        case .mediaLibrary:
            components.host = "media"

        default:
            return nil
        }

        return components.url
    }

    // MARK: - Analytics

    private func trackDeepLink(url: URL) {
        analyticsService?.track(event: "deep_link_opened", properties: [
            "url": url.absoluteString,
            "scheme": url.scheme ?? "unknown",
            "host": url.host ?? "unknown"
        ])
    }

    // MARK: - Accessibility

    private func announceRouteChange(route: DeepLinkRoute) {
        let announcement = routeAnnouncement(for: route)
        AccessibilityHelper.announceScreenChange()
        AccessibilityHelper.announce(announcement)
    }

    private func routeAnnouncement(for route: DeepLinkRoute) -> String {
        switch route {
        case .userProfile(let userId):
            return "Opening profile for user \(userId)"
        case .currentUserProfile:
            return "Opening your profile"
        case .post(let postId):
            return "Opening post \(postId)"
        case .search(let query):
            if let query = query {
                return "Searching for \(query)"
            }
            return "Opening search"
        case .notifications:
            return "Opening notifications"
        case .feed:
            return "Opening feed"
        case .explore:
            return "Opening explore"
        case .settings:
            return "Opening settings"
        case .camera:
            return "Opening camera"
        case .invalid(let error):
            return "Invalid link: \(error)"
        default:
            return "Navigating"
        }
    }
}

// MARK: - Analytics Service Protocol

protocol AnalyticsService {
    func track(event: String, properties: [String: Any])
}

// MARK: - Deep Link Builder

/// Helper for building deep links programmatically
struct DeepLinkBuilder {

    static func userProfile(userId: String) -> URL? {
        DeepLinkRouter().generateURL(for: .userProfile(userId: userId))
    }

    static func post(postId: String) -> URL? {
        DeepLinkRouter().generateURL(for: .post(postId: postId))
    }

    static func search(query: String) -> URL? {
        DeepLinkRouter().generateURL(for: .search(query: query))
    }

    static func hashtag(tag: String) -> URL? {
        DeepLinkRouter().generateURL(for: .searchHashtag(tag: tag))
    }

    static func emailVerification(token: String) -> URL? {
        DeepLinkRouter().generateURL(for: .emailVerification(token: token))
    }

    static func passwordReset(token: String) -> URL? {
        DeepLinkRouter().generateURL(for: .passwordReset(token: token))
    }
}

// MARK: - Deep Link Share Extension

extension DeepLinkRoute {

    /// Get a shareable message for this route
    var shareMessage: String? {
        switch self {
        case .userProfile(let userId):
            return "Check out this profile on Nova Social!"
        case .post(let postId):
            return "Check out this post on Nova Social!"
        case .searchHashtag(let tag):
            return "Explore #\(tag) on Nova Social!"
        default:
            return "Check this out on Nova Social!"
        }
    }

    /// Get activity items for sharing
    func activityItems(router: DeepLinkRouter) -> [Any] {
        var items: [Any] = []

        if let url = router.generateURL(for: self) {
            items.append(url)
        }

        if let message = shareMessage {
            items.append(message)
        }

        return items
    }
}
