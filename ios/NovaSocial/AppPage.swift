import SwiftUI

/// 应用页面枚举
enum AppPage: Equatable {
    case splash
    case welcome
    case inviteCode
    case login
    case phoneLogin
    case phoneRegistration
    case phoneEnterCode(phoneNumber: String)
    case gmailEnterCode(email: String)
    case gmailEnterCodeLogin(email: String)  // For login flow
    case forgotPassword
    case emailSentConfirmation(email: String)
    case resetPassword(token: String)
    case createAccount
    case createAccountEmail
    case createAccountPhoneNumber
    case profileSetup
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
    case chatBackup
    case callRecordings
}
