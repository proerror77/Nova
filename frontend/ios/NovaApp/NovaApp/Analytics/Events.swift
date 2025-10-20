import Foundation

/// All 16+ analytics event types for ClickHouse
enum AnalyticsEvent {
    // App Lifecycle
    case appOpen
    case appBackground
    case appForeground

    // Auth Events
    case onboardingView
    case signInView
    case signUpView
    case signIn(method: String) // "email" | "apple"
    case signUp(method: String)
    case signOut

    // Feed Events
    case feedView
    case postImpression(postId: String)
    case postTap(postId: String)
    case postLike(postId: String)
    case postUnlike(postId: String)

    // Comment Events
    case commentView(postId: String)
    case commentCreate(postId: String)

    // Upload Events
    case uploadStart(fileSize: Int)
    case uploadSuccess(postId: String, duration: TimeInterval)
    case uploadFail(error: String)

    // Search Events
    case searchSubmit(query: String)
    case searchResultClick(userId: String, query: String)

    // Profile Events
    case profileView(userId: String)
    case profileUpdate

    // Notification Events
    case notificationOpen(notificationId: String)

    // Account Events
    case accountDelete

    // Custom Events
    case custom(name: String, parameters: [String: Any])

    // MARK: - Event Properties
    var name: String {
        switch self {
        case .appOpen: return "app_open"
        case .appBackground: return "app_background"
        case .appForeground: return "app_foreground"
        case .onboardingView: return "onboarding_view"
        case .signInView: return "sign_in_view"
        case .signUpView: return "sign_up_view"
        case .signIn: return "sign_in"
        case .signUp: return "sign_up"
        case .signOut: return "sign_out"
        case .feedView: return "feed_view"
        case .postImpression: return "post_impression"
        case .postTap: return "post_tap"
        case .postLike: return "post_like"
        case .postUnlike: return "post_unlike"
        case .commentView: return "comment_view"
        case .commentCreate: return "comment_create"
        case .uploadStart: return "upload_start"
        case .uploadSuccess: return "upload_success"
        case .uploadFail: return "upload_fail"
        case .searchSubmit: return "search_submit"
        case .searchResultClick: return "search_result_click"
        case .profileView: return "profile_view"
        case .profileUpdate: return "profile_update"
        case .notificationOpen: return "notification_open"
        case .accountDelete: return "account_delete"
        case .custom(let name, _): return name
        }
    }

    var parameters: [String: Any] {
        var params: [String: Any] = [:]

        switch self {
        case .signIn(let method), .signUp(let method):
            params["method"] = method

        case .postImpression(let postId), .postTap(let postId),
             .postLike(let postId), .postUnlike(let postId):
            params["post_id"] = postId

        case .commentView(let postId), .commentCreate(let postId):
            params["post_id"] = postId

        case .uploadStart(let fileSize):
            params["file_size"] = fileSize

        case .uploadSuccess(let postId, let duration):
            params["post_id"] = postId
            params["duration_ms"] = Int(duration * 1000)

        case .uploadFail(let error):
            params["error"] = error

        case .searchSubmit(let query):
            params["query"] = query

        case .searchResultClick(let userId, let query):
            params["user_id"] = userId
            params["query"] = query

        case .profileView(let userId):
            params["user_id"] = userId

        case .notificationOpen(let notificationId):
            params["notification_id"] = notificationId

        case .custom(_, let customParams):
            params = customParams

        default:
            break
        }

        return params
    }

    var category: String {
        switch self {
        case .appOpen, .appBackground, .appForeground:
            return "lifecycle"
        case .onboardingView, .signInView, .signUpView, .signIn, .signUp, .signOut:
            return "auth"
        case .feedView, .postImpression, .postTap, .postLike, .postUnlike:
            return "feed"
        case .commentView, .commentCreate:
            return "comment"
        case .uploadStart, .uploadSuccess, .uploadFail:
            return "upload"
        case .searchSubmit, .searchResultClick:
            return "search"
        case .profileView, .profileUpdate:
            return "profile"
        case .notificationOpen:
            return "notification"
        case .accountDelete:
            return "account"
        case .custom:
            return "custom"
        }
    }
}
