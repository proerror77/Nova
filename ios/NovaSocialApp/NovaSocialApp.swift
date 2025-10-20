import SwiftUI

@main
struct NovaSocialApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(nil)
        }
    }
}

// MARK: - 主内容视图
struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Feed Tab
            FeedPreviewView()
                .tabItem {
                    Label("Feed", systemImage: "house.fill")
                }
                .tag(0)

            // Explore Tab
            ExplorePreviewView()
                .tabItem {
                    Label("Explore", systemImage: "magnifyingglass")
                }
                .tag(1)

            // Profile Tab
            ProfilePreviewView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(2)
        }
    }
}

// MARK: - Feed 预览
struct FeedPreviewView: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<5, id: \.self) { index in
                    FeedPostCell(
                        title: "User \(index + 1)",
                        subtitle: "2 hours ago",
                        description: "这是一条精彩的帖子内容 🎉 This is an amazing post with multiple languages 多言語対応"
                    )
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FeedPostCell: View {
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.blue.opacity(0.5))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundColor(.gray)
            }

            Text(description)
                .font(.body)
                .lineLimit(3)

            HStack(spacing: 16) {
                Label("12", systemImage: "heart")
                    .foregroundColor(.red)
                Label("5", systemImage: "bubble.right")
                    .foregroundColor(.blue)
                Label("Share", systemImage: "square.and.arrow.up")
                    .foregroundColor(.green)

                Spacer()
            }
            .font(.caption)
        }
        .padding()
    }
}

// MARK: - Explore 预览
struct ExplorePreviewView: View {
    var body: some View {
        NavigationStack {
            VStack {
                SearchBar()
                    .padding()

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(0..<12, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.purple.opacity(Double(index) * 0.1 + 0.2))
                                .aspectRatio(1, contentMode: .fill)
                                .overlay(
                                    Text("Post \(index + 1)")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SearchBar: View {
    @State private var text = ""

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search users, posts...", text: $text)
                .textFieldStyle(.roundedBorder)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Profile 预览
struct ProfilePreviewView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // 用户头部
                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.orange.opacity(0.5))
                        .frame(width: 80, height: 80)

                    Text("John Doe")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("@johndoe")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text("Product Designer • iOS 开発者 / Developer")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .padding()

                // 统计信息
                HStack(spacing: 20) {
                    StatItem(number: "1.2K", label: "Posts")
                    StatItem(number: "5.4K", label: "Followers")
                    StatItem(number: "892", label: "Following")
                }
                .padding()

                // 按钮
                HStack(spacing: 12) {
                    Button(action: {}) {
                        Text("Edit Profile")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }

                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal)

                Divider()

                // 帖子网格
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(0..<9, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green.opacity(Double(index) * 0.1 + 0.2))
                                .aspectRatio(1, contentMode: .fill)
                        }
                    }
                    .padding()
                }

                Spacer()
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct StatItem: View {
    let number: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(number)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ContentView()
}
