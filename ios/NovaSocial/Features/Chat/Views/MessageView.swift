import SwiftUI
import AVFoundation

// MARK: - 会话预览数据模型
struct ConversationPreview: Identifiable {
    let id: String
    let userName: String
    let lastMessage: String
    let time: String
    let unreadCount: Int
    let hasUnread: Bool
    let isEncrypted: Bool  // E2EE status indicator
    let avatarUrl: String?  // 头像URL（可选）

    init(id: String, userName: String, lastMessage: String, time: String, unreadCount: Int, hasUnread: Bool, isEncrypted: Bool, avatarUrl: String? = nil) {
        self.id = id
        self.userName = userName
        self.lastMessage = lastMessage
        self.time = time
        self.unreadCount = unreadCount
        self.hasUnread = hasUnread
        self.isEncrypted = isEncrypted
        self.avatarUrl = avatarUrl
    }
}

// MARK: - Mock Data for UI Preview (开发阶段用于调试UI)
extension ConversationPreview {
    /// 模拟会话数据 - 用于开发阶段预览UI
    static var mockConversations: [ConversationPreview] {
        [
            ConversationPreview(
                id: "mock-alice",
                userName: "Alice",
                lastMessage: "Hi! I'm your AI assistant. How can I help you today?",
                time: "Just now",
                unreadCount: 1,
                hasUnread: true,
                isEncrypted: false
            ),
            ConversationPreview(
                id: "mock-1",
                userName: "Emma Watson",
                lastMessage: "That sounds great! Let's meet tomorrow 🎉",
                time: "09:41 PM",
                unreadCount: 2,
                hasUnread: true,
                isEncrypted: true
            ),
            ConversationPreview(
                id: "mock-2",
                userName: "James Chen",
                lastMessage: "Did you see the new project update?",
                time: "08:30 PM",
                unreadCount: 0,
                hasUnread: false,
                isEncrypted: true
            ),
            ConversationPreview(
                id: "mock-3",
                userName: "Sophie Miller",
                lastMessage: "Thanks for your help! 🙏",
                time: "Yesterday",
                unreadCount: 0,
                hasUnread: false,
                isEncrypted: false
            ),
            ConversationPreview(
                id: "mock-4",
                userName: "Design Team",
                lastMessage: "Lucy: The new mockups are ready for review",
                time: "Yesterday",
                unreadCount: 5,
                hasUnread: true,
                isEncrypted: false
            ),
            ConversationPreview(
                id: "mock-5",
                userName: "Michael Brown",
                lastMessage: "See you at the gym tomorrow morning!",
                time: "Tuesday",
                unreadCount: 0,
                hasUnread: false,
                isEncrypted: true
            ),
            ConversationPreview(
                id: "mock-6",
                userName: "Sarah Johnson",
                lastMessage: "The restaurant was amazing! We should go again.",
                time: "Monday",
                unreadCount: 0,
                hasUnread: false,
                isEncrypted: false
            ),
            ConversationPreview(
                id: "mock-7",
                userName: "Tech News",
                lastMessage: "Breaking: Apple announces new AI features...",
                time: "12/10",
                unreadCount: 12,
                hasUnread: true,
                isEncrypted: false
            )
        ]
    }
}

struct MessageView: View {
    @Binding var currentPage: AppPage
    @State private var showNewPost = false
    @State private var showChat = false
    @State private var showPhotoOptions = false
    @State private var showAddOptionsMenu = false
    @State private var showQRScanner = false
    @State private var selectedUserName = "User"
    @State private var selectedConversationId = ""
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var showCameraPermissionAlert = false
    @State private var selectedImage: UIImage?
    @State private var showGenerateImage = false
    @State private var showWrite = false

    // MARK: - UserProfile 导航状态
    @State private var showUserProfile = false
    @State private var selectedUserId: String = ""

    // 会话预览数据 - 从API获取
    @State private var conversations: [ConversationPreview] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPreviewMode = false  // 追踪预览模式状态

    // MARK: - Search State
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [UserProfile] = []
    @State private var isSearchLoading = false
    @FocusState private var isSearchFocused: Bool

    // MARK: - 预览模式配置 (开发调试用)
    // 🎨 在模拟器上运行时启用预览模式，方便调试UI
    #if DEBUG
    private static var useMessagePreviewMode: Bool {
        #if targetEnvironment(simulator)
        return false  // 关闭模拟器预览模式，使用真实API
        #else
        return false
        #endif
    }
    #else
    private static let useMessagePreviewMode = false
    #endif

