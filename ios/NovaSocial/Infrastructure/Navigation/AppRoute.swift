import SwiftUI

/// Type-safe navigation route with associated data for deep linking
enum AppRoute: Hashable, Codable {
    // MARK: - Authentication Routes
    case splash
    case inviteCode
    case login
    case phoneLogin
    case phoneRegistration
    case forgotPassword
    case emailSentConfirmation(email: String)
    case resetPassword(token: String)
    case createAccount

    // MARK: - Main Tab Routes
    case home
    case message
    case alice
    case account

    // MARK: - Content Routes
    case post(id: String)
    case profile(userId: String)
    case chat(roomId: String)
    case channel(id: String)
    case comment(postId: String)

    // MARK: - Settings Routes
    case settings
    case profileSetting
    case devices
    case passkeys
    case getVerified
    case chatBackup
    case callRecordings

    // MARK: - Discovery Routes
    case search(query: String?)
    case rankingList
    case notification

    // MARK: - Social Routes
    case inviteFriends
    case addFriends
    case friendRequests
    case myChannels
    case newChat
    case groupChat
    case newPost
    case write

    // MARK: - Codable Support

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case email
        case token
        case userId
        case roomId
        case postId
        case query
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "splash": self = .splash
        case "inviteCode": self = .inviteCode
        case "login": self = .login
        case "phoneLogin": self = .phoneLogin
        case "phoneRegistration": self = .phoneRegistration
        case "forgotPassword": self = .forgotPassword
        case "emailSentConfirmation":
            let email = try container.decode(String.self, forKey: .email)
            self = .emailSentConfirmation(email: email)
        case "resetPassword":
            let token = try container.decode(String.self, forKey: .token)
            self = .resetPassword(token: token)
        case "createAccount": self = .createAccount
        case "home": self = .home
        case "message": self = .message
        case "alice": self = .alice
        case "account": self = .account
        case "post":
            let id = try container.decode(String.self, forKey: .id)
            self = .post(id: id)
        case "profile":
            let userId = try container.decode(String.self, forKey: .userId)
            self = .profile(userId: userId)
        case "chat":
            let roomId = try container.decode(String.self, forKey: .roomId)
            self = .chat(roomId: roomId)
        case "channel":
            let id = try container.decode(String.self, forKey: .id)
            self = .channel(id: id)
        case "comment":
            let postId = try container.decode(String.self, forKey: .postId)
            self = .comment(postId: postId)
        case "settings": self = .settings
        case "profileSetting": self = .profileSetting
        case "devices": self = .devices
        case "passkeys": self = .passkeys
        case "getVerified": self = .getVerified
        case "search":
            let query = try container.decodeIfPresent(String.self, forKey: .query)
            self = .search(query: query)
        case "rankingList": self = .rankingList
        case "notification": self = .notification
        case "inviteFriends": self = .inviteFriends
        case "addFriends": self = .addFriends
        case "friendRequests": self = .friendRequests
        case "myChannels": self = .myChannels
        case "newChat": self = .newChat
        case "groupChat": self = .groupChat
        case "newPost": self = .newPost
        case "write": self = .write
        default: self = .home
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .splash: try container.encode("splash", forKey: .type)
        case .inviteCode: try container.encode("inviteCode", forKey: .type)
        case .login: try container.encode("login", forKey: .type)
        case .phoneLogin: try container.encode("phoneLogin", forKey: .type)
        case .phoneRegistration: try container.encode("phoneRegistration", forKey: .type)
        case .forgotPassword: try container.encode("forgotPassword", forKey: .type)
        case .emailSentConfirmation(let email):
            try container.encode("emailSentConfirmation", forKey: .type)
            try container.encode(email, forKey: .email)
        case .resetPassword(let token):
            try container.encode("resetPassword", forKey: .type)
            try container.encode(token, forKey: .token)
        case .createAccount: try container.encode("createAccount", forKey: .type)
        case .home: try container.encode("home", forKey: .type)
        case .message: try container.encode("message", forKey: .type)
        case .alice: try container.encode("alice", forKey: .type)
        case .account: try container.encode("account", forKey: .type)
        case .post(let id):
            try container.encode("post", forKey: .type)
            try container.encode(id, forKey: .id)
        case .profile(let userId):
            try container.encode("profile", forKey: .type)
            try container.encode(userId, forKey: .userId)
        case .chat(let roomId):
            try container.encode("chat", forKey: .type)
            try container.encode(roomId, forKey: .roomId)
        case .channel(let id):
            try container.encode("channel", forKey: .type)
            try container.encode(id, forKey: .id)
        case .comment(let postId):
            try container.encode("comment", forKey: .type)
            try container.encode(postId, forKey: .postId)
        case .settings: try container.encode("settings", forKey: .type)
        case .profileSetting: try container.encode("profileSetting", forKey: .type)
        case .devices: try container.encode("devices", forKey: .type)
        case .passkeys: try container.encode("passkeys", forKey: .type)
        case .getVerified: try container.encode("getVerified", forKey: .type)
        case .search(let query):
            try container.encode("search", forKey: .type)
            try container.encodeIfPresent(query, forKey: .query)
        case .rankingList: try container.encode("rankingList", forKey: .type)
        case .notification: try container.encode("notification", forKey: .type)
        case .inviteFriends: try container.encode("inviteFriends", forKey: .type)
        case .addFriends: try container.encode("addFriends", forKey: .type)
        case .friendRequests: try container.encode("friendRequests", forKey: .type)
        case .myChannels: try container.encode("myChannels", forKey: .type)
        case .newChat: try container.encode("newChat", forKey: .type)
        case .groupChat: try container.encode("groupChat", forKey: .type)
        case .newPost: try container.encode("newPost", forKey: .type)
        case .write: try container.encode("write", forKey: .type)
        case .chatBackup: try container.encode("chatBackup", forKey: .type)
        case .callRecordings: try container.encode("callRecordings", forKey: .type)
        }
    }
}

