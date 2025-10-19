import Foundation

// MARK: - String Localization Extension
extension String {

    /// Returns the localized version of the string
    var localized: String {
        LocalizationManager.shared.localizedString(for: self)
    }

    /// Returns the localized version with format arguments
    func localized(with arguments: CVarArg...) -> String {
        let format = LocalizationManager.shared.localizedString(for: self)
        return String(format: format, arguments: arguments)
    }

    /// Returns the localized version with a single argument
    func localized(_ argument: CVarArg) -> String {
        let format = LocalizationManager.shared.localizedString(for: self)
        return String(format: format, argument)
    }

    /// Returns the localized version with comment
    func localized(comment: String) -> String {
        LocalizationManager.shared.localizedString(for: self, comment: comment)
    }
}

// MARK: - Localization Keys (Type-safe)
/// Type-safe localization keys to avoid typos
enum L10n {

    // MARK: - Common
    enum Common {
        static let ok = "common.ok"
        static let cancel = "common.cancel"
        static let save = "common.save"
        static let delete = "common.delete"
        static let edit = "common.edit"
        static let done = "common.done"
        static let retry = "common.retry"
        static let loading = "common.loading"
        static let error = "common.error"
        static let success = "common.success"
        static let confirm = "common.confirm"
        static let back = "common.back"
        static let next = "common.next"
        static let skip = "common.skip"
        static let close = "common.close"
        static let yes = "common.yes"
        static let no = "common.no"
        static let send = "common.send"
        static let share = "common.share"
        static let search = "common.search"
    }

    // MARK: - Authentication
    enum Auth {
        static let login = "auth.login"
        static let logout = "auth.logout"
        static let signup = "auth.signup"
        static let email = "auth.email"
        static let password = "auth.password"
        static let confirmPassword = "auth.confirmPassword"
        static let forgotPassword = "auth.forgotPassword"
        static let resetPassword = "auth.resetPassword"
        static let enterEmail = "auth.enterEmail"
        static let enterPassword = "auth.enterPassword"
        static let enterConfirmPassword = "auth.enterConfirmPassword"
        static let username = "auth.username"
        static let enterUsername = "auth.enterUsername"
        static let dontHaveAccount = "auth.dontHaveAccount"
        static let alreadyHaveAccount = "auth.alreadyHaveAccount"
        static let signupNow = "auth.signupNow"
        static let loginNow = "auth.loginNow"
    }

    // MARK: - Errors
    enum Error {
        static let invalidEmail = "error.invalidEmail"
        static let passwordTooShort = "error.passwordTooShort"
        static let passwordsDoNotMatch = "error.passwordsDoNotMatch"
        static let usernameRequired = "error.usernameRequired"
        static let emailRequired = "error.emailRequired"
        static let passwordRequired = "error.passwordRequired"
        static let networkError = "error.networkError"
        static let unknownError = "error.unknownError"
        static let unauthorized = "error.unauthorized"
    }

    // MARK: - Feed
    enum Feed {
        static let title = "feed.title"
        static let loading = "feed.loading"
        static let noPostsYet = "feed.noPostsYet"
        static let startFollowing = "feed.startFollowing"
        static let pullToRefresh = "feed.pullToRefresh"
        static let loadingMore = "feed.loadingMore"
    }

    // MARK: - Post
    enum Post {
        static let create = "post.create"
        static let edit = "post.edit"
        static let delete = "post.delete"
        static let deleteConfirm = "post.deleteConfirm"
        static let caption = "post.caption"
        static let enterCaption = "post.enterCaption"
        static let share = "post.share"
        static let like = "post.like"
        static let unlike = "post.unlike"
        static let comment = "post.comment"
        static let comments = "post.comments"
        static let addComment = "post.addComment"

        static func viewComments(_ count: Int) -> String {
            "post.viewComments".localized(count)
        }

        static func likedBy(_ name: String, others: Int) -> String {
            "post.likedBy".localized(with: name, others)
        }

        static func likedByOne(_ name: String) -> String {
            "post.likedByOne".localized(name)
        }

        static func likedByTwo(_ name1: String, _ name2: String) -> String {
            "post.likedByTwo".localized(with: name1, name2)
        }
    }

    // MARK: - Profile
    enum Profile {
        static let title = "profile.title"
        static let editProfile = "profile.editProfile"
        static let followers = "profile.followers"
        static let following = "profile.following"
        static let posts = "profile.posts"
        static let follow = "profile.follow"
        static let unfollow = "profile.unfollow"
        static let message = "profile.message"
        static let bio = "profile.bio"
        static let website = "profile.website"
        static let noPostsYet = "profile.noPostsYet"
    }

