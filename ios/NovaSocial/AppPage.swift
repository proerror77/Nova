import SwiftUI

/// 应用页面枚举
enum AppPage: Equatable {
    case splash
    case welcome
    case login
    case phoneLogin
    case phoneRegistration
    case forgotPassword
    case emailSentConfirmation(email: String)
    case resetPassword(token: String)
    case createAccount
    case home
    case rankingList
    case search
    case newPost
    case notification
    case message
    case account
    case alice
    case setting
    case profileSetting
    case aliasName
    case devices
    case inviteFriends
    case myChannels
    case addFriends
    case friendRequests
    case newChat
    case write
    case getVerified
    case groupChat
    case passkeys
}
