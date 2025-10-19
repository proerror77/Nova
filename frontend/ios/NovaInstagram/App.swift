import SwiftUI

@main
struct NovaInstagramApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(nil)
        }
    }
}

// MARK: - Design System Colors
struct DesignColors {
    static let brandPrimary = Color(red: 0.2, green: 0.5, blue: 0.95)
    static let brandAccent = Color(red: 1.0, green: 0.3, blue: 0.4)
    static let surfaceLight = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let surfaceElevated = Color.white
    static let textPrimary = Color.black
    static let textSecondary = Color.gray
    static let borderLight = Color(red: 0.9, green: 0.9, blue: 0.92)
}

struct MainTabView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                // Home Feed
                FeedTabView()
                    .tag(0)
                    .tabItem {
                        Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                        Text("主頁")
                    }
                
                // Search
                SearchTabView()
                    .tag(1)
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                        Text("搜索")
                    }
                
                // Create
                CreateTabView()
                    .tag(2)
                    .tabItem {
                        Image(systemName: "plus.square")
                        Text("發佈")
                    }
                
                // Notifications
                NotificationsTabView()
                    .tag(3)
                    .tabItem {
                        Image(systemName: selectedTab == 3 ? "heart.fill" : "heart")
                        Text("讚")
                    }
                
                // Profile
                ProfileTabView()
                    .tag(4)
                    .tabItem {
                        Image(systemName: "person.crop.circle")
                        Text("檔案")
                    }
            }
            .accentColor(DesignColors.brandPrimary)
        }
        .background(DesignColors.surfaceLight)
    }
}

// MARK: - Feed View
struct FeedTabView: View {
    @State private var posts: [PostModel] = [
        PostModel(id: "1", author: "Emma Chen", avatar: "🎨", caption: "新作品上線！設計系統 v2.0 完成 🚀", likes: 2341, comments: 128, imageEmoji: "🎨"),
        PostModel(id: "2", author: "Alex Liu", avatar: "📱", caption: "iOS 開發技巧分享：SwiftUI 的最佳實踐", likes: 1542, comments: 87, imageEmoji: "📱"),
        PostModel(id: "3", author: "Sarah Wong", avatar: "🌅", caption: "週末旅行，美景無邊 🏔️", likes: 3205, comments: 245, imageEmoji: "🌅"),
        PostModel(id: "4", author: "Mike Chen", avatar: "☕️", caption: "咖啡館工作日常", likes: 1876, comments: 156, imageEmoji: "☕️"),
        PostModel(id: "5", author: "Lisa Park", avatar: "🎬", caption: "新 MV 幕後花絮發佈", likes: 5421, comments: 512, imageEmoji: "🎬"),
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Text("Nova")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(DesignColors.textPrimary)
                    Spacer()
                    HStack(spacing: 16) {
                        Image(systemName: "heart")
                        Image(systemName: "paperplane")
                    }
                    .font(.system(size: 20))
                    .foregroundColor(DesignColors.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                    .background(DesignColors.borderLight)
                
                // Posts Feed
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(posts) { post in
                            PostCardView(post: post)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .background(DesignColors.surfaceLight)
            .navigationTitle("")
            .navigationBarHidden(true)
        }
    }
}

// MARK: - Post Model
struct PostModel: Identifiable {
    let id: String
    let author: String
    let avatar: String
    let caption: String
    let likes: Int
    let comments: Int
    let imageEmoji: String
}

// MARK: - Post Card Component
struct PostCardView: View {
    let post: PostModel
    @State private var isLiked = false
    @State private var isSaved = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text(post.avatar)
                    .font(.system(size: 40))
                    .frame(width: 44, height: 44)
                    .background(DesignColors.brandPrimary.opacity(0.1))
                    .cornerRadius(22)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignColors.textPrimary)
                    Text("2小時前")
                        .font(.system(size: 12))
                        .foregroundColor(DesignColors.textSecondary)
                }
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundColor(DesignColors.textSecondary)
            }
            .padding(12)
            
            Divider()
                .background(DesignColors.borderLight)
            
            // Image
            Text(post.imageEmoji)
                .font(.system(size: 80))
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .background(LinearGradient(
                    gradient: Gradient(colors: [
                        DesignColors.brandPrimary.opacity(0.1),
                        DesignColors.brandAccent.opacity(0.1)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            // Actions
            HStack(spacing: 12) {
                Button(action: { isLiked.toggle() }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .foregroundColor(isLiked ? DesignColors.brandAccent : DesignColors.textPrimary)
                }
                
                Button(action: {}) {
                    Image(systemName: "bubble.right")
                        .foregroundColor(DesignColors.textPrimary)
                }
                
                Button(action: {}) {
                    Image(systemName: "paperplane")
                        .foregroundColor(DesignColors.textPrimary)
                }
                
                Spacer()
                
                Button(action: { isSaved.toggle() }) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .foregroundColor(isSaved ? DesignColors.brandPrimary : DesignColors.textPrimary)
                }
            }
            .font(.system(size: 18))
            .padding(12)
            
            Divider()
                .background(DesignColors.borderLight)
            
            // Stats & Caption
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Text("\(post.likes) 讚")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(post.comments) 評論")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(DesignColors.textSecondary)
                
                Text(post.caption)
                    .font(.system(size: 13))
                    .foregroundColor(DesignColors.textPrimary)
                    .lineLimit(3)
            }
            .padding(12)
        }
        .background(DesignColors.surfaceElevated)
        .cornerRadius(8)
        .padding(.horizontal, 8)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 1)
    }
}

