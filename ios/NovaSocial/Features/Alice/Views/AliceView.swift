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
    var toolCallName: String?
    var isToolExecuting: Bool

    init(content: String, isUser: Bool, isStreaming: Bool = false, toolCallName: String? = nil) {
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.isStreaming = isStreaming
        self.toolCallName = toolCallName
        self.isToolExecuting = false
    }
}

struct AliceView: View {
    @Binding var currentPage: AppPage
    @State private var showPhotoOptions = false
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
    // UI 显示 "alice + 版本"，实际功能通过 name 判断使用哪个 API
    private var aliceModels: [AliceModel] {
        var models: [AliceModel] = []

        // Grok 4 - X.AI 最新模型（推薦）
        models.append(AliceModel(
            name: "grok-4",  // 功能：使用 Grok API
            displayName: "alice AI",  // UI 显示
            description: "最新模型 ⭐️ 推薦"
        ))

        // 本地模型（如果可用）
        if aiRouter.isOnDeviceAvailable {
            models.append(AliceModel(
                name: "on-device",  // 功能：使用本地模型
                displayName: "alice Local",  // UI 显示
                description: "隱私優先・離線可用",
                isOnDevice: true
            ))
        }

        // 遠端模型（Nova 後端）
        models.append(contentsOf: [
            AliceModel(name: "gpt-4o-all", displayName: "alice Pro", description: "最強大模型"),
            AliceModel(name: "gpt-4o", displayName: "alice Plus", description: "進階優化"),
            AliceModel(name: "gpt-4", displayName: "alice 4.0", description: "標準版本"),
            AliceModel(name: "gpt-3.5-turbo", displayName: "alice Fast", description: "快速高效")
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
        // MARK: - Action Button Voice Mode Auto-Open
        .onAppear {
            // Check if voice mode was requested via Action Button
            checkForVoiceModeRequest()
        }
        .onChange(of: AppCoordinator.shared.shouldOpenVoiceMode) { _, newValue in
            // Auto-open voice chat when triggered by Action Button intent
            if newValue {
                AppCoordinator.shared.shouldOpenVoiceMode = false
                #if DEBUG
                print("[AliceView] Auto-opening voice chat from Action Button")
                #endif
                // Small delay to ensure view is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showVoiceChat = true
                }
            }
        }
    }

    /// Check if voice mode was requested (for initial load)
    private func checkForVoiceModeRequest() {
        if AppCoordinator.shared.shouldOpenVoiceMode {
            AppCoordinator.shared.shouldOpenVoiceMode = false
            #if DEBUG
            print("[AliceView] Processing pending voice mode request on appear")
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showVoiceChat = true
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
                VStack(spacing: 0) {
                    Spacer()
                    
                    HStack {
                        // 清除對話按鈕（左侧）- 固定宽度以平衡右侧
                        Button(action: clearChat) {
                            Image(systemName: "trash")
                                .font(.system(size: 18.f))
                                .foregroundColor(messages.isEmpty ? DesignTokens.textSecondary : DesignTokens.textPrimary)
                        }
                        .disabled(messages.isEmpty)
                        .frame(width: 34.w, height: 18.h)
                        .padding(.leading, 16.w)

                        Spacer()

                        // 模型名稱（中间）
                        Text(aliceModels.first { $0.name == selectedModel }?.displayName ?? "alice")
                            .font(Font.custom("SFProDisplay-Semibold", size: 18.f))
                            .foregroundColor(DesignTokens.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        // 右侧占位符保持对称
                        Color.clear
                            .frame(width: 34.w, height: 18.h)
                            .padding(.trailing, 16.w)
                    }
                    .frame(height: 24.h)
                    
                    Spacer()
                        .frame(height: 18.h)
                    
                    Rectangle()
                        .fill(DesignTokens.borderColor)
                        .frame(maxWidth: .infinity)
                        .frame(height: 0.5)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 98.h)

                // MARK: - 聊天消息区域
                if messages.isEmpty {
                    // 空状态 - 显示中间图标和建议问题
                    ScrollView {
                        VStack(spacing: 24) {
                            Spacer()
                                .frame(height: 40)

                            // Alice 图标
                            Image("alice-center-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)

                            // 欢迎文字
                            VStack(spacing: 8) {
                                Text("嗨！我是 Alice")
                                    .font(Font.custom("SFProDisplay-Semibold", size: 20.f))
                                    .foregroundColor(DesignTokens.textPrimary)

                                Text("有什麼我可以幫你的嗎？")
                                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                                    .foregroundColor(DesignTokens.textSecondary)
                            }

                            // 建議問題
                            VStack(spacing: 12) {
                                suggestionButton("今天有什麼熱門話題？", icon: "flame.fill")
                                suggestionButton("幫我寫一篇貼文", icon: "pencil.line")
                                suggestionButton("推薦一些有趣的內容", icon: "sparkles")
                                suggestionButton("解釋一下這個功能", icon: "questionmark.circle")
                            }
                            .padding(.horizontal, 24)

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
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
                                    AliceStreamingMessageView(message: message)
                                        .id(message.id)
                                }

                                if isWaitingForResponse {
                                    HStack {
                                        StreamingIndicator(
                                            style: .thinking,
                                            color: DesignTokens.accentColor,
                                            size: 8
                                        )
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
                        // Auto-scroll when streaming content updates
                        .onChange(of: messages.last?.content) { _, _ in
                            if let lastMessage = messages.last, lastMessage.isStreaming {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }

                // MARK: - 底部固定区域（按钮组 + 输入框）
                VStack(spacing: 10.h) {
                    // 功能按钮组
                    HStack(spacing: 10.s) {
                        // Get Super alice 按钮
                        HStack(spacing: 10.s) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16.f))
                                .foregroundColor(DesignTokens.textPrimary)
                            Text("Get Super alice")
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .tracking(0.24)
                                .foregroundColor(DesignTokens.textPrimary)
                        }
                        .padding(EdgeInsets(top: 10.h, leading: 16.w, bottom: 10.h, trailing: 16.w))
                        .background(DesignTokens.surface)
                        .cornerRadius(21.s)
                        .overlay(
                            RoundedRectangle(cornerRadius: 21.s)
                                .inset(by: 0.20)
                                .stroke(DesignTokens.borderColor, lineWidth: 0.20)
                        )

                        // Voice Mode 按钮
                        Button(action: {
                            showVoiceChat = true
                        }) {
                            HStack(spacing: 10.s) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 16.f))
                                    .foregroundColor(DesignTokens.textPrimary)
                                Text("Voice Mode")
                                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                    .tracking(0.24)
                                    .foregroundColor(DesignTokens.textPrimary)
                            }
                            .padding(EdgeInsets(top: 10.h, leading: 16.w, bottom: 10.h, trailing: 16.w))
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.86, green: 0.56, blue: 0.84).opacity(0.76),
                                        Color(red: 0.73, green: 0.58, blue: 0.87).opacity(0.52),
                                        Color(red: 0.45, green: 0.79, blue: 0.91).opacity(0.60)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(21.s)
                            .overlay(
                                RoundedRectangle(cornerRadius: 21.s)
                                    .inset(by: 0.20)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.82, green: 0.33, blue: 0.80),
                                                Color(red: 0.38, green: 0.71, blue: 0.84)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 0.20
                                    )
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16.w)

                    // 输入框区域
                    HStack(spacing: 10.s) {
                        Image(systemName: "plus")
                            .font(.system(size: 16.f))
                            .foregroundColor(DesignTokens.textPrimary)

                        TextField("Ask any questions", text: $inputText)
                            .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                            .tracking(0.24)
                            .foregroundColor(DesignTokens.textSecondary)
                            .submitLabel(.send)
                            .onSubmit {
                                sendMessage()
                            }

                        if !inputText.isEmpty {
                            Button(action: sendMessage) {
                                Image("Send-Icon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 24.s, height: 24.s)
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 12.h, leading: 16.w, bottom: 12.h, trailing: 16.w))
                    .frame(maxWidth: .infinity)
                    .background(DesignTokens.surface)
                    .cornerRadius(45.s)
                    .overlay(
                        RoundedRectangle(cornerRadius: 45.s)
                            .inset(by: 0.20)
                            .stroke(DesignTokens.borderColor, lineWidth: 0.20)
                    )
                    .padding(.horizontal, 16.w)
                }
                .padding(.bottom, 82.h)  // 距离手机底部边缘 82pt
            }
            .background(DesignTokens.surface)
            .ignoresSafeArea(edges: .top)  // 统一处理顶部安全区域
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .ignoresSafeArea(edges: .bottom)

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

    // MARK: - Streaming Message (On-Device with Tools)
    private func sendMessageWithStreaming(_ text: String) {
        // 創建空的 AI 回應訊息（用於流式更新）
        let aiMessage = AliceChatMessage(content: "", isUser: false, isStreaming: true)
        messages.append(aiMessage)

        Task {
            do {
                // Use tool-enabled streaming for richer responses
                let stream = aiRouter.streamChatWithTools(text)

                for try await chunk in stream {
                    await MainActor.run {
                        // Check if this is a tool call indicator
                        if chunk.hasPrefix("[TOOL:") && chunk.hasSuffix("]") {
                            let toolName = String(chunk.dropFirst(6).dropLast(1))
                            aiMessage.toolCallName = toolName
                            aiMessage.isToolExecuting = true
                        } else if chunk == "[TOOL_COMPLETE]" {
                            aiMessage.isToolExecuting = false
                        } else {
                            aiMessage.content += chunk
                        }
                    }
                }

                await MainActor.run {
                    aiMessage.isStreaming = false
                    aiMessage.isToolExecuting = false
                }
            } catch {
                await MainActor.run {
                    aiMessage.isStreaming = false
                    aiMessage.isToolExecuting = false
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

                    // Check for quota error and provide helpful message
                    let displayMessage: String
                    if let xaiError = error as? XAIError, xaiError.isQuotaError {
                        displayMessage = "AI 服務配額已用完，請稍後再試。\n\n此錯誤通常是暫時的，請稍等幾分鐘後重試。"
                    } else {
                        displayMessage = "抱歉，發生錯誤：\(error.localizedDescription)"
                    }

                    if aiMessage.content.isEmpty {
                        aiMessage.content = displayMessage
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
        // 創建空的 AI 回應訊息（用於流式更新）
        let aiMessage = AliceChatMessage(content: "", isUser: false, isStreaming: true)
        messages.append(aiMessage)

        Task {
            do {
                // 构建对话历史
                let chatMessages = messages.filter { !$0.isStreaming }.map { msg in
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
                    aiMessage.content = response
                    aiMessage.isStreaming = false
                }
            } catch {
                await MainActor.run {
                    aiMessage.isStreaming = false

                    // 提供更友好的錯誤訊息
                    let displayMessage: String
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .decodingError:
                            displayMessage = "😅 Alice 正在學習中，回應格式有點問題。\n\n請再試一次，或者換個方式問問看！"
                        case .serviceUnavailable:
                            displayMessage = "🔧 Alice 正在維護中，請稍後再試。\n\n通常幾分鐘後就會恢復正常。"
                        case .timeout:
                            displayMessage = "⏱️ 回應時間太長了。\n\n請檢查網路連接後重試。"
                        case .unauthorized:
                            displayMessage = "🔐 需要重新登入。\n\n請退出後重新登入。"
                        case .serverError(let code, _):
                            displayMessage = "❌ 服務器錯誤 (\(code))\n\n請稍後重試，或聯繫客服。"
                        default:
                            displayMessage = "😕 發生了一些問題。\n\n\(error.localizedDescription)\n\n請稍後重試。"
                        }
                    } else {
                        displayMessage = "😕 發生了一些問題。\n\n請檢查網路連接後重試。"
                    }

                    aiMessage.content = displayMessage
                    errorMessage = error.localizedDescription

                    #if DEBUG
                    print("[AliceView] Error: \(error)")
                    if let apiError = error as? APIError {
                        print("[AliceView] API Error type: \(apiError)")
                    }
                    #endif
                }
            }
        }
    }

    // MARK: - Clear Chat
    private func clearChat() {
        messages.removeAll()
        aiRouter.resetChatSession()
        aiRouter.resetToolSession()
        xaiService.resetConversation()
    }

    // MARK: - Suggestion Button
    private func suggestionButton(_ text: String, icon: String) -> some View {
        Button(action: {
            inputText = text
            sendMessage()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16.f))
                    .foregroundColor(DesignTokens.accentColor)

                Text(text)
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .foregroundColor(DesignTokens.textPrimary)
                    .multilineTextAlignment(.leading)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14.f))
                    .foregroundColor(DesignTokens.textSecondary)
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            .background(DesignTokens.surface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .inset(by: 0.5)
                    .stroke(DesignTokens.borderColor, lineWidth: 0.5)
            )
        }
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