    // MARK: - Notifications
    enum Notification {
        static let title = "notification.title"
        static let noNotifications = "notification.noNotifications"
        static let markAllAsRead = "notification.markAllAsRead"

        static func likedYourPost(_ username: String) -> String {
            "notification.likedYourPost".localized(username)
        }

        static func commentedOnYourPost(_ username: String) -> String {
            "notification.commentedOnYourPost".localized(username)
        }

        static func startedFollowingYou(_ username: String) -> String {
            "notification.startedFollowingYou".localized(username)
        }

        static func mentionedYou(_ username: String) -> String {
            "notification.mentionedYou".localized(username)
        }
    }

    // MARK: - Explore
    enum Explore {
        static let title = "explore.title"
        static let searchPlaceholder = "explore.searchPlaceholder"
        static let trending = "explore.trending"
        static let suggested = "explore.suggested"
        static let noResults = "explore.noResults"
    }

    // MARK: - Settings
    enum Settings {
        static let title = "settings.title"
        static let account = "settings.account"
        static let privacy = "settings.privacy"
        static let notifications = "settings.notifications"
        static let language = "settings.language"
        static let theme = "settings.theme"
        static let about = "settings.about"
        static let termsOfService = "settings.termsOfService"
        static let privacyPolicy = "settings.privacyPolicy"
        static let help = "settings.help"
        static let logout = "settings.logout"
        static let logoutConfirm = "settings.logoutConfirm"
        static let deleteAccount = "settings.deleteAccount"
        static let deleteAccountConfirm = "settings.deleteAccountConfirm"
    }

    // MARK: - Language
    enum Language {
        static let select = "language.select"
        static let current = "language.current"
        static let english = "language.english"
        static let chineseSimplified = "language.chineseSimplified"
        static let chineseTraditional = "language.chineseTraditional"
        static let japanese = "language.japanese"
        static let systemDefault = "language.systemDefault"
    }

    // MARK: - Time
    enum Time {
        static let justNow = "time.justNow"

        static func minuteAgo(_ count: Int) -> String {
            count == 1 ? "time.minuteAgo".localized(count) : "time.minutesAgo".localized(count)
        }

        static func hourAgo(_ count: Int) -> String {
            count == 1 ? "time.hourAgo".localized(count) : "time.hoursAgo".localized(count)
        }

        static func dayAgo(_ count: Int) -> String {
            count == 1 ? "time.dayAgo".localized(count) : "time.daysAgo".localized(count)
        }

        static func weekAgo(_ count: Int) -> String {
            count == 1 ? "time.weekAgo".localized(count) : "time.weeksAgo".localized(count)
        }
    }

    // MARK: - Plurals
    enum Plurals {
        static func follower(_ count: Int) -> String {
            count == 1 ? "plurals.follower".localized(count) : "plurals.followers".localized(count)
        }

        static func post(_ count: Int) -> String {
            count == 1 ? "plurals.post".localized(count) : "plurals.posts".localized(count)
        }

        static func like(_ count: Int) -> String {
            count == 1 ? "plurals.like".localized(count) : "plurals.likes".localized(count)
        }

        static func comment(_ count: Int) -> String {
            count == 1 ? "plurals.comment".localized(count) : "plurals.comments".localized(count)
        }
    }

    // MARK: - Empty States
    enum Empty {
        static let noPosts = "empty.noPosts"
        static let noComments = "empty.noComments"
        static let noFollowers = "empty.noFollowers"
        static let noFollowing = "empty.noFollowing"
        static let noNotifications = "empty.noNotifications"

        static func noSearchResults(_ query: String) -> String {
            "empty.noSearchResults".localized(query)
        }
    }

    // MARK: - Media
    enum Media {
        static let camera = "media.camera"
        static let photoLibrary = "media.photoLibrary"
        static let takePhoto = "media.takePhoto"
        static let choosePhoto = "media.choosePhoto"
        static let removePhoto = "media.removePhoto"
        static let cameraPermissionDenied = "media.cameraPermissionDenied"
        static let photoPermissionDenied = "media.photoPermissionDenied"
    }

    // MARK: - Network
    enum Network {
        static let offline = "network.offline"
        static let reconnecting = "network.reconnecting"
        static let connected = "network.connected"
    }

    // MARK: - Accessibility
    enum Accessibility {
        static let profileImage = "accessibility.profileImage"
        static let postImage = "accessibility.postImage"
        static let likeButton = "accessibility.likeButton"
        static let commentButton = "accessibility.commentButton"
        static let shareButton = "accessibility.shareButton"
        static let backButton = "accessibility.backButton"
        static let closeButton = "accessibility.closeButton"
        static let menuButton = "accessibility.menuButton"
    }
}
