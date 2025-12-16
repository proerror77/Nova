import SwiftUI

/// 应用页面枚举
enum AppPage: Equatable {
    case splash
    case welcome
    case login
    case forgotPassword
    case resetPassword(token: String)
    case createAccount
    case phoneRegistration
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
    case newChat
    case write
    case getVerified
    case groupChat
}