// MARK: - Search Tab
struct SearchTabView: View {
    @State private var searchText = ""
    let suggestions = ["設計", "iOS", "SwiftUI", "旅行", "攝影", "咖啡", "技術", "藝術"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignColors.textSecondary)
                    TextField("搜索用戶、主題、標籤...", text: $searchText)
                        .font(.system(size: 14))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(DesignColors.textSecondary)
                        }
                    }
                }
                .padding(10)
                .background(DesignColors.surfaceLight)
                .cornerRadius(20)
                .padding(12)
                
                if searchText.isEmpty {
                    // Suggestions
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("熱搜話題")
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.horizontal, 12)
                            
                            VStack(spacing: 0) {
                                ForEach(suggestions, id: \.self) { suggestion in
                                    HStack(spacing: 12) {
                                        Image(systemName: "magnifyingglass")
                                            .foregroundColor(DesignColors.textSecondary)
                                        Text("#\(suggestion)")
                                            .foregroundColor(DesignColors.textPrimary)
                                        Spacer()
                                        Text("→")
                                            .foregroundColor(DesignColors.textSecondary)
                                    }
                                    .padding(12)
                                    .background(DesignColors.surfaceElevated)
                                    Divider().padding(0)
                                }
                            }
                            .cornerRadius(8)
                            .clipped()
                            .padding(.horizontal, 12)
                        }
                    }
                } else {
                    // Search Results
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(0..<8, id: \.self) { index in
                                HStack(spacing: 12) {
                                    Text("\(["👤", "📸", "🎨", "📱", "🌅", "☕️", "🎬", "📚"][index])")
                                        .font(.system(size: 32))
                                        .frame(width: 60, height: 60)
                                        .background(DesignColors.surfaceLight)
                                        .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("搜索結果 #\(index + 1)")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(DesignColors.textPrimary)
                                        Text("1,234 個匹配結果")
                                            .font(.system(size: 12))
                                            .foregroundColor(DesignColors.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(12)
                            }
                        }
                    }
                }
            }
            .background(DesignColors.surfaceLight)
        }
    }
}

// MARK: - Create Tab
struct CreateTabView: View {
    @State private var showImagePicker = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 80))
                    .foregroundColor(DesignColors.brandPrimary)
                
                VStack(spacing: 8) {
                    Text("建立新貼文")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(DesignColors.textPrimary)
                    Text("分享您的精彩時刻")
                        .font(.system(size: 14))
                        .foregroundColor(DesignColors.textSecondary)
                }
                
                VStack(spacing: 12) {
                    Button(action: { showImagePicker = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.fill")
                            Text("從相冊選擇")
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(DesignColors.brandPrimary)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                        .cornerRadius(12)
                    }
                    
                    Button(action: {}) {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                            Text("拍攝新照片")
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(DesignColors.brandAccent)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                        .cornerRadius(12)
                    }
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .padding(24)
            .background(DesignColors.surfaceLight)
        }
    }
}