    // ChatService 实例
    private let chatService = ChatService()
    private let friendsService = FriendsService()

    init(currentPage: Binding<AppPage>) {
        self._currentPage = currentPage
    }

    // MARK: - 从API加载会话列表
    private func loadConversations() async {
        // 🎨 预览模式：使用模拟数据进行UI调试
        if Self.useMessagePreviewMode {
            print("🎨 [MessageView] Preview Mode enabled - using mock data")
            await MainActor.run {
                self.conversations = ConversationPreview.mockConversations
                self.isLoading = false
                self.errorMessage = nil
                self.isPreviewMode = true
            }
            return
        }

        await MainActor.run {
            self.isPreviewMode = false
        }

        print("🚀 [MessageView] loadConversations() starting...")
        isLoading = true
        errorMessage = nil

        do {
            print("📞 [MessageView] Calling chatService.getConversations()")
            let apiConversations = try await chatService.getConversations()

            print("✅ [MessageView] Loaded \(apiConversations.count) conversations from API")

            // Convert to UI model
            let currentUserId = KeychainService.shared.get(.userId) ?? ""
            let previews = apiConversations.map { conv -> ConversationPreview in
                // For direct conversations, show the other user's name
                // For group conversations, show the group name
                let userName: String
                if conv.type == .direct {
                    // Find the other member (not current user)
                    if let otherMember = conv.members.first(where: { $0.userId != currentUserId }) {
                        userName = otherMember.username
                    } else if let firstMember = conv.members.first {
                        userName = firstMember.username
                    } else {
                        userName = "User \(conv.id.prefix(4))"
                    }
                } else {
                    // Group conversation - use group name
                    userName = conv.name ?? "Group \(conv.id.prefix(4))"
                }
                
                // Get last message content (may need decryption)
                let lastMsg = conv.lastMessage?.content ?? "Start chatting!"
                let timeStr = formatTime(conv.lastMessage?.timestamp ?? conv.updatedAt)

                return ConversationPreview(
                    id: conv.id,
                    userName: userName,
                    lastMessage: lastMsg,
                    time: timeStr,
                    unreadCount: conv.unreadCount,
                    hasUnread: conv.unreadCount > 0,
                    isEncrypted: conv.isEncrypted
                )
            }

            await MainActor.run {
                self.conversations = previews
                self.isLoading = false
            }
        } catch {
            print("❌ [MessageView] Failed to load conversations: \(error)")

            await MainActor.run {
                self.errorMessage = "Failed to load messages"
                self.isLoading = false
                // 如果API失败，显示空列表而不是mock数据
                self.conversations = []
            }
        }
    }

