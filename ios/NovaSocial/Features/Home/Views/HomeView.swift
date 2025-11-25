import SwiftUI
import Foundation

// MARK: - Feed Service

/// Manages feed retrieval using feed-service backend
class FeedService {
    func getFeed(algo: FeedAlgorithm = .chronological, limit: Int = 20, cursor: String? = nil) async throws -> FeedResponse {
        var urlComponents = URLComponents(string: "\(APIConfig.current.baseURL)\(APIConfig.Feed.getFeed)")

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "algo", value: algo.rawValue),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100)))
        ]

        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        urlComponents?.queryItems = queryItems

        guard let url = urlComponents?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use same key as AuthenticationManager: "auth_token"
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.current.timeout
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(FeedResponse.self, from: data)
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

// MARK: - Feed Algorithm

enum FeedAlgorithm: String {
    case chronological = "ch"
    case timeBased = "time"
}

// MARK: - Feed Response Models

struct FeedResponse: Codable {
    let posts: [String]
    let cursor: String?
    let hasMore: Bool
    let totalCount: Int

    enum CodingKeys: String, CodingKey {
        case posts
        case cursor
        case hasMore = "has_more"
        case totalCount = "total_count"
    }
}

struct FeedPost: Identifiable, Codable {
    let id: String
    let authorId: String
    let authorName: String
    let authorAvatar: String?
    let content: String
    let mediaUrls: [String]
    let createdAt: Date
    let likeCount: Int
    let commentCount: Int
    let shareCount: Int
    let isLiked: Bool
    let isBookmarked: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case authorId = "author_id"
        case authorName = "author_name"
        case authorAvatar = "author_avatar"
        case content
        case mediaUrls = "media_urls"
        case createdAt = "created_at"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case shareCount = "share_count"
        case isLiked = "is_liked"
        case isBookmarked = "is_bookmarked"
    }
}

// MARK: - Feed ViewModel

@MainActor
class FeedViewModel: ObservableObject {
    @Published var posts: [FeedPost] = []
    @Published var postIds: [String] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: String?
    @Published var hasMore = true

    private let feedService = FeedService()
    private var currentCursor: String?
    private var currentAlgorithm: FeedAlgorithm = .chronological

    func loadFeed(algorithm: FeedAlgorithm = .chronological) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        currentAlgorithm = algorithm
        currentCursor = nil

        do {
            let response = try await feedService.getFeed(algo: algorithm, limit: 20, cursor: nil)

            self.postIds = response.posts
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            self.posts = response.posts.enumerated().map { index, postId in
                createMockPost(id: postId, index: index)
            }

            self.error = nil
        } catch let apiError as APIError {
            self.error = apiError.localizedDescription
            print("Feed API Error: \(apiError)")
        } catch {
            self.error = "Failed to load feed: \(error.localizedDescription)"
            print("Feed Error: \(error)")
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore, let cursor = currentCursor else { return }

        isLoadingMore = true

        do {
            let response = try await feedService.getFeed(algo: currentAlgorithm, limit: 20, cursor: cursor)

            self.postIds.append(contentsOf: response.posts)
            self.currentCursor = response.cursor
            self.hasMore = response.hasMore

            let newPosts = response.posts.enumerated().map { index, postId in
                createMockPost(id: postId, index: self.posts.count + index)
            }
            self.posts.append(contentsOf: newPosts)

        } catch {
            print("Load more error: \(error)")
        }

        isLoadingMore = false
    }

    func refresh() async {
        await loadFeed(algorithm: currentAlgorithm)
    }

    private func createMockPost(id: String, index: Int) -> FeedPost {
        let authors = ["Simone Carter", "Alex Johnson", "Maria Garcia", "James Wilson", "Emma Davis"]
        let contents = [
            "Cyborg dreams under the moonlit sky",
            "Just finished an amazing workout!",
            "The sunset today was breathtaking",
            "Working on something exciting! Stay tuned",
            "Coffee and code - the perfect combination"
        ]

        return FeedPost(
            id: id,
            authorId: "user-\(index % 5)",
            authorName: authors[index % authors.count],
            authorAvatar: nil,
            content: contents[index % contents.count],
            mediaUrls: ["post-image", "post-image-2", "post-image-3"][index % 3...index % 3].map { $0 },
            createdAt: Date().addingTimeInterval(-Double(index * 3600)),
            likeCount: Int.random(in: 0...100),
            commentCount: Int.random(in: 0...50),
            shareCount: Int.random(in: 0...20),
            isLiked: false,
            isBookmarked: false
        )
    }
}