// MARK: - AppRoute to AppPage Conversion

extension AppRoute {
    /// Convert to legacy AppPage for backward compatibility
    var toAppPage: AppPage {
        switch self {
        case .splash: return .splash
        case .inviteCode: return .inviteCode
        case .login: return .login
        case .phoneLogin: return .phoneLogin
        case .phoneRegistration: return .phoneRegistration
        case .forgotPassword: return .forgotPassword
        case .emailSentConfirmation(let email): return .emailSentConfirmation(email: email)
        case .resetPassword(let token): return .resetPassword(token: token)
        case .createAccount: return .createAccount
        case .home: return .home
        case .message: return .message
        case .alice: return .alice
        case .account: return .account
        case .post: return .home // Post detail handled by HomeView internally
        case .profile: return .account
        case .chat: return .message
        case .channel: return .home
        case .comment: return .home
        case .settings: return .setting
        case .profileSetting: return .profileSetting
        case .devices: return .devices
        case .passkeys: return .passkeys
        case .getVerified: return .getVerified
        case .search: return .home
        case .rankingList: return .rankingList
        case .notification: return .home
        case .inviteFriends: return .inviteFriends
        case .addFriends: return .addFriends
        case .friendRequests: return .friendRequests
        case .myChannels: return .myChannels
        case .newChat: return .newChat
        case .groupChat: return .groupChat
        case .newPost: return .home
        case .write: return .write
        case .chatBackup: return .chatBackup
        case .callRecordings: return .callRecordings
        }
    }
}

// MARK: - Tab Identification

extension AppRoute {
    /// The main tab this route belongs to
    var mainTab: MainTab? {
        switch self {
        case .home, .search, .rankingList, .notification, .post, .channel, .comment, .newPost, .write:
            return .home
        case .message, .chat, .newChat, .groupChat:
            return .message
        case .alice:
            return .alice
        case .account, .profile, .settings, .profileSetting, .devices, .passkeys, .getVerified, .inviteFriends, .addFriends, .myChannels, .chatBackup, .callRecordings:
            return .account
        default:
            return nil
        }
    }
}

/// Main tab bar tabs
enum MainTab: String, CaseIterable, Codable {
    case home
    case message
    case alice
    case account

    var route: AppRoute {
        switch self {
        case .home: return .home
        case .message: return .message
        case .alice: return .alice
        case .account: return .account
        }
    }
}