    // 格式化时间显示
    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd"
            return formatter.string(from: date)
        }
    }

    // MARK: - Search Functions
    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            await MainActor.run {
                searchResults = []
            }
            return
        }

        await MainActor.run {
            isSearchLoading = true
        }

        // 在预览模式下使用本地过滤
        if Self.useMessagePreviewMode {
            await MainActor.run {
                // 模拟搜索延迟
                searchResults = getMockSearchResults(query: query)
                isSearchLoading = false
            }
            return
        }

        do {
            let users = try await friendsService.searchUsers(query: query, limit: 20)
            await MainActor.run {
                searchResults = users
                isSearchLoading = false
            }
        } catch {
            print("❌ [MessageView] Search failed: \(error)")
            await MainActor.run {
                searchResults = []
                isSearchLoading = false
            }
        }
    }

    private func getMockSearchResults(query: String) -> [UserProfile] {
        let mockUsers = [
            UserProfile(id: "mock-brody", username: "Brody", displayName: "Brody", bio: "Dude, I just saw.", avatarUrl: nil, followerCount: 150, followingCount: 120, postCount: 45),
            UserProfile(id: "mock-blaine", username: "Blaine", displayName: "Blaine", bio: "Hey bro, are you free later?", avatarUrl: nil, followerCount: 200, followingCount: 180, postCount: 78),
            UserProfile(id: "mock-bella", username: "Bella", displayName: "Bella", bio: "Living my best life", avatarUrl: nil, followerCount: 500, followingCount: 350, postCount: 120),
            UserProfile(id: "mock-brian", username: "Brian", displayName: "Brian", bio: "Tech enthusiast", avatarUrl: nil, followerCount: 300, followingCount: 250, postCount: 60)
        ]

        return mockUsers.filter { user in
            let name = user.displayName ?? user.username
            return name.lowercased().contains(query.lowercased()) ||
                   user.username.lowercased().contains(query.lowercased())
        }
    }

    private func startConversationWithUser(_ user: UserProfile) {
        // 设置选中的用户信息并跳转到聊天页面
        selectedConversationId = user.id
        selectedUserName = user.displayName ?? user.username
        searchText = ""
        isSearching = false
        searchResults = []
        isSearchFocused = false
        showChat = true
    }

    // MARK: - Camera Permission Check
    private func checkCameraPermissionAndOpen() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCamera = true
                    } else {
                        showCameraPermissionAlert = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraPermissionAlert = true
        @unknown default:
            showCameraPermissionAlert = true
        }
    }

    var body: some View {
        ZStack {
            // 条件渲染：根据状态即时切换视图
            if showChat {
                ChatView(
                    showChat: $showChat,
                    conversationId: selectedConversationId,
                    userName: selectedUserName
                )
                .transition(.identity)
            } else if showNewPost {
                NewPostView(showNewPost: $showNewPost, initialImage: selectedImage)
                    .transition(.identity)
            } else if showGenerateImage {
                GenerateImage01View(showGenerateImage: $showGenerateImage)
                    .transition(.identity)
            } else if showWrite {
                WriteView(showWrite: $showWrite)
                    .transition(.identity)
            } else if showUserProfile {
                // MARK: - UserProfile 页面
                UserProfileView(
                    showUserProfile: $showUserProfile,
                    userId: selectedUserId
                )
                .transition(.identity)
            } else {
                messageContent
            }

            // MARK: - 照片选项弹窗
            if showPhotoOptions {
                PhotoOptionsModal(
                    isPresented: $showPhotoOptions,
                    onChoosePhoto: {
                        showImagePicker = true
                    },
                    onTakePhoto: {
                        checkCameraPermissionAndOpen()
                    },
                    onGenerateImage: {
                        showGenerateImage = true
                    },
                    onWrite: {
                        showWrite = true
                    }
                )
            }

            // MARK: - 添加选项菜单弹窗
            if showAddOptionsMenu {
                addOptionsMenu
            }
        }
        .animation(.none, value: showChat)
        .animation(.none, value: showNewPost)
        .animation(.none, value: showGenerateImage)
        .animation(.none, value: showWrite)
        .animation(.none, value: showUserProfile)
        .sheet(isPresented: $showQRScanner) {
            QRCodeScannerView(isPresented: $showQRScanner)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
        }
        .alert("Camera Access Required", isPresented: $showCameraPermissionAlert) {
            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow camera access in Settings to take photos.")
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            // 选择/拍摄照片后，自动跳转到NewPostView
            if newValue != nil {
                showNewPost = true
            }
        }
        .onAppear {
            // 页面显示时加载会话列表
            Task {
                await loadConversations()
            }
        }
    }

    // MARK: - 消息页面内容
    private var messageContent: some View {
        ZStack {
            // MARK: - 背景色
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    // 左侧占位，保持标题居中
                    Color.clear
                        .frame(width: 24)

                    Spacer()

                    Text(LocalizedStringKey("Message"))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // 右侧添加按钮 (圆圈加号)
                    Button(action: {
                        showAddOptionsMenu = true
                    }) {
                        Image(systemName: "plus.circle")
                            .frame(width: 24, height: 24)
                            .foregroundColor(DesignTokens.textPrimary)
                    }
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(DesignTokens.surface)

                // MARK: - 顶部分割线
                Divider()
                    .frame(height: 0.5)
                    .background(DesignTokens.dividerColor)

                // MARK: - 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(DesignTokens.textSecondary)

                    TextField("Search", text: $searchText)
                        .font(Font.custom("Helvetica Neue", size: 14))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                        .focused($isSearchFocused)
                        .onChange(of: searchText) { _, newValue in
                            isSearching = !newValue.isEmpty
                            if !newValue.isEmpty {
                                Task {
                                    await performSearch(query: newValue)
                                }
                            } else {
                                searchResults = []
                            }
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            isSearching = false
                            searchResults = []
                            isSearchFocused = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(DesignTokens.textSecondary)
                        }
                    }
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(height: 32)
                .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                .cornerRadius(32)
                .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

                // MARK: - 预览模式提示（仅在DEBUG模式显示）
                #if DEBUG
                if isPreviewMode {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 12))
                        Text("Preview Mode - Mock Data (Simulator)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                }
                #endif

                // MARK: - 搜索结果 / 消息列表
                if isSearching {
                    // 搜索结果列表
                    ScrollView {
                        VStack(spacing: 0) {
                            if isSearchLoading {
                                ProgressView()
                                    .padding(.top, 40)
                            } else if searchResults.isEmpty && !searchText.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 32))
                                        .foregroundColor(DesignTokens.textSecondary)
                                    Text("No results found")
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignTokens.textSecondary)
                                }
                                .padding(.top, 60)
                            } else {
                                ForEach(searchResults, id: \.id) { user in
                                    SearchResultRow(
                                        user: user,
                                        onMessageTapped: {
                                            // 开始与该用户的对话
                                            startConversationWithUser(user)
                                        }
                                    )
                                }
                            }
                        }
                    }
                } else {
                // MARK: - 消息列表
                ScrollView {
                    VStack(spacing: 2) {
                        // 加载状态
                        if isLoading {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(1.2)
                                Text(LocalizedStringKey("Loading messages..."))
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignTokens.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        }
                        // 错误状态
                        else if let error = errorMessage {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(DesignTokens.accentColor)
                                Text(error)
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignTokens.textSecondary)
                                Button(action: {
                                    Task {
                                        await loadConversations()
                                    }
                                }) {
                                Text(LocalizedStringKey("Retry"))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(DesignTokens.textOnAccent)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 8)
                                        .background(DesignTokens.accentColor)
                                        .cornerRadius(20)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        }
                        // 空状态
                        else if conversations.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "message")
                                    .font(.system(size: 40))
                                    .foregroundColor(DesignTokens.textSecondary)
                                Text(LocalizedStringKey("No messages yet"))
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(DesignTokens.textSecondary)
                                Text(LocalizedStringKey("Start a conversation with friends"))
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignTokens.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        }
                        // 会话列表
                        else {
                            ForEach(conversations) { convo in
                                MessageListItem(
                                    name: convo.userName,
                                    messagePreview: convo.lastMessage,
                                    time: convo.time,
                                    unreadCount: convo.unreadCount,
                                    showMessagePreview: true,
                                    showTimeAndBadge: convo.hasUnread,
                                    isEncrypted: convo.isEncrypted,
                                    userId: convo.id,  // 使用会话ID（实际项目中应传入对方用户ID）
                                    onAvatarTapped: { userId in
                                        // 点击头像跳转用户主页（排除 Alice）
                                        if convo.userName.lowercased() != "alice" {
                                            selectedUserId = userId
                                            showUserProfile = true
                                        }
                                    }
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // alice 跳转到 Alice 页面，其他用户跳转到 Chat 页面
                                    if convo.userName.lowercased() == "alice" {
                                        currentPage = .alice
                                    } else {
                                        selectedConversationId = convo.id
                                        selectedUserName = convo.userName
                                        showChat = true
                                    }
                                }

                                if convo.id != conversations.last?.id {
                                    Divider()
                                        .frame(height: 0.25)
                                        .background(DesignTokens.borderColor)
                                }
                            }
                        }
                    }
                    .padding(.bottom, DesignTokens.bottomBarHeight + DesignTokens.spacing12 + 40)
                }
                } // End of else (non-searching state)
            }
            .safeAreaInset(edge: .bottom) {
                BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions, showNewPost: $showNewPost)
            }
        }
    }

    // MARK: - 添加选项菜单弹窗
    private var addOptionsMenu: some View {
        ZStack {
            // 半透明背景遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    showAddOptionsMenu = false
                }

            // 弹窗内容 - 定位在右上角
            VStack {
                HStack {
                    Spacer()

                    ZStack {
                        // 背景
                        Rectangle()
                            .foregroundColor(DesignTokens.surface)
                            .frame(width: 180, height: 151)
                            .cornerRadius(8)
                            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)

                        VStack(spacing: 0) {
                            // Add Friends
                            Button(action: {
                                showAddOptionsMenu = false
                                currentPage = .addFriends
                            }) {
                                HStack(alignment: .center, spacing: 16) {
                                    Image("AddFriends")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                    Text(LocalizedStringKey("Add Friends"))
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignTokens.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(height: 50)
                            }

                            Divider()
                                .frame(height: 0.20)
                                .background(DesignTokens.textMuted)
                                .padding(.horizontal, 16)

                            // New Chat
                            Button(action: {
                                showAddOptionsMenu = false
                                currentPage = .newChat
                            }) {
                                HStack(alignment: .center, spacing: 16) {
                                    Image("GroupChat")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                    Text(LocalizedStringKey("New Chat"))
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignTokens.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(height: 50)
                            }

                            Divider()
                                .frame(height: 0.20)
                                .background(DesignTokens.textMuted)
                                .padding(.horizontal, 16)

                            // Scan QR Code
                            Button(action: {
                                showAddOptionsMenu = false
                                showQRScanner = true
                            }) {
                                HStack(alignment: .center, spacing: 16) {
                                    Image("Scan")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                    Text(LocalizedStringKey("Scan QR Code"))
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignTokens.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(height: 50)
                            }
                        }
                        .frame(width: 180, height: 151)
                    }
                    .padding(.trailing, 16)
                }
                .padding(.top, 72) // 从顶部安全区域下方开始

                Spacer()
            }
        }
    }
}

