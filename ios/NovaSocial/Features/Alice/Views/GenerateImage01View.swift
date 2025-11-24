import SwiftUI

struct GenerateImage01View: View {
    @Binding var showGenerateImage: Bool
    @State private var promptText: String = ""
    @State private var generatedImage: UIImage?
    @State private var isGenerating = false

    var body: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    // 关闭按钮
                    Button(action: {
                        showGenerateImage = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.black)
                    }
                    .frame(width: 24, height: 24)

                    Spacer()

                    // 标题
                    Text("Create an image with alice")
                        .font(Font.custom("Helvetica Neue", size: 18).weight(.medium))
                        .foregroundColor(.black)

                    Spacer()

                    // 占位 - 保持标题居中
                    Color.clear
                        .frame(width: 24, height: 24)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(Color.white)

                // 分隔线
                Divider()
                    .frame(height: 0.5)
                    .background(Color(red: 0.77, green: 0.77, blue: 0.77))

                Spacer()

                // MARK: - 图片展示区域
                ZStack {
                    // 占位背景
                    Rectangle()
                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                        .frame(height: 279)

                    // 生成的图片
                    if let image = generatedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 279)
                            .clipped()
                    }

                    // 加载指示器
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 279)

                Spacer()

                // MARK: - 底部输入区域
                VStack(spacing: 0) {
                    Divider()
                        .frame(height: 0.5)
                        .background(Color(red: 0.77, green: 0.77, blue: 0.77))

                    HStack(spacing: 10) {
                        // 键盘按钮
                        Button(action: {
                            // 显示/隐藏键盘
                        }) {
                            Image("keyboard-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                        }

                        // 输入框
                        HStack(spacing: 8) {
                            TextField("Describe the image to generate", text: $promptText)
                                .font(Font.custom("Helvetica Neue", size: 14))
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                            // 语音按钮
                            Button(action: {
                                // 语音输入功能
                            }) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                            }
                            .frame(width: 24, height: 24)
                        }
                        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 10))
                        .frame(height: 36)
                        .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                        .cornerRadius(56)

                        // 发送按钮
                        Button(action: {
                            generateImage()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.87, green: 0.11, blue: 0.26))
                                    .frame(width: 32, height: 32)

                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                        }
                        .disabled(promptText.isEmpty || isGenerating)
                        .opacity(promptText.isEmpty ? 0.5 : 1.0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .frame(height: 88)
                .background(Color.white)
            }
        }
    }

    // MARK: - 生成图片
    private func generateImage() {
        guard !promptText.isEmpty else { return }

        isGenerating = true

        // TODO: 调用 AI 图片生成 API
        // 这里是模拟延迟
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isGenerating = false
            // 生成完成后的处理
        }
    }
}

#Preview {
    GenerateImage01View(showGenerateImage: .constant(true))
}
