import SwiftUI

// MARK: - Design System from Figma

enum FigmaDesignSystem {
    enum Colors {
        static let primary = Color(red: 0.82, green: 0.11, blue: 0.26)           // #D11C42
        static let background = Color(red: 0.969, green: 0.961, blue: 0.965)    // #F7F6F6
        static let card = Color(red: 1.0, green: 1.0, blue: 1.0)                // White
        static let textDark = Color(red: 0.247, green: 0.247, blue: 0.247)      // #3F3F3F
        static let textMedium = Color(red: 0.529, green: 0.529, blue: 0.537)    // #878889
        static let divider = Color(red: 0.9, green: 0.9, blue: 0.9)
    }

    enum Typography {
        static let title1 = Font.system(size: 22, weight: .bold, design: .default)
        static let title2 = Font.system(size: 18, weight: .bold, design: .default)
        static let subtitle = Font.system(size: 16, weight: .medium, design: .default)
        static let body = Font.system(size: 14, weight: .regular, design: .default)
        static let label = Font.system(size: 9, weight: .regular, design: .default)
    }
}

// MARK: - Main Content View

public struct ContentView: View {
    @State private var selectedTab = Tab.home

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .home:
                        FigmaHomeView()
                    case .message:
                        FigmaMessageView()
                    case .create:
                        FigmaCreateView()
                    case .alice:
                        FigmaAliceView()
                    case .account:
                        FigmaAccountView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                FigmaTabBar(selectedTab: $selectedTab)
            }
        }
        .background(FigmaDesignSystem.Colors.background)
    }

    public init() {}
}

// MARK: - Tab Enum

enum Tab: Int {
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
        case .home: return "triangle.fill"
        case .message: return "message.fill"
        case .create: return "plus.circle.fill"
        case .alice: return "arrow.2.circlepath"
        case .account: return "person.circle.fill"
        }
    }
}

// MARK: - Figma Tab Bar

private struct FigmaTabBar: View {
    @Binding var selectedTab: Tab

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .foregroundColor(FigmaDesignSystem.Colors.divider)

            HStack(spacing: 0) {
                ForEach([Tab.home, .message, .create, .alice, .account], id: \.rawValue) { tab in
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
                                        ? FigmaDesignSystem.Colors.primary
                                        : FigmaDesignSystem.Colors.textMedium
                                )

                            Text(tab.label)
                                .font(FigmaDesignSystem.Typography.label)
                                .foregroundColor(
                                    selectedTab == tab
                                        ? FigmaDesignSystem.Colors.primary
                                        : FigmaDesignSystem.Colors.textMedium
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                    }
                }
            }
            .background(FigmaDesignSystem.Colors.card)
        }
    }
}

// MARK: - Home View (Figma Design)

private struct FigmaHomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 推荐卡片
                    RecommendationCardView(
                        title: "kyleegigstead",
                        subtitle: "Cyborg dreams",
                        commentCount: 93
                    )

                    // 投票卡片
                    PollCardView(
                        title: "Hottest Banker in H.K.",
                        subtitle: "Corporate Poll"
                    )

                    Spacer()
                        .frame(height: 16)
                }
                .padding(16)
            }
            .background(FigmaDesignSystem.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        // Search action
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(FigmaDesignSystem.Colors.textDark)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("ICERED")
                        .font(FigmaDesignSystem.Typography.subtitle)
                        .fontWeight(.bold)
                        .foregroundColor(FigmaDesignSystem.Colors.primary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // Notification action
                    } label: {
                        Image(systemName: "bell.fill")
                            .foregroundColor(FigmaDesignSystem.Colors.textDark)
                    }
                }
            }
        }
    }
}

// MARK: - Recommendation Card

private struct RecommendationCardView: View {
    let title: String
    let subtitle: String
    let commentCount: Int

