import SwiftUI

// MARK: - 会话预览数据模型
struct ConversationPreview {
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
    @State private var selectedUserMessages: [ChatMessage] = []
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var showGenerateImage = false

    // 会话预览数据
    @State private var conversations: [ConversationPreview] = []

    init(currentPage: Binding<AppPage>) {
        self._currentPage = currentPage

        // 初始化用户名
        var names = ["alice", "Ethan Miller"]
        let randomNames = ["Liam", "Emma", "Noah", "Olivia", "James", "Ava", "Lucas", "Sophia", "Mason", "Isabella", "Mia", "Alexander", "Charlotte", "Michael", "Amelia", "Daniel", "Harper", "Henry", "Evelyn"].shuffled()
        names.append(contentsOf: Array(randomNames.prefix(7)))

        // 初始化会话预览数据
        let messages = [
            "Hi", "Hello!", "How are you?", "What's up?", "Good morning!",
            "See you later", "Thanks!", "Sounds good", "Ok", "Sure thing",
            "Let's meet up", "Call me later", "I'm on my way", "Almost there",
            "That's awesome!", "Haha", "😊", "👍", "Miss you", "Bye!"
        ]

        let times = [
            "09:41 PM", "10:30 AM", "Yesterday", "2:15 PM", "11:20 AM",
            "3:45 PM", "8:30 PM", "Monday", "Tuesday", "5:10 PM"
        ]

        var convos: [ConversationPreview] = []
        for name in names {
            // 70% 概率显示真实消息
            let hasRealMessage = Double.random(in: 0...1) < 0.7
            let message = hasRealMessage ? (messages.randomElement() ?? "") : "Now let's start chatting!"
            let time = hasRealMessage ? times.randomElement() ?? "" : ""
            let hasUnread = hasRealMessage && Double.random(in: 0...1) < 0.6 // 60% 概率有未读
            let unreadCount = hasUnread ? Int.random(in: 1...5) : 0

            convos.append(ConversationPreview(
                userName: name,
                lastMessage: message,
                time: time,
                unreadCount: unreadCount,
                hasUnread: hasUnread
            ))
        }

        self._conversations = State(initialValue: convos)
    }

    var body: some View {
        ZStack {
            // 条件渲染：根据状态即时切换视图
            if showChat {
                ChatView(showChat: $showChat, userName: selectedUserName, initialMessages: selectedUserMessages)
                    .transition(.identity)
            } else if showNewPost {
                NewPostView(showNewPost: $showNewPost)
                    .transition(.identity)
            } else if showGenerateImage {
                GenerateImage01View(showGenerateImage: $showGenerateImage)
                    .transition(.identity)
            } else {
                messageContent
            }

            // MARK: - 照片选项弹窗
            if showPhotoOptions {
                photoOptionsModal
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
    }

    // MARK: - 消息页面内容
    private var messageContent: some View {
        ZStack {
            // MARK: - 背景色
            Color(red: 0.97, green: 0.96, blue: 0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Spacer()

                    Text("Message")
                        .font(Font.custom("Helvetica Neue", size: 24).weight(.medium))
                        .foregroundColor(.black)

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
                .background(Color.white)

                // MARK: - 顶部分割线
                Divider()
                    .frame(height: 0.5)
                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))

                // MARK: - 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    Text("Search")
                        .font(Font.custom("Helvetica Neue", size: 15))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    Spacer()
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(height: 32)
                .background(Color(red: 0.89, green: 0.88, blue: 0.87))
                .cornerRadius(32)
                .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

                // MARK: - 消息列表
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(conversations.indices, id: \.self) { index in
                            let convo = conversations[index]
                            MessageListItem(
                                name: convo.userName,
                                messagePreview: convo.lastMessage,
                                time: convo.time,
                                unreadCount: convo.unreadCount,
                                showMessagePreview: true, // 总是显示消息预览
                                showTimeAndBadge: convo.hasUnread
                            )
                            .onTapGesture {
                                let userName = convo.userName
                                // alice 跳转到 Alice 页面，其他用户跳转到 Chat 页面
                                if userName.lowercased() == "alice" {
                                    currentPage = .alice
                                } else {
                                    selectedUserName = userName
                                    // 创建初始消息（只有真实消息才显示在 Chat 中）
                                    if !convo.lastMessage.isEmpty && convo.lastMessage != "Now let's start chatting!" {
                                        selectedUserMessages = [
                                            ChatMessage(
                                                text: convo.lastMessage,
                                                isFromMe: false,
                                                timestamp: Date()
                                            )
                                        ]
                                    } else {
                                        selectedUserMessages = []
                                    }
                                    showChat = true
                                }
                            }

                            if index < conversations.count - 1 {
                                Divider()
                                    .frame(height: 0.25)
                                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))
                            }
                        }
                    }
                }
                .padding(.bottom, -43)

                // MARK: - 底部导航栏
                HStack(spacing: -20) {
                    // Home
                    VStack(spacing: 2) {
                        Image("home-icon-black")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 22)
                        Text("Home")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.black)
                    }
                     .frame(maxWidth: .infinity)
                     .onTapGesture {
                         currentPage = .home
                     }

                    // Message (高亮状态)
                    VStack(spacing: 4) {
                        Image("Message-icon-red")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                        Text("Message")
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                    .frame(maxWidth: .infinity)

                    // New Post
                    NewPostButtonComponent(showNewPost: $showPhotoOptions)

                    // Alice
                    VStack(spacing: -12) {
                        Image("alice-button-off")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        Text("")
                            .font(.system(size: 9))
                    }
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        currentPage = .alice
                    }

                    // Account
                    VStack(spacing: -12) {
                        Image("Account-button-off")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 44, height: 44)
                        Text("")
                            .font(.system(size: 9))
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
                        showPhotoOptions = false
                        showImagePicker = true
                    }) {
                        Text("Choose Photo")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0, y: -79)

                    // Take Photo
                    Button(action: {
                        showPhotoOptions = false
                        showCamera = true
                    }) {
                        Text("Take Photo")
                            .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))
                    }
                    .offset(x: 0.50, y: -21)

                    // Generate image
                    Button(action: {
                        showPhotoOptions = false
                        showGenerateImage = true
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
                                    Text("Add Friends")
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
                                .background(Color(red: 0.77, green: 0.77, blue: 0.77))
                                .padding(.horizontal, 16)

                            // Start Group Chat
                            Button(action: {
                                showAddOptionsMenu = false
                                currentPage = .startGroupChat
                            }) {
                                HStack(alignment: .center, spacing: 16) {
                                    Image("GroupChat")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                    Text("Start Group Chat")
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
                                .background(Color(red: 0.77, green: 0.77, blue: 0.77))
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
                                    Text("Scan QR Code")
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
                    .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54))
                    .opacity(showMessagePreview ? 1 : 0)
            }

            Spacer()

            // 时间和未读标记 - 可隐藏
            if showTimeAndBadge {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(time)
                        .font(Font.custom("Helvetica Neue", size: 13))
                        .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))

                    ZStack {
                        Circle()
                            .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                            .frame(width: 17, height: 17)

                        Text("\(unreadCount)")
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.medium))
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 13, leading: 18, bottom: 13, trailing: 18))
        .frame(height: 80)
        .background(Color(red: 0.97, green: 0.96, blue: 0.96))
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
