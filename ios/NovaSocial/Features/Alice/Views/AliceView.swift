import SwiftUI

// MARK: - Alice Model Data Structure
struct AliceModel: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let isSelected: Bool
}

// MARK: - Alice Chat Message Data Structure
struct AliceChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp: Date = Date()
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
    @State private var selectedModel = "gpt-4o-all"
    
    // MARK: - Voice Chat States
    @State private var showVoiceChat = false

    // MARK: - Chat States
    @State private var messages: [AliceChatMessage] = []
    @State private var inputText = ""
    @State private var isWaitingForResponse = false
    @State private var errorMessage: String?

    // MARK: - AI Service
    private let aliceService = AliceService.shared

    // MARK: - Model Data
    private let aliceModels: [AliceModel] = [
        AliceModel(name: "gpt-4o-all", description: "Most capable model", isSelected: true),
        AliceModel(name: "gpt-4o", description: "GPT-4 optimized", isSelected: false),
        AliceModel(name: "gpt-4", description: "GPT-4 standard", isSelected: false),
        AliceModel(name: "gpt-3.5-turbo", description: "Fast and efficient", isSelected: false)
    ]

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
        // TODO: Re-enable when VoiceChatView is added to project
        // .fullScreenCover(isPresented: $showVoiceChat) {
        //     VoiceChatView(isPresented: $showVoiceChat)
        // }
        .onChange(of: selectedImage) { oldValue, newValue in
            // 选择/拍摄照片后，自动跳转到NewPostView
            if newValue != nil {
                showNewPost = true
            }
        }
    }

    // MARK: - Alice 主内容
    private var aliceContent: some View {
        ZStack {
            // 背景色
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack(spacing: 5) {
                    Text(selectedModel)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(DesignTokens.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(DesignTokens.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(DesignTokens.surface)
                .onTapGesture {
                    showModelSelector.toggle()
                }

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
                .padding(.bottom, -25)

                // MARK: - 底部导航栏
                BottomTabBar(currentPage: $currentPage, showPhotoOptions: $showPhotoOptions)
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

        // 显示等待状态
        isWaitingForResponse = true

        // 调用真实的 AI API
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
    let message: AliceChatMessage

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
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
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
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
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

// MARK: - Alice AI Service (Inline)
// 临时将服务代码放在这里，避免添加新文件到项目

@Observable
final class AliceService {
    static let shared = AliceService()

    private let baseURL: String
    private let apiKey: String

    private let apiClient = APIClient.shared

    private init() {
        // API requests are proxied through our backend
        // Backend handles third-party AI provider authentication
        self.baseURL = APIConfig.AI.baseURL
        self.apiKey = ""  // Not used - backend manages API keys
    }

    @MainActor
    func sendMessage(
        messages: [AIChatMessage],
        model: String = "gpt-4o-all"
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw AliceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Use user's JWT token for authentication with our backend proxy
        // Backend will then authenticate with the AI provider using server-side API keys
        if let token = apiClient.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: messages
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AliceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(AIErrorResponse.self, from: data) {
                throw AliceError.apiError(errorResponse.error.message)
            }
            throw AliceError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let completionResponse = try decoder.decode(ChatCompletionResponse.self, from: data)

        guard let firstChoice = completionResponse.choices.first else {
            throw AliceError.emptyResponse
        }

        return firstChoice.message.content
    }
}

// MARK: - AI Data Models

struct AIChatMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Codable, Sendable {
    let model: String
    let messages: [AIChatMessage]
}

struct ChatCompletionResponse: Codable, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]

    struct Choice: Codable, Sendable {
        let index: Int
        let message: AIChatMessage
        let finishReason: String?
    }
}

struct AIErrorResponse: Codable, Sendable {
    let error: ErrorDetail

    struct ErrorDetail: Codable, Sendable {
        let message: String
        let type: String?
        let code: String?
    }
}

enum AliceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "API error: \(message)"
        case .emptyResponse:
            return "Empty response from server"
        }
    }
}

#Preview {
    AliceView(currentPage: .constant(.alice))
}

// MARK: - Keyboard Dismissal Extension
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
