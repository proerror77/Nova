import SwiftUI

/// Figma 设计的底部标签栏 - 5 个标签
struct IceredTabBar: View {
    @Binding var selectedTab: Tab

    enum Tab: Int, CaseIterable {
        case home = 0
        case message = 1
        case create = 2
        case alice = 3
        case account = 4

        var label: String {
            switch self {
            case .home: return "Home"
            case .message: return "Message"
            case .create: return "Create"
            case .alice: return "Alice"
            case .account: return "Account"
            }
        }

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .message: return "message.fill"
            case .create: return "plus.circle.fill"
            case .alice: return "sparkles"
            case .account: return "person.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .foregroundColor(DesignSystem.Colors.divider)

            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.rawValue) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 24))
                                .foregroundColor(
                                    selectedTab == tab
                                        ? DesignSystem.Colors.primary
                                        : DesignSystem.Colors.textMedium
                                )

                            Text(tab.label)
                                .font(DesignSystem.Typography.label)
                                .foregroundColor(
                                    selectedTab == tab
                                        ? DesignSystem.Colors.primary
                                        : DesignSystem.Colors.textMedium
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                    }
                }
            }
            .background(DesignSystem.Colors.card)
        }
    }
}

#Preview {
    @State var selectedTab = IceredTabBar.Tab.home
    return ZStack {
        VStack {
            Spacer()
        }
        .background(DesignSystem.Colors.background)

        VStack {
            Spacer()
            IceredTabBar(selectedTab: $selectedTab)
        }
    }
}