// MARK: - HomeView

struct HomeView: View {
    @Binding var currentPage: AppPage
    @Environment(\.dismiss) var dismiss
    @StateObject private var feedViewModel = FeedViewModel()
    @State private var showReportView = false
    @State private var showThankYouView = false
    @State private var showNewPost = false
    @State private var showSearch = false
    @State private var showNotification = false
    @State private var showPhotoOptions = false

    var body: some View {
        ZStack {
            // 条件渲染：根据状态即时切换视图
            if showNotification {
                NotificationView(showNotification: $showNotification)
                    .transition(.identity)
            } else if showSearch {
                SearchView(showSearch: $showSearch)
                    .transition(.identity)
            } else if showNewPost {
                NewPostView(showNewPost: $showNewPost)
                    .transition(.identity)
            } else {
                homeContent
            }

            // MARK: - 照片选项弹窗
            if showPhotoOptions {
                photoOptionsModal
            }
        }
        .animation(.none, value: showNotification)
        .animation(.none, value: showSearch)
        .animation(.none, value: showNewPost)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showReportView) {
            ReportModal(isPresented: $showReportView, showThankYouView: $showThankYouView)
        }
        .onAppear {
            // Load feed when view appears
            if feedViewModel.posts.isEmpty {
                Task { await feedViewModel.loadFeed() }
            }
        }
    }

    var homeContent: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.96, blue: 0.96)
                .ignoresSafeArea()

            NavigationStack {
                VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: { showSearch = true }) {
                        Image("Back-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                    Spacer()
                    Image("ICERED-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
                    Spacer()
                    Button(action: { showNotification = true }) {
                        Image("Notice-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    }
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(Color.white)

                Divider()

                // MARK: - 可滚动内容区
                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: - Loading State
                        if feedViewModel.isLoading && feedViewModel.posts.isEmpty {
                            ProgressView("Loading feed...")
                                .padding()
                        }

                        // MARK: - Error State
                        if let error = feedViewModel.error {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                Button("Retry") {
                                    Task { await feedViewModel.loadFeed() }
                                }
                                .foregroundColor(Color(red: 0.82, green: 0.11, blue: 0.26))
                            }
                            .padding()
                        }

                        // MARK: - Feed Posts (Dynamic)
                        ForEach(feedViewModel.posts) { post in
                            FeedPostCard(post: post, showReportView: $showReportView)
                        }

                        // MARK: - Fallback: Static Cards (when no API data)
                        if feedViewModel.posts.isEmpty && !feedViewModel.isLoading && feedViewModel.error == nil {
                            CommentCardItem(imageAssetName: "post-image", showReportView: $showReportView)
                            CommentCardItem(imageAssetName: "post-image-2", showReportView: $showReportView)
                            CommentCardItem(hasExtraField: true, imageAssetName: "post-image-3", showReportView: $showReportView)
                        }

                        // MARK: - Load More
                        if feedViewModel.hasMore && !feedViewModel.posts.isEmpty {
                            Button(action: {
                                Task { await feedViewModel.loadMore() }
                            }) {
                                if feedViewModel.isLoadingMore {
                                    ProgressView()
                                } else {
                                    Text("Load More")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Color(red: 0.82, green: 0.11, blue: 0.26))
                                }
                            }
                            .padding()
                        }

                        // MARK: - 标题部分
                        VStack(spacing: 8) {
                            Text("Hottest Banker in H.K.")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))

                            Text("Corporate Poll")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54))
                        }

                        // MARK: - 轮播卡片容器 (水平滚动)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                // 卡片 1
                                CarouselCardItem(
                                    rankNumber: "1",
                                    name: "Lucy Liu",
                                    company: "Morgan Stanley",
                                    votes: "2293",
                                    isActive: true,
                                    imageAssetName: "PollCard-1"
                                )

                                // 卡片 2
                                CarouselCardItem(
                                    rankNumber: "2",
                                    name: "Lucy Liu",
                                    company: "Morgan Stanley",
                                    votes: "2293",
                                    isActive: false,
                                    imageAssetName: "PollCard-2"
                                )

                                // 卡片 3
                                CarouselCardItem(
                                    rankNumber: "3",
                                    name: "Lucy Liu",
                                    company: "Morgan Stanley",
                                    votes: "2293",
                                    isActive: false,
                                    imageAssetName: "PollCard-3"
                                )

                                // 卡片 4
                                CarouselCardItem(
                                    rankNumber: "4",
                                    name: "Lucy Liu",
                                    company: "Morgan Stanley",
                                    votes: "2293",
                                    isActive: false,
                                    imageAssetName: "PollCard-4"
                                )

                                // 卡片 5
                                CarouselCardItem(
                                    rankNumber: "5",
                                    name: "Lucy Liu",
                                    company: "Morgan Stanley",
                                    votes: "2293",
                                    isActive: false,
                                    imageAssetName: "PollCard-5"
                                )
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 320)

                        // MARK: - 分页指示点
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                                .frame(width: 6, height: 6)

                            ForEach(0..<4, id: \.self) { _ in
                                Circle()
                                    .fill(Color(red: 0.73, green: 0.73, blue: 0.73))
                                    .frame(width: 6, height: 6)
                            }
                        }

                        // MARK: - View more 按钮
                        HStack(spacing: 8) {
                            Text("view more")
                                .font(.system(size: 13))
                                .foregroundColor(Color(red: 0.81, green: 0.13, blue: 0.25))

                            Rectangle()
                                .stroke(Color(red: 0.81, green: 0.13, blue: 0.25), lineWidth: 0.5)
                                .frame(height: 1)
                                .frame(width: 50)
                        }
                        .padding(.top, 10)
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal)
                }
                .padding(.bottom, -43)
                .safeAreaInset(edge: .bottom) {
                    Color.clear.frame(height: 0)
                }

                // MARK: - 底部导航栏
                HStack(spacing: -20) {
                    // Home
                    VStack(spacing: 2) {
                        Image("home-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 22)
                        Text("Home")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                     .frame(maxWidth: .infinity)

                    // Message
                    VStack(spacing: 4) {
                        Image("Message-icon-black")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text("Message")
                            .font(.system(size: 9))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .message
                    }

                    // New Post
                    NewPostButtonComponent(showNewPost: $showPhotoOptions)

                    // Alice
                    VStack(spacing: -12) {
                        Image("alice-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        Text("")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .alice
                    }

                    // Account
                    VStack(spacing: 4) {
                        Image("Account-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        Text("Account")
                            .font(.system(size: 9))
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .account
                    }
                }
                .frame(height: 60)
                .padding(.bottom, 20)
                .background(Color.white)
                .border(Color(red: 0.74, green: 0.74, blue: 0.74), width: 0.5)
                .offset(y: 35)
                }
            }
        }
    }

    // MARK: - 照片选项弹窗
    private var photoOptionsModal: some View {
        ZStack {
            // 半透明背景遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    showPhotoOptions = false
                }

            // 弹窗内容
            VStack {
                Spacer()

                ZStack() {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 270)
                        .background(.white)
                        .cornerRadius(11)
                        .offset(x: 0, y: 0)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 56, height: 7)
                        .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .cornerRadius(3.50)
                        .offset(x: -0.50, y: -120.50)

                    // Choose Photo
                    Button(action: {
                        // 选择照片操作
                        showPhotoOptions = false
                    }) {
                        Text("Choose Photo")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: -79)

                    // Take Photo
                    Button(action: {
                        // 拍照操作
                        showPhotoOptions = false
                    }) {
                        Text("Take Photo")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0.50, y: -21)

                    // Generate image
                    Button(action: {
                        // 生成图片操作
                        showPhotoOptions = false
                    }) {
                        Text("Generate image")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: 37)

                    // Cancel
                    Button(action: {
                        showPhotoOptions = false
                    }) {
                        Text("Cancel")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .lineSpacing(20)
                            .foregroundColor(.black)
                    }
                    .offset(x: -0.50, y: 105)

                    // 分隔线
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.93, green: 0.93, blue: 0.93), lineWidth: 3)
                        )
                        .offset(x: 0, y: 75)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: -50)
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 0)
                        .overlay(
                            Rectangle()
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )
                        .offset(x: 0, y: 8)
                }
                .frame(width: 375, height: 270)
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - 轮播卡片组件
struct CarouselCardItem: View {
    let rankNumber: String
    let name: String
    let company: String
    let votes: String
    let isActive: Bool
    let imageAssetName: String  // ✅ 新增参数：图片资源名称