// MARK: - Notifications Tab
struct NotificationsTabView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("通知")
                        .font(.system(size: 28, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                    .background(DesignColors.borderLight)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(0..<10, id: \.self) { index in
                            HStack(spacing: 12) {
                                Text(["❤️", "💬", "👥", "📌", "✨"][index % 5])
                                    .font(.system(size: 28))
                                    .frame(width: 44, height: 44)
                                    .background(DesignColors.surfaceLight)
                                    .cornerRadius(22)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("用戶\(index + 1)讚了您的貼文")
                                        .font(.system(size: 13))
                                        .foregroundColor(DesignColors.textPrimary)
                                    Text("\(index + 1)小時前")
                                        .font(.system(size: 12))
                                        .foregroundColor(DesignColors.textSecondary)
                                }
                                
                                Spacer()
                                
                                Text("📸")
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .background(DesignColors.surfaceLight)
                                    .cornerRadius(8)
                            }
                            .padding(12)
                            Divider()
                                .background(DesignColors.borderLight)
                        }
                    }
                }
            }
            .background(DesignColors.surfaceLight)
        }
    }
}

// MARK: - Profile Tab
struct ProfileTabView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Profile Header
                        VStack(spacing: 12) {
                            Text("👤")
                                .font(.system(size: 80))
                                .frame(width: 120, height: 120)
                                .background(LinearGradient(
                                    gradient: Gradient(colors: [
                                        DesignColors.brandPrimary.opacity(0.2),
                                        DesignColors.brandAccent.opacity(0.2)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .cornerRadius(60)
                            
                            Text("John Doe")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(DesignColors.textPrimary)
                            
                            Text("@johndoe • iOS 開發者 • 設計愛好者")
                                .font(.system(size: 13))
                                .foregroundColor(DesignColors.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            Text("🌍 台灣 • ☕️ 咖啡愛好者 • 📸 攝影師")
                                .font(.system(size: 13))
                                .foregroundColor(DesignColors.textPrimary)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Stats
                        HStack(spacing: 0) {
                            VStack(spacing: 8) {
                                Text("1,245")
                                    .font(.system(size: 18, weight: .bold))
                                Text("貼文")
                                    .font(.system(size: 12))
                            }
                            .frame(maxWidth: .infinity)
                            
                            Divider()
                                .frame(height: 40)
                            
                            VStack(spacing: 8) {
                                Text("54.3K")
                                    .font(.system(size: 18, weight: .bold))
                                Text("粉絲")
                                    .font(.system(size: 12))
                            }
                            .frame(maxWidth: .infinity)
                            
                            Divider()
                                .frame(height: 40)
                            
                            VStack(spacing: 8) {
                                Text("2,134")
                                    .font(.system(size: 18, weight: .bold))
                                Text("追蹤中")
                                    .font(.system(size: 12))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .foregroundColor(DesignColors.textPrimary)
                        .padding(.vertical, 16)
                        .background(DesignColors.surfaceElevated)
                        .cornerRadius(12)
                        
                        // Buttons
                        HStack(spacing: 12) {
                            Button(action: {}) {
                                Text("編輯檔案")
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(DesignColors.brandPrimary)
                                    .foregroundColor(.white)
                                    .font(.system(size: 14, weight: .semibold))
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {}) {
                                Text("分享")
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .background(DesignColors.surfaceElevated)
                                    .foregroundColor(DesignColors.textPrimary)
                                    .font(.system(size: 14, weight: .semibold))
                                    .border(DesignColors.borderLight, width: 1)
                                    .cornerRadius(8)
                            }
                        }
                        
                        // Posts Grid
                        VStack(alignment: .leading, spacing: 12) {
                            Text("貼文")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(DesignColors.textPrimary)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                                ForEach(0..<9, id: \.self) { index in
                                    Text(["🎨", "📸", "🌅", "☕️", "🎬", "📱", "🏔️", "🎭", "🌸"][index])
                                        .font(.system(size: 40))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 100)
                                        .background(LinearGradient(
                                            gradient: Gradient(colors: [
                                                DesignColors.brandPrimary.opacity(0.1),
                                                DesignColors.brandAccent.opacity(0.1)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .background(DesignColors.surfaceLight)
        }
    }
}

#if DEBUG
struct NovaInstagramApp_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
#endif