// MARK: - 消息列表项组件
struct MessageListItem: View {
    var name: String = "Liam"
    var messagePreview: String = "Hello, how are you bro~"
    var time: String = "09:41 PM"
    var unreadCount: Int = 1
    var showMessagePreview: Bool = true
    var showTimeAndBadge: Bool = true
    var isEncrypted: Bool = false  // E2EE status indicator
    var userId: String = ""  // 用户ID（用于跳转用户主页）
    var onAvatarTapped: ((String) -> Void)?  // 点击头像回调

    var body: some View {
        HStack(spacing: 12) {
            // 头像 - alice 使用自定义图片，其他用户使用默认头像（可点击跳转用户主页）
            Group {
                if name.lowercased() == "alice" {
                    Image("alice-avatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    DefaultAvatarView(size: 50)
                }
            }
            .onTapGesture {
                onAvatarTapped?(userId)
            }

            // 消息内容
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(DesignTokens.textPrimary)

                    // E2EE indicator - show lock icon for encrypted conversations
                    if isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }
                }

                // 消息预览 - 使用动态消息
                Text(messagePreview)
                    .font(.system(size: 15))
                    .foregroundColor(DesignTokens.textSecondary)
                    .opacity(showMessagePreview ? 1 : 0)
            }

            Spacer()

