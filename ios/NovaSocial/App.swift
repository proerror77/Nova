import SwiftUI

@main
struct FigmaDesignAppApp: App {
    @State private var currentPage: AppPage = .splash

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 根据状态即时切换页面（无过渡动画）
                switch currentPage {
                case .splash:
                    SplashScreenView(currentPage: $currentPage)
                        .transition(.identity)
                case .login:
                    LoginView(currentPage: $currentPage)
                        .transition(.identity)
                case .home:
                    HomeView(currentPage: $currentPage)
                        .transition(.identity)
                case .message:
                    MessageView(currentPage: $currentPage)
                        .transition(.identity)
                case .account:
                    ProfileView(currentPage: $currentPage)
                        .transition(.identity)
                case .alice:
                    AliceView(currentPage: $currentPage)
                        .transition(.identity)
                case .setting:
                    SettingsView(currentPage: $currentPage)
                        .transition(.identity)
                case .profileSetting:
                    ProfileSettingView(currentPage: $currentPage)
                        .transition(.identity)
                case .accounts:
                    AccountsView(currentPage: $currentPage)
                        .transition(.identity)
                case .devices:
                    DevicesView(currentPage: $currentPage)
                        .transition(.identity)
                case .inviteFriends:
                    InviteFriendsView(currentPage: $currentPage)
                        .transition(.identity)
                case .myChannels:
                    MyChannelsView(currentPage: $currentPage)
                        .transition(.identity)
                case .addFriends:
                    AddFriendsView(currentPage: $currentPage)
                        .transition(.identity)
                case .startGroupChat:
                    StartGroupChatView(currentPage: $currentPage)
                        .transition(.identity)
                default:
                    HomeView(currentPage: $currentPage)
                        .transition(.identity)
                }
            }
            .animation(.none, value: currentPage)
        }
    }
}
