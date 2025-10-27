import SwiftUI

/// 主应用容器 - 基于 Figma 设计的完整应用
struct MainTabView: View {
    @State private var selectedTab = IceredTabBar.Tab.home

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 内容区域
                Group {
                    switch selectedTab {
                    case .home:
                        HomeView()
                    case .message:
                        MessageView()
                    case .create:
                        CreateView()
                    case .alice:
                        AliceView()
                    case .account:
                        AccountView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // 底部标签栏
                IceredTabBar(selectedTab: $selectedTab)
            }

            VStack {
                // 如果需要添加全局 overlay，可以在这里添加
            }
        }
        .background(DesignSystem.Colors.background)
    }
}

#Preview {
    MainTabView()
}