    var body: some View {
        VStack(spacing: 0) {
            // Image placeholder
            RoundedRectangle(cornerRadius: 15)
                .fill(FigmaDesignSystem.Colors.background)
                .frame(height: 200)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(FigmaDesignSystem.Typography.body)
                            .fontWeight(.semibold)
                            .foregroundColor(FigmaDesignSystem.Colors.textDark)

                        Text(subtitle)
                            .font(FigmaDesignSystem.Typography.label)
                            .foregroundColor(FigmaDesignSystem.Colors.textMedium)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right.fill")
                            .font(.system(size: 12))
                        Text("\(commentCount)")
                            .font(FigmaDesignSystem.Typography.label)
                    }
                    .foregroundColor(FigmaDesignSystem.Colors.textMedium)
                }

                Divider()
                    .foregroundColor(FigmaDesignSystem.Colors.divider)
            }
            .padding(16)
        }
        .background(FigmaDesignSystem.Colors.card)
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Poll Card

private struct PollCardView: View {
    let title: String
    let subtitle: String

    let candidates = [
        ("Lucy Liu", "Morgan Stanley", 2293),
        ("Jane Smith", "Goldman Sachs", 1856),
        ("Emily Chen", "JPMorgan", 1624),
        ("Sarah Johnson", "Bank of America", 1432),
        ("Lisa Wong", "HSBC", 1289),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(title)
                    .font(FigmaDesignSystem.Typography.title2)
                    .fontWeight(.bold)
                    .foregroundColor(FigmaDesignSystem.Colors.textDark)

                Text(subtitle)
                    .font(FigmaDesignSystem.Typography.subtitle)
                    .foregroundColor(FigmaDesignSystem.Colors.textMedium)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)

            VStack(spacing: 16) {
                ForEach(candidates.indices, id: \.self) { index in
                    candidateRow(index: index, name: candidates[index].0, org: candidates[index].1, votes: candidates[index].2)
                }
            }
            .padding(16)

            HStack(spacing: 6) {
                ForEach(0 ..< 5, id: \.self) { index in
                    Circle()
                        .fill(
                            index == 0
                                ? FigmaDesignSystem.Colors.primary
                                : FigmaDesignSystem.Colors.divider
                        )
                        .frame(width: 4, height: 4)
                }
                Spacer()
                Text("view more")
                    .font(FigmaDesignSystem.Typography.label)
                    .foregroundColor(FigmaDesignSystem.Colors.primary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(FigmaDesignSystem.Colors.card)
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private func candidateRow(index: Int, name: String, org: String, votes: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(FigmaDesignSystem.Typography.subtitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 35, height: 35)
                .background(FigmaDesignSystem.Colors.primary)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(FigmaDesignSystem.Typography.title2)
                    .fontWeight(.bold)
                    .foregroundColor(FigmaDesignSystem.Colors.textDark)

                Text(org)
                    .font(FigmaDesignSystem.Typography.body)
                    .foregroundColor(FigmaDesignSystem.Colors.textMedium)
            }

            Spacer()

            Text("\(votes)")
                .font(FigmaDesignSystem.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(FigmaDesignSystem.Colors.textMedium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Other Views

private struct FigmaMessageView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Messages")
                    .font(FigmaDesignSystem.Typography.title1)
                    .foregroundColor(FigmaDesignSystem.Colors.textDark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FigmaDesignSystem.Colors.background)
            .navigationTitle("Message")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FigmaCreateView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Create")
                    .font(FigmaDesignSystem.Typography.title1)
                    .foregroundColor(FigmaDesignSystem.Colors.textDark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FigmaDesignSystem.Colors.background)
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FigmaAliceView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Alice")
                    .font(FigmaDesignSystem.Typography.title1)
                    .foregroundColor(FigmaDesignSystem.Colors.textDark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FigmaDesignSystem.Colors.background)
            .navigationTitle("Alice")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FigmaAccountView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Account")
                    .font(FigmaDesignSystem.Typography.title1)
                    .foregroundColor(FigmaDesignSystem.Colors.textDark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FigmaDesignSystem.Colors.background)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ContentView()
}
