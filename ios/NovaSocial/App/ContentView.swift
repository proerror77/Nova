import SwiftUI
import NovaSocialFeature

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isAuthenticated {
                MainTabView()
            } else {
                AuthenticationView()
            }
        }
        .animation(.easeInOut, value: appState.isAuthenticated)
    }
}

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content area
            Group {
                switch selectedTab {
                case 0:
                    HomeView() // Figma-designed home page
                case 1:
                    ExploreView()
                case 2:
                    CreatePostView()
                case 3:
                    NotificationView()
                case 4:
                    ProfileView()
                default:
                    HomeView()
                }
            }

            // Custom bottom navigation bar
            CustomTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: Int

    // Brand color from Figma design
    private let accentColor = Color(red: 0.82, green: 0.11, blue: 0.26)
    private let inactiveColor = Color(red: 0.53, green: 0.53, blue: 0.54)

    var body: some View {
        VStack(spacing: 0) {
            // Top border line
            Rectangle()
                .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                // Tab 1: HOTS (Home/Feed)
                TabBarItem(
                    icon: "flame.fill",
                    label: "HOTS",
                    isSelected: selectedTab == 0,
                    accentColor: accentColor,
                    inactiveColor: inactiveColor
                ) {
                    selectedTab = 0
                }

                Spacer()

                // Tab 2: LNFORG (Explore)
                TabBarItem(
                    icon: "person.2.fill",
                    label: "LNFORG",
                    isSelected: selectedTab == 1,
                    accentColor: accentColor,
                    inactiveColor: inactiveColor
                ) {
                    selectedTab = 1
                }

                Spacer()

                // Central Plus Button
                Button {
                    selectedTab = 2
                } label: {
                    ZStack {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 56, height: 56)
                            .shadow(color: accentColor.opacity(0.3), radius: 8, x: 0, y: 4)

                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .offset(y: -16)

                Spacer()

                // Tab 4: FEED (Notifications)
                TabBarItem(
                    icon: "square.grid.2x2.fill",
                    label: "FEED",
                    isSelected: selectedTab == 3,
                    accentColor: accentColor,
                    inactiveColor: inactiveColor
                ) {
                    selectedTab = 3
                }

                Spacer()

                // Tab 5: ACCOUNT (Profile)
                TabBarItem(
                    icon: "person.circle.fill",
                    label: "ACCOUNT",
                    isSelected: selectedTab == 4,
                    accentColor: accentColor,
                    inactiveColor: inactiveColor
                ) {
                    selectedTab = 4
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Color.white)
        }
    }
}

// MARK: - Tab Bar Item
struct TabBarItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let accentColor: Color
    let inactiveColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? accentColor : inactiveColor)

                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? accentColor : inactiveColor)
            }
            .frame(width: 60)
        }
    }
}
