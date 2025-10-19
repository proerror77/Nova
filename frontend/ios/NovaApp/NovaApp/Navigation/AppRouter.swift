import Foundation

/// Centralized app routing definition
/// All 21 screens mapped to type-safe routes
enum AppRoute: Hashable {
    // MARK: - Auth Routes (4)
    case onboarding
    case signIn
    case signUp
    case appleSignInGate

    // MARK: - Main Tab Routes (5)
    case feed
    case search
    case create
    case notifications
    case profile(userId: String?)

    // MARK: - Post Routes (2)
    case postDetail(postId: String)
    case comments(postId: String)

    // MARK: - Create Flow Routes (4)
    case photoPicker
    case imageEdit(imageData: Data)
    case publishForm(imageData: Data)
    case uploadQueue

    // MARK: - Search Routes (1)
    case userResults(query: String)

    // MARK: - Profile Routes (1)
    case editProfile

    // MARK: - Settings Routes (3)
    case settings
    case deleteAccount
    case policy(url: URL)

    // MARK: - Deep Link Route (1)
    case deepLink(URL)

    // MARK: - Route Properties
    var analyticsName: String {
        switch self {
        case .onboarding: return "onboarding"
        case .signIn: return "sign_in"
        case .signUp: return "sign_up"
        case .appleSignInGate: return "apple_sign_in"
        case .feed: return "feed"
        case .search: return "search"
        case .create: return "create"
        case .notifications: return "notifications"
        case .profile: return "profile"
        case .postDetail: return "post_detail"
        case .comments: return "comments"
        case .photoPicker: return "photo_picker"
        case .imageEdit: return "image_edit"
        case .publishForm: return "publish_form"
        case .uploadQueue: return "upload_queue"
        case .userResults: return "user_results"
        case .editProfile: return "edit_profile"
        case .settings: return "settings"
        case .deleteAccount: return "delete_account"
        case .policy: return "policy"
        case .deepLink: return "deep_link"
        }
    }

    var requiresAuth: Bool {
        switch self {
        case .onboarding, .signIn, .signUp, .appleSignInGate:
            return false
        default:
            return true
        }
    }

    /// Convert to deep link path
    var deepLinkPath: String {
        switch self {
        case .onboarding: return "/onboarding"
        case .signIn: return "/auth/signin"
        case .signUp: return "/auth/signup"
        case .appleSignInGate: return "/auth/apple"
        case .feed: return "/"
        case .search: return "/search"
        case .create: return "/create"
        case .notifications: return "/notifications"
        case .profile(let userId):
            return userId.map { "/profile/\($0)" } ?? "/profile"
        case .postDetail(let postId): return "/post/\(postId)"
        case .comments(let postId): return "/post/\(postId)/comments"
        case .photoPicker: return "/create/picker"
        case .imageEdit: return "/create/edit"
        case .publishForm: return "/create/publish"
        case .uploadQueue: return "/create/queue"
        case .userResults(let query): return "/search/users?q=\(query)"
        case .editProfile: return "/profile/edit"
        case .settings: return "/settings"
        case .deleteAccount: return "/settings/delete"
        case .policy(let url): return "/settings/policy?url=\(url.absoluteString)"
        case .deepLink(let url): return url.path
        }
    }
}

// MARK: - Route Hashable Conformance
extension AppRoute {
    func hash(into hasher: inout Hasher) {
        hasher.combine(analyticsName)
    }

    static func == (lhs: AppRoute, rhs: AppRoute) -> Bool {
        lhs.analyticsName == rhs.analyticsName
    }
}