    var body: some View {
        VStack(spacing: 16) {
            // 图片区域
            Image(imageAssetName)  // ✅ 使用参数，支持动态图片名称
                .resizable()
                .scaledToFill()
                .frame(height: 250)
                .clipped()
                .cornerRadius(15)

            // 排名和信息
            HStack(spacing: 12) {
                Text(rankNumber)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 35, height: 35)
                    .background(Color(red: 0.82, green: 0.11, blue: 0.26))
                    .cornerRadius(6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))

                    Text(company)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54))
                }

                Spacer()

                Text(votes)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.54))
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .frame(width: 310)
    }
}

// MARK: - 评论卡片组件
struct CommentCardItem: View {
    var hasExtraField: Bool = false
    let imageAssetName: String
    @Binding var showReportView: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - 用户信息头（顶部）
            HStack(spacing: 10) {
                // 头像
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 40, height: 40)

                // 用户信息
                VStack(alignment: .leading, spacing: 2) {
                    Text("Simone Carter")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)

                    Text("1d")
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                }

                Spacer()

                // 菜单按钮 - 点击跳转到 ReportModal
                Button(action: {
                    showReportView = true
                }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.black)
                        .font(.system(size: 14))
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // MARK: - 主图片区域（中间）
            Image(imageAssetName)  // ✅ 使用参数，支持动态图片名称
                .resizable()
                .scaledToFill()  // 改为 scaledToFill() 填满容器，多余部分裁剪
                .frame(maxWidth: .infinity, minHeight: 200)  // 固定宽度，最小高度 200
                .clipped()
                .cornerRadius(12)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // MARK: - 分页指示点
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.81, green: 0.13, blue: 0.25))
                    .frame(width: 6, height: 6)

                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 160)
            .padding(.vertical, 6)

            // MARK: - 评论文本（下部）
            HStack(spacing: 4) {
                Text("kyleegigstead Cyborg dreams...")
                    .font(.system(size: 13))
                    .foregroundColor(.black)

                Text("up")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 0.45, green: 0.44, blue: 0.44))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // MARK: - 交互按钮
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                    Text("0")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                    Text("0")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }

                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                    Text("0")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }

                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                    Text("Share")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }

                Spacer()

                Image(systemName: "bookmark")
                    .font(.system(size: 12))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.white)
        .cornerRadius(12)
    }
}

