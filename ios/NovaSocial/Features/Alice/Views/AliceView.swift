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

    // MARK: - Keyboard State
    @State private var keyboardHeight: CGFloat = 0

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
            displayName: "Alice",  // UI 显示
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
        GeometryReader { geometry in
            ZStack {
                // 背景
                Color.white
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // MARK: - 顶部导航栏（绝对固定）
                    VStack(spacing: 0) {
                        Spacer()

                        HStack {
                            Spacer()

                            // 模型名稱（中间）
                            Text(aliceModels.first { $0.name == selectedModel }?.displayName ?? "alice")
                                .font(Font.custom("SFProDisplay-Semibold", size: 18.f))
                                .foregroundColor(DesignTokens.textPrimary)
                                .lineLimit(1)

                            Spacer()
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
                    .background(DesignTokens.surface)

                    // MARK: - 聊天消息区域
                    ZStack {
                        Color.white

                        if messages.isEmpty {
                            // 空状态 - 显示中间图标
                            VStack {
                                Spacer()

                                HStack(alignment: .center, spacing: 0) {
                                    Spacer()

                                    Image("alice-center-icon")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 120, height: 120)

                                    Spacer()
                                }

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
                                .onChange(of: messages.last?.content) { _, _ in
                                    if let lastMessage = messages.last, lastMessage.isStreaming {
                                        withAnimation(.easeOut(duration: 0.1)) {
                                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Spacer()
                        .frame(minHeight: 0)
                }
                .ignoresSafeArea(edges: .top)

                // MARK: - 底部输入区域（浮动在最上层）
                VStack {
                    Spacer()

                    VStack(spacing: 10.h) {
                        // 输入框
                        HStack(alignment: .center, spacing: 10.s) {
                            Image(systemName: "plus")
                                .font(.system(size: 16.f))
                                .foregroundColor(DesignTokens.textPrimary)
                                .frame(width: 24.s, height: 24.s)

                            TextField("Ask any questions", text: $inputText)
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .tracking(0.24)
                                .foregroundColor(DesignTokens.textSecondary)
                                .submitLabel(.send)
                                .onSubmit {
                                    sendMessage()
                                }

                            Spacer()

                            if !inputText.isEmpty {
                                Button(action: sendMessage) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 0.87, green: 0.11, blue: 0.26))
                                            .frame(width: 30.s, height: 30.s)

                                        Image(systemName: "arrow.up")
                                            .font(.system(size: 14.f, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                            } else {
                                // Voice Mode Button
                                Button(action: {
                                    showVoiceChat = true
                                }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 0.87, green: 0.11, blue: 0.26))
                                            .frame(width: 30.s, height: 30.s)

                                        Image(systemName: "waveform")
                                            .font(.system(size: 14.f, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16.w)
                        .padding(.vertical, 12.h)
                        .frame(width: 343.w, height: 54.h)
                        .background(DesignTokens.surface)
                        .cornerRadius(45.s)
                        .overlay(
                            RoundedRectangle(cornerRadius: 45.s)
                                .inset(by: 0.20)
                                .stroke(DesignTokens.borderColor, lineWidth: 0.40)
                        )
                        .padding(.horizontal, 16.w)
                    }
                    .padding(.top, 10.h)
                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 10 : 100.h)
                    .background(Color.white)
                    .animation(.easeOut(duration: 0.25), value: keyboardHeight)
                }
            }
        }
        .overlay(alignment: .bottom) {
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
        .overlay(alignment: .bottom) {
            // MARK: - 底部导航栏（覆盖在内容上方）
            BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions, showNewPost: $showNewPost)
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .onAppear {
            subscribeToKeyboardEvents()
        }
        .onDisappear {
            unsubscribeFromKeyboardEvents()
        }
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
                    if let xaiError = error as? XAIError {
                        if xaiError.isQuotaError {
                            displayMessage = "AI 服務配額已用完，請稍後再試。\n\n此錯誤通常是暫時的，請稍等幾分鐘後重試。"
                        } else if case .authError(let message) = xaiError {
                            displayMessage = "🔐 \(message)\n\n請先登入您的帳號以使用 AI 聊天功能。"
                        } else {
                            displayMessage = "抱歉，發生錯誤：\(error.localizedDescription)"
                        }
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

    // MARK: - Keyboard Handling

    private func subscribeToKeyboardEvents() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardHeight = keyboardFrame.height
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            keyboardHeight = 0
        }
    }

    private func unsubscribeFromKeyboardEvents() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
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
