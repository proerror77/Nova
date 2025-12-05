import SwiftUI

// MARK: - 会话预览数据模型
struct ConversationPreview: Identifiable {
    let id: String
    let userName: String
    let lastMessage: String
    let time: String
    let unreadCount: Int
    let hasUnread: Bool
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
    @State private var selectedImage: UIImage?
    @State private var showGenerateImage = false

    // 会话预览数据 - 从API获取
    @State private var conversations: [ConversationPreview] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // ChatService 实例
    private let chatService = ChatService()

    init(currentPage: Binding<AppPage>) {
        self._currentPage = currentPage
    }

    // MARK: - 从API加载会话列表
    private func loadConversations() async {
        isLoading = true
        errorMessage = nil

        do {
            let apiConversations = try await chatService.getConversations()

            #if DEBUG
            print("[MessageView] Loaded \(apiConversations.count) conversations from API")
            #endif

            // 转换为UI模型
            let previews = apiConversations.map { conv -> ConversationPreview in
                let userName = conv.name ?? "User \(conv.id.prefix(4))"
                let lastMsg = conv.lastMessage?.content ?? "Start chatting!"
                let timeStr = formatTime(conv.lastMessage?.timestamp ?? conv.updatedAt)

                return ConversationPreview(
                    id: conv.id,
                    userName: userName,
                    lastMessage: lastMsg,
                    time: timeStr,
                    unreadCount: conv.unreadCount,
                    hasUnread: conv.unreadCount > 0
                )
            }

            await MainActor.run {
                self.conversations = previews
                self.isLoading = false
            }
        } catch {
            #if DEBUG
            print("[MessageView] Failed to load conversations: \(error)")
            #endif

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
                        showCamera = true
                    },
                    onGenerateImage: {
                        showGenerateImage = true
                    },
                    onWrite: {
                        showNewPost = true
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
        .sheet(isPresented: $showQRScanner) {
            QRCodeScannerView(isPresented: $showQRScanner)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
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
                    Spacer()

                    Text(LocalizedStringKey("Message"))
                        .font(Font.custom("Helvetica Neue", size: 24).weight(.medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // 右侧添加按钮 (圆圈加号)
                    Button(action: {
                        showAddOptionsMenu = true
                    }) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(.black)
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

                    Text(LocalizedStringKey("Search"))
                        .font(Font.custom("Helvetica Neue", size: 15))
                        .foregroundColor(DesignTokens.textSecondary)

                    Spacer()
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(height: 32)
                .background(DesignTokens.tileBackground)
                .cornerRadius(32)
                .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

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
                                    .font(Font.custom("Helvetica Neue", size: 14))
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
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .foregroundColor(DesignTokens.textSecondary)
                                Button(action: {
                                    Task {
                                        await loadConversations()
                                    }
                                }) {
                                Text(LocalizedStringKey("Retry"))
                                        .font(Font.custom("Helvetica Neue", size: 14).weight(.medium))
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
                                    .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                                    .foregroundColor(DesignTokens.textSecondary)
                                Text(LocalizedStringKey("Start a conversation with friends"))
                                    .font(Font.custom("Helvetica Neue", size: 14))
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
                                    showTimeAndBadge: convo.hasUnread
                                )
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
                }
                .padding(.bottom, DesignTokens.bottomBarHeight + DesignTokens.spacing12)
            }
            .safeAreaInset(edge: .bottom) {
                BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions)
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
                        // 白色背景
                        Rectangle()
                            .foregroundColor(.white)
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
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .foregroundColor(.black)
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
                                    Text(LocalizedStringKey("Start Group Chat"))
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .foregroundColor(.black)
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
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .foregroundColor(.black)
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

    var body: some View {
        HStack(spacing: 12) {
            // 头像 - alice 使用自定义图片，其他用户使用默认圆形
            if name.lowercased() == "alice" {
                Image("alice-avatar")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 63, height: 63)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                    .frame(width: 63, height: 63)
            }

            // 消息内容
            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(Font.custom("Helvetica Neue", size: 19).weight(.bold))
                    .foregroundColor(.black)

                // 消息预览 - 使用动态消息
                Text(messagePreview)
                    .font(Font.custom("Helvetica Neue", size: 15))
                    .foregroundColor(DesignTokens.textSecondary)
                    .opacity(showMessagePreview ? 1 : 0)
            }

            Spacer()

            // 时间和未读标记 - 可隐藏
            if showTimeAndBadge {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(time)
                        .font(Font.custom("Helvetica Neue", size: 13))
                        .foregroundColor(DesignTokens.textMuted)

                    ZStack {
                        Circle()
                            .fill(DesignTokens.accentColor)
                            .frame(width: 17, height: 17)

                        Text(LocalizedStringKey("\(unreadCount)"))
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.medium))
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

#Preview {
    struct PreviewWrapper: View {
        @State private var currentPage: AppPage = .message

        var body: some View {
            MessageView(currentPage: $currentPage)
        }
    }

    return PreviewWrapper()
}