            // 时间和未读标记 - 可隐藏
            if showTimeAndBadge {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(time)
                        .font(.system(size: 13))
                        .foregroundColor(DesignTokens.textMuted)

                    ZStack {
                        Circle()
                            .fill(DesignTokens.accentColor)
                            .frame(width: 17, height: 17)

                        Text(LocalizedStringKey("\(unreadCount)"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 13, leading: 18, bottom: 13, trailing: 18))
        .frame(height: 80)
        .background(DesignTokens.backgroundColor)
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let user: UserProfile
    let onMessageTapped: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            // 用户头像
            if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle()
                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 50, height: 50)
            }

            // 用户信息
            VStack(alignment: .leading, spacing: 5) {
                Text(user.displayName ?? user.username)
                    .font(Font.custom("Helvetica Neue", size: 18).weight(.bold))
                    .lineSpacing(20)
                    .foregroundColor(.black)

                Text(user.bio ?? "")
                    .font(Font.custom("Helvetica Neue", size: 14))
                    .lineSpacing(20)
                    .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54))
                    .lineLimit(1)
            }

            Spacer()

            // Message 按钮
            Button(action: onMessageTapped) {
                Text("Message")
                    .font(Font.custom("Helvetica Neue", size: 12))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 57)
                    .stroke(.black, lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 18)
        .frame(height: 80)
        .background(DesignTokens.backgroundColor)
    }
}

// MARK: - Previews

#Preview("Message - Default") {
    MessageView(currentPage: .constant(.message))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("Message - Dark Mode") {
    MessageView(currentPage: .constant(.message))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
