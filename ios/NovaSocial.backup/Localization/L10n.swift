import Foundation
import SwiftUI

/// 本地化字符串访问器 - 类型安全的本地化字符串访问
enum L10n {
    // MARK: - Common
    enum Common {
        static let appName = "app.name".localized
        static let cancel = "common.cancel".localized
        static let confirm = "common.confirm".localized
        static let delete = "common.delete".localized
        static let edit = "common.edit".localized
        static let save = "common.save".localized
        static let send = "common.send".localized
        static let done = "common.done".localized
        static let back = "common.back".localized
        static let next = "common.next".localized
        static let skip = "common.skip".localized
        static let retry = "common.retry".localized
        static let close = "common.close".localized
        static let ok = "common.ok".localized
        static let yes = "common.yes".localized
        static let no = "common.no".localized
        static let loading = "common.loading".localized
        static let error = "common.error".localized
        static let success = "common.success".localized
        static let warning = "common.warning".localized
    }

    // MARK: - Authentication
    enum Auth {
        static let login = "auth.login".localized
        static let register = "auth.register".localized
        static let logout = "auth.logout".localized
        static let email = "auth.email".localized
        static let password = "auth.password".localized
        static let username = "auth.username".localized
        static let forgotPassword = "auth.forgot_password".localized
        static let createAccount = "auth.create_account".localized
        static let alreadyHaveAccount = "auth.already_have_account".localized
        static let dontHaveAccount = "auth.dont_have_account".localized

        static func invalidCredentials() -> String {
            "auth.error.invalid_credentials".localized
        }

        static func passwordTooShort() -> String {
            "auth.error.password_too_short".localized
        }

        static func emailInvalid() -> String {
            "auth.error.email_invalid".localized
        }
    }

    // MARK: - Feed
    enum Feed {
        static let title = "feed.title".localized
        static let newPost = "feed.new_post".localized
        static let refresh = "feed.refresh".localized
        static let noMorePosts = "feed.no_more_posts".localized
        static let loadingMore = "feed.loading_more".localized

        static func postsCount(_ count: Int) -> String {
            String.localizedStringWithFormat("feed.posts_count".localized, count)
        }
    }

    // MARK: - Post
    enum Post {
        static let like = "post.like".localized
        static let unlike = "post.unlike".localized
        static let comment = "post.comment".localized
        static let share = "post.share".localized
        static let delete = "post.delete".localized
        static let edit = "post.edit".localized
        static let report = "post.report".localized
        static let save = "post.save".localized
        static let unsave = "post.unsave".localized

        static func likesCount(_ count: Int) -> String {
            String.localizedStringWithFormat("post.likes_count".localized, count)
        }

        static func commentsCount(_ count: Int) -> String {
            String.localizedStringWithFormat("post.comments_count".localized, count)
        }

        static func sharesCount(_ count: Int) -> String {
            String.localizedStringWithFormat("post.shares_count".localized, count)
        }

        static func timeAgo(minutes: Int) -> String {
            String.localizedStringWithFormat("post.time_ago.minutes".localized, minutes)
        }

        static func timeAgo(hours: Int) -> String {
            String.localizedStringWithFormat("post.time_ago.hours".localized, hours)
        }

        static func timeAgo(days: Int) -> String {
            String.localizedStringWithFormat("post.time_ago.days".localized, days)
        }
    }

    // MARK: - Profile
    enum Profile {
        static let followers = "profile.followers".localized
        static let following = "profile.following".localized
        static let posts = "profile.posts".localized
        static let follow = "profile.follow".localized
        static let unfollow = "profile.unfollow".localized
        static let editProfile = "profile.edit_profile".localized
        static let settings = "profile.settings".localized
        static let bio = "profile.bio".localized

        static func followersCount(_ count: Int) -> String {
            String.localizedStringWithFormat("profile.followers_count".localized, count)
        }

        static func followingCount(_ count: Int) -> String {
            String.localizedStringWithFormat("profile.following_count".localized, count)
        }

        static func postsCount(_ count: Int) -> String {
            String.localizedStringWithFormat("profile.posts_count".localized, count)
        }
    }

    // MARK: - Notification
    enum Notification {
        static let title = "notification.title".localized
        static let markAllRead = "notification.mark_all_read".localized
        static let noNotifications = "notification.no_notifications".localized

        static func likedYourPost(username: String) -> String {
            String.localizedStringWithFormat("notification.liked_your_post".localized, username)
        }

        static func commentedOnYourPost(username: String) -> String {
            String.localizedStringWithFormat("notification.commented_on_your_post".localized, username)
        }

        static func followedYou(username: String) -> String {
            String.localizedStringWithFormat("notification.followed_you".localized, username)
        }
    }

    // MARK: - Search
    enum Search {
        static let title = "search.title".localized
        static let searchPlaceholder = "search.placeholder".localized
        static let noResults = "search.no_results".localized
        static let recent = "search.recent".localized
        static let trending = "search.trending".localized
    }

    // MARK: - Settings
    enum Settings {
        static let title = "settings.title".localized
        static let account = "settings.account".localized
        static let privacy = "settings.privacy".localized
        static let notifications = "settings.notifications".localized
        static let language = "settings.language".localized
        static let theme = "settings.theme".localized
        static let about = "settings.about".localized
        static let version = "settings.version".localized
        static let logout = "settings.logout".localized
    }

    // MARK: - Error Messages
    enum Error {
        static let networkError = "error.network_error".localized
        static let unknownError = "error.unknown_error".localized
        static let serverError = "error.server_error".localized
        static let invalidInput = "error.invalid_input".localized
        static let unauthorized = "error.unauthorized".localized
    }

    // MARK: - Create Post
    enum CreatePost {
        static let title = "create_post.title".localized
        static let caption = "create_post.caption".localized
        static let captionPlaceholder = "create_post.caption_placeholder".localized
        static let selectMedia = "create_post.select_media".localized
        static let publish = "create_post.publish".localized
        static let uploading = "create_post.uploading".localized
    }

    // MARK: - Language Selection
    enum LanguageSelection {
        static let title = "language_selection.title".localized
        static let currentLanguage = "language_selection.current_language".localized
        static let systemLanguage = "language_selection.system_language".localized
    }
}

// MARK: - String Extension for Localization

extension String {
    /// 获取本地化字符串
    var localized: String {
        LocalizationManager.shared.localizedString(forKey: self)
    }

    /// 获取带参数的本地化字符串
    func localized(arguments: CVarArg...) -> String {
        let format = LocalizationManager.shared.localizedString(forKey: self)
        return String(format: format, arguments: arguments)
    }
}

// MARK: - LocalizedStringKey Extension

extension LocalizedStringKey {
    /// 从字符串创建 LocalizedStringKey
    static func key(_ string: String) -> LocalizedStringKey {
        LocalizedStringKey(string)
    }
}