// MARK: - Feed Post Card (Dynamic Data)
struct FeedPostCard: View {
    let post: FeedPost
    @Binding var showReportView: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: - User Info Header
            HStack(spacing: 10) {
                // Avatar
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 40, height: 40)

                // User Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)

                    Text(post.createdAt.timeAgoDisplay())
                        .font(.system(size: 11))
                        .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                }

                Spacer()

                // Menu Button
                Button(action: { showReportView = true }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.black)
                        .font(.system(size: 14))
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // MARK: - Post Image
            if let imageUrl = post.mediaUrls.first {
                Image(imageUrl)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .clipped()
                    .cornerRadius(12)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }

            // MARK: - Pagination Dots
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.81, green: 0.13, blue: 0.25))
                    .frame(width: 6, height: 6)

                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color(red: 0.85, green: 0.85, blue: 0.85))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 160)
            .padding(.vertical, 6)

            // MARK: - Post Content
            HStack(spacing: 4) {
                Text(post.content)
                    .font(.system(size: 13))
                    .foregroundColor(.black)
                    .lineLimit(2)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // MARK: - Interaction Buttons
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                    Text("\(post.likeCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                    Text("0")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }

                HStack(spacing: 6) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                    Text("\(post.commentCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }

                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 10))
                        .foregroundColor(.black)
                    Text("Share")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                }

                Spacer()

                Image(systemName: post.isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 12))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.white)
        .cornerRadius(12)
    }
}

// MARK: - Date Extension
extension Date {
    func timeAgoDisplay() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfYear], from: self, to: now)

        if let weeks = components.weekOfYear, weeks > 0 {
            return "\(weeks)w"
        } else if let days = components.day, days > 0 {
            return "\(days)d"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)h"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes)m"
        } else {
            return "now"
        }
    }
}

// MARK: - New Post Button Component
struct NewPostButtonComponent: View {
    @State private var isPressed = false
    @Binding var showNewPost: Bool

    var body: some View {
        VStack(spacing: -10) {
            Image("Newpost-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .opacity(isPressed ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isPressed)
            Text("")
                .font(.system(size: 9))
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            // 点击时淡出动画
            isPressed = true

            // 动画结束后即时切换（无过渡动画）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showNewPost = true
            }

            // 重置状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPressed = false
            }
        }
    }
}

#Preview {
    HomeView(currentPage: .constant(.home))
}
