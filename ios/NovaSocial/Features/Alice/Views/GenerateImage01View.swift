import SwiftUI

// MARK: - 消息类型
enum MessageType: Hashable {
    case userPrompt(String)
    case aiResponse
}

struct GenerateImage01View: View {
    @Binding var showGenerateImage: Bool
    @State private var promptText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var messages: [MessageType] = []
    @State private var isGenerating: Bool = false
    @State private var showFeatureComingSoon: Bool = false

    var body: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    // 返回按钮
                    Button(action: {
                        showGenerateImage = false
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.black)
                    }
                    .accessibilityLabel("Close")
                    .frame(width: 24, height: 24)

                    Spacer()

                    // 标题
                    Text("Create images")
                        .font(Font.custom("Helvetica Neue", size: 20).weight(.bold))
                        .foregroundColor(.black)

                    Spacer()

                    // 占位 - 保持标题居中
                    Color.clear
                        .frame(width: 24, height: 24)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(Color.white)

                Divider()

                // MARK: - 消息列表区域
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            switch message {
                            case .userPrompt(let text):
                                // 用户消息气泡
                                HStack {
                                    Spacer()
                                    HStack(spacing: 8) {
                                        Text(text)
                                            .font(Font.custom("Helvetica Neue", size: 14))
                                            .foregroundColor(.black)
                                    }
                                    .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
                                    .background(.white)
                                    .cornerRadius(43)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 43)
                                            .inset(by: 0.50)
                                            .stroke(Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.50)
                                    )
                                    .padding(.trailing, 16)
                                }

                            case .aiResponse:
                                // AI 生成的图片响应
                                aiResponseView
                            }
                        }
                    }
                    .padding(.top, 16)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

                // MARK: - 底部输入区域
                VStack(spacing: 0) {
                    Divider()
                        .frame(height: 0.5)
                        .background(Color(red: 0.74, green: 0.74, blue: 0.74))

                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))

                                TextField("Describe the image to generate", text: $promptText)
                                    .font(Font.custom("Helvetica Neue", size: 16))
                                    .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                                    .focused($isInputFocused)
                                    .onSubmit {
                                        sendMessage()
                                    }
                            }
                            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .background(Color(red: 0.53, green: 0.53, blue: 0.53).opacity(0.20))
                            .cornerRadius(26)

                            // 发送按钮
                            Button(action: {
                                sendMessage()
                            }) {
                                Circle()
                                    .fill(promptText.isEmpty ? Color.gray : Color(red: 0.91, green: 0.18, blue: 0.30))
                                    .frame(width: 33, height: 33)
                                    .overlay(
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.white)
                                    )
                            }
                            .accessibilityLabel("Send")
                            .disabled(promptText.isEmpty)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    }
                    .background(Color.white)
                    .background(
                        Color.white
                            .ignoresSafeArea(edges: .bottom)
                    )
                }
            }
        }
        .alert("Feature Coming Soon", isPresented: $showFeatureComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("AI image generation is currently under development. This feature will be available once the backend API is connected.")
        }
    }

    // MARK: - AI 响应视图
    private var aiResponseView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Alice 标题和标签
            HStack(spacing: 8) {
                Text("Alice")
                    .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                    .foregroundColor(.black)

                HStack(spacing: 6) {
                    Text("AI agent")
                        .font(Font.custom("Helvetica Neue", size: 10))
                        .lineSpacing(14.55)
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .inset(by: 0.50)
                        .stroke(.black, lineWidth: 0.50)
                )
            }
            .padding(.leading, 16)

            // Loading 或 生成完成文本
            Text(isGenerating ? "Loading..." : "Generated 2 images")
                .font(Font.custom("Helvetica Neue", size: 12))
                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                .padding(.leading, 16)

            // 图片横向滚动区域
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    // 图片 1
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 198, height: 285)
                        .background(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                        .cornerRadius(6)
                        .accessibilityLabel("Generated image 1")

                    // 图片 2
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 197, height: 285)
                        .background(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                        .cornerRadius(6)
                        .accessibilityLabel("Generated image 2")
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    // MARK: - 发送消息函数
    private func sendMessage() {
        guard !promptText.isEmpty else { return }

        // 添加用户消息到列表
        messages.append(.userPrompt(promptText))

        // 清空输入框
        promptText = ""

        // 取消输入焦点（收起键盘）
        isInputFocused = false

        // 显示功能尚未可用的提示
        showFeatureComingSoon = true

        // 模拟 AI 生成过程（仅用于演示UI）
        isGenerating = true

        // 延迟 1.5 秒后添加 AI 响应（占位符）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // TODO: 替换为真实的 AI 图片生成 API 调用
            // try await AIImageService.generate(prompt: userPrompt)
            messages.append(.aiResponse)
            isGenerating = false
        }
    }
}

#Preview {
    GenerateImage01View(showGenerateImage: .constant(true))
}
