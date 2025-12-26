import SwiftUI

// MARK: - Alice Model Data Structure
struct AliceModel: Identifiable {
    let id = UUID()
    let name: String
    let displayName: String
    let description: String
    let isOnDevice: Bool
    let isGrok: Bool

    init(name: String, displayName: String? = nil, description: String, isOnDevice: Bool = false, isGrok: Bool = false) {
        self.name = name
        self.displayName = displayName ?? name
        self.description = description
        self.isOnDevice = isOnDevice
        self.isGrok = name.hasPrefix("grok") || isGrok
    }
}

// MARK: - Alice Chat Message Data Structure
@Observable
final class AliceChatMessage: Identifiable {
    let id = UUID()
    var content: String
    let isUser: Bool
    let timestamp: Date
    var isStreaming: Bool

    init(content: String, isUser: Bool, isStreaming: Bool = false) {
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.isStreaming = isStreaming
    }
}

struct AliceView: View {
    @Binding var currentPage: AppPage
    @State private var showPhotoOptions = false
    @State private var showModelSelector = false
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var selectedImage: UIImage?
    @State private var showGenerateImage = false
    @State private var showNewPost = false
    @State private var showWrite = false
    @State private var selectedModel = "grok-4"  // 預設使用 Grok 4
    
    // MARK: - Voice Chat States
    @State private var showVoiceChat = false

    // MARK: - Chat States
    @State private var messages: [AliceChatMessage] = []
    @State private var inputText = ""
    @State private var isWaitingForResponse = false
    @State private var errorMessage: String?

    // MARK: - AI Service
    private let aliceService = AliceService.shared
    private let aiRouter = AIRouter.shared
    private let xaiService = XAIService.shared

    // MARK: - Model Data
    private var aliceModels: [AliceModel] {
        var models: [AliceModel] = []

        // Grok 4 - X.AI 最新模型（推薦）
        models.append(AliceModel(
            name: "grok-4",
            displayName: "Grok 4",
            description: "X.AI 最新模型 ⭐️ 推薦"
        ))

        // 本地模型（如果可用）
        if aiRouter.isOnDeviceAvailable {
            models.append(AliceModel(
                name: "on-device",
                displayName: "On-Device AI",
                description: "隱私優先・離線可用",
                isOnDevice: true
            ))
        }

        // 遠端模型（Nova 後端）
        models.append(contentsOf: [
            AliceModel(name: "gpt-4o-all", description: "Most capable model"),
            AliceModel(name: "gpt-4o", description: "GPT-4 optimized"),
            AliceModel(name: "gpt-4", description: "GPT-4 standard"),
            AliceModel(name: "gpt-3.5-turbo", description: "Fast and efficient")
        ])

        return models
    }

    /// 是否使用 Grok (X.AI) 模型
    private var isUsingGrok: Bool {
        selectedModel.hasPrefix("grok")
    }

    /// 是否使用本地模型
    private var isUsingOnDevice: Bool {
        selectedModel == "on-device"
    }

    var body: some View {
        ZStack {
            // 条件渲染：根据状态切换视图
            if showNewPost {
                NewPostView(showNewPost: $showNewPost, initialImage: selectedImage)
                    .transition(.identity)
            } else if showGenerateImage {
                GenerateImage01View(showGenerateImage: $showGenerateImage)
                    .transition(.identity)
            } else if showWrite {
                WriteView(showWrite: $showWrite)
                    .transition(.identity)
            } else {
                aliceContent
            }
        }
        .animation(.none, value: showNewPost)
        .animation(.none, value: showGenerateImage)
        .animation(.none, value: showWrite)
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: .photoLibrary, selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera, selectedImage: $selectedImage)
        }
        .fullScreenCover(isPresented: $showVoiceChat) {
            // 使用 LiveKit 語音對話（支援 barge-in 打斷）
            LiveKitVoiceChatView(isPresented: $showVoiceChat)
        }
        .onChange(of: selectedImage) { oldValue, newValue in
            // 选择/拍摄照片后，自动跳转到NewPostView
            if newValue != nil {
                showNewPost = true
            }
        }
    }

    // MARK: - Alice 主内容
    private var aliceContent: some View {
        ZStack(alignment: .bottom) {
            // 内容区域
            ZStack {
                // 背景色
                DesignTokens.backgroundColor
                    .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    // 清除對話按鈕
                    Button(action: clearChat) {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundColor(messages.isEmpty ? DesignTokens.textSecondary : DesignTokens.textPrimary)
                    }
                    .disabled(messages.isEmpty)
                    .padding(.leading, 16)

                    Spacer()

                    // 模型選擇器
                    HStack(spacing: 5) {
                        // 模型圖標
                        if isUsingGrok {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        } else if isUsingOnDevice {
                            Image(systemName: "cpu")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.green)
                        }

                        Text(aliceModels.first { $0.name == selectedModel }?.displayName ?? selectedModel)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(DesignTokens.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(DesignTokens.textPrimary)
                    }
                    .onTapGesture {
                        showModelSelector.toggle()
                    }

                    Spacer()

                    // 佔位符保持對稱
                    Color.clear
                        .frame(width: 34, height: 18)
                        .padding(.trailing, 16)
                }
                .frame(height: 56)
                .background(DesignTokens.surface)

                Divider()

                // MARK: - 聊天消息区域
                if messages.isEmpty {
                    // 空状态 - 显示中间图标
                    VStack {
                        Spacer()
                        Image("alice-center-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                    }
                } else {
                    // 聊天消息列表
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(messages) { message in
                                    AliceChatMessageView(message: message)
                                        .id(message.id)
                                }

                                if isWaitingForResponse {
                                    HStack {
                                        ProgressView()
                                            .padding(.leading, 16)
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            hideKeyboard()
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let lastMessage = messages.last {
                                withAnimation {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                // MARK: - 底部固定区域（按钮组 + 输入框）
                VStack(spacing: 6) {
                    // 功能按钮组
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            // Get Super alice 按钮
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 18))
                                    .foregroundColor(DesignTokens.textPrimary)
                                Text("Get Super alice")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(DesignTokens.textPrimary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 42)
                            .background(DesignTokens.surface)
                            .cornerRadius(21)
                            .overlay(
                                RoundedRectangle(cornerRadius: 21)
                                    .inset(by: 0.50)
                                    .stroke(DesignTokens.borderColor, lineWidth: 0.50)
                            )

                            // Voice Mode 按钮
                            Button(action: {
                                showVoiceChat = true
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 16))
                                    Text("Voice Mode")
                                        .font(.system(size: 16, weight: .medium))
                                }
                                .foregroundColor(DesignTokens.textPrimary)
                                .frame(width: 140, height: 42)
                                .background(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.3), .blue.opacity(0.2)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(21)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 21)
                                        .inset(by: 0.50)
                                        .stroke(
                                            LinearGradient(
                                                colors: [.purple.opacity(0.5), .blue.opacity(0.3)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .frame(height: 50)

                    // 输入框区域
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(DesignTokens.textPrimary)

                        TextField("Ask any questions", text: $inputText)
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.textPrimary)
                            .submitLabel(.send)
                            .onSubmit {
                                sendMessage()
                            }

                        if !inputText.isEmpty {
                            Button(action: sendMessage) {
                                Image("Send-Icon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24, height: 24)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                    .background(DesignTokens.surface)
                    .cornerRadius(26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 26)
                            .inset(by: 0.50)
                            .stroke(DesignTokens.borderColor, lineWidth: 0.50)
                    )
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 60)  // 为底部导航栏预留空间
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)

            // MARK: - 模型选择器弹窗
            if showModelSelector {
                modelSelectorModal
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
                        showWrite = true
                    }
                )
            }
            }

            // MARK: - 底部导航栏（覆盖在内容上方）
            BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions, showNewPost: $showNewPost)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Send Message Function
    private func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        // 添加用户消息
        let userMessage = AliceChatMessage(content: trimmedText, isUser: true)
        messages.append(userMessage)

        // 清空输入框
        inputText = ""

        // 清除之前的错误
        errorMessage = nil

        // 根據模型選擇使用不同的處理方式
        if isUsingOnDevice {
            sendMessageWithStreaming(trimmedText)
        } else if isUsingGrok {
            sendMessageToGrok(trimmedText)
        } else {
            sendMessageToRemote(trimmedText)
        }
    }

    // MARK: - Streaming Message (On-Device)
    private func sendMessageWithStreaming(_ text: String) {
        // 創建空的 AI 回應訊息（用於流式更新）
        let aiMessage = AliceChatMessage(content: "", isUser: false, isStreaming: true)
        messages.append(aiMessage)

        Task {
            do {
                let stream = aiRouter.streamChat(text)

                for try await chunk in stream {
                    await MainActor.run {
                        aiMessage.content += chunk
                    }
                }

                await MainActor.run {
                    aiMessage.isStreaming = false
                }
            } catch {
                await MainActor.run {
                    aiMessage.isStreaming = false
                    if aiMessage.content.isEmpty {
                        aiMessage.content = "抱歉，發生錯誤：\(error.localizedDescription)"
                    }
                    errorMessage = error.localizedDescription

                    #if DEBUG
                    print("[AliceView] Streaming error: \(error)")
                    #endif
                }
            }
        }
    }

    // MARK: - Grok Message (X.AI API)
    private func sendMessageToGrok(_ text: String) {
        // 創建空的 AI 回應訊息（用於流式更新）
        let aiMessage = AliceChatMessage(content: "", isUser: false, isStreaming: true)
        messages.append(aiMessage)

        Task {
            do {
                let stream = xaiService.streamChat(text)

                for try await chunk in stream {
                    await MainActor.run {
                        aiMessage.content += chunk
                    }
                }

                await MainActor.run {
                    aiMessage.isStreaming = false
                }
            } catch {
                await MainActor.run {
                    aiMessage.isStreaming = false
                    if aiMessage.content.isEmpty {
                        aiMessage.content = "抱歉，發生錯誤：\(error.localizedDescription)"
                    }
                    errorMessage = error.localizedDescription

                    #if DEBUG
                    print("[AliceView] Grok streaming error: \(error)")
                    #endif
                }
            }
        }
    }

    // MARK: - Remote Message (Cloud API)
    private func sendMessageToRemote(_ text: String) {
        isWaitingForResponse = true

        Task {
            do {
                // 构建对话历史
                let chatMessages = messages.map { msg in
                    AIChatMessage(
                        role: msg.isUser ? "user" : "assistant",
                        content: msg.content
                    )
                }

                // 调用 API
                let response = try await aliceService.sendMessage(
                    messages: chatMessages,
                    model: selectedModel
                )

                await MainActor.run {
                    isWaitingForResponse = false

                    // 添加 AI 响应
                    let aiMessage = AliceChatMessage(content: response, isUser: false)
                    messages.append(aiMessage)
                }
            } catch {
                await MainActor.run {
                    isWaitingForResponse = false
                    errorMessage = error.localizedDescription

                    // 显示错误消息
                    let errorMsg = AliceChatMessage(
                        content: "抱歉，我遇到了一个错误：\(error.localizedDescription)\n\n请稍后重试。",
                        isUser: false
                    )
                    messages.append(errorMsg)

                    #if DEBUG
                    print("[AliceView] Error: \(error)")
                    #endif
                }
            }
        }
    }

    // MARK: - Clear Chat
    private func clearChat() {
        messages.removeAll()
        aiRouter.resetChatSession()
        xaiService.resetConversation()
    }

    // MARK: - 模型选择器弹窗
    private var modelSelectorModal: some View {
        ZStack {
            // 背景模糊遮罩（除了底部导航栏）
            VStack(spacing: 0) {
                Color.clear
                    .background(.ultraThinMaterial)
                    .ignoresSafeArea()

                // 底部导航栏区域保持清晰
                Color.clear
                    .frame(height: 95)
            }
            .onTapGesture {
                showModelSelector = false
            }

            // 模型选择器 - 使用结构化数据
            VStack {
                Spacer()
                    .frame(height: 140)

                VStack(spacing: 4) {
                    ForEach(aliceModels) { model in
                        ModelRowView(
                            model: model,
                            isSelected: model.name == selectedModel,
                            onSelect: {
                                selectedModel = model.name
                                showModelSelector = false
                            }
                        )
                    }
                }
                .padding(.vertical, 8)
                .frame(width: 280)
                .background(DesignTokens.surface)
                .cornerRadius(20)
                .shadow(color: Color(red: 0, green: 0, blue: 0, opacity: 0.15), radius: 12, x: 0, y: 4)

                Spacer()
            }
        }
    }

}

// MARK: - Alice Chat Message View Component
struct AliceChatMessageView: View {
    @Bindable var message: AliceChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer()
                // 用户消息气泡
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(DesignTokens.textPrimary)
                    .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
                    .background(DesignTokens.surface)
                    .cornerRadius(43)
                    .overlay(
                        RoundedRectangle(cornerRadius: 43)
                            .inset(by: 0.50)
                            .stroke(DesignTokens.borderColor, lineWidth: 0.50)
                    )
                    .frame(maxWidth: 249, alignment: .trailing)
            } else {
                // AI响应消息
                VStack(alignment: .leading, spacing: 8) {
                    if message.content.isEmpty && message.isStreaming {
                        // 流式載入中
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("思考中...")
                                .font(.system(size: 12))
                                .foregroundColor(DesignTokens.textSecondary)
                        }
                    } else {
                        Text(message.content)
                            .font(.system(size: 14))
                            .foregroundColor(DesignTokens.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        // 流式指示器
                        if message.isStreaming {
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { index in
                                    Circle()
                                        .fill(DesignTokens.accentColor)
                                        .frame(width: 4, height: 4)
                                        .opacity(0.6)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            }
        }
    }
}

// MARK: - Model Row Component
struct ModelRowView: View {
    let model: AliceModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 模型圖標
                if model.isGrok {
                    // X.AI Grok 圖標
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                } else if model.isOnDevice {
                    Image(systemName: "cpu")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.system(size: 16))
                        .foregroundColor(DesignTokens.textPrimary)

                    Text(model.description)
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignTokens.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? DesignTokens.tileBackground : Color.clear)
            .cornerRadius(12)
            .padding(.horizontal, 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Previews

#Preview("Alice - Default") {
    AliceView(currentPage: .constant(.alice))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("Alice - Dark Mode") {
    AliceView(currentPage: .constant(.alice))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}

// MARK: - Keyboard Dismissal Extension
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
