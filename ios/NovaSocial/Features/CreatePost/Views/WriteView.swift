import SwiftUI

/// 写作视图 - 纯文字内容创作
struct WriteView: View {
    @Binding var showWrite: Bool
    var currentPage: Binding<AppPage>? = nil
    @State private var textContent: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            // 背景色
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                topNavigationBar

                Spacer()
                    .frame(height: 30)

                // MARK: - 文本输入框
                ZStack {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 323, height: 564)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 1)
                        )

                    // TextEditor with placeholder
                    VStack(spacing: 0) {
                        Spacer()

                        ZStack(alignment: .topLeading) {
                            if textContent.isEmpty {
                                Text("Write something...")
                                    .font(.system(size: 25, weight: .medium))
                                    .lineSpacing(20)
                                    .italic()
                                    .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                            }

                            TextEditor(text: $textContent)
                                .font(.system(size: 25, weight: .medium))
                                .lineSpacing(20)
                                .foregroundColor(.black)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .focused($isTextFieldFocused)
                        }
                        .frame(height: 60)

                        Spacer()
                    }
                    .frame(width: 303, height: 544)
                }

                Spacer()

                // MARK: - 底部按钮
                Button(action: {
                    // TODO: 实现文字转图片功能
                    #if DEBUG
                    print("Text to Image tapped with content: \(textContent)")
                    #endif
                }) {
                    HStack(spacing: 8) {
                        Text("Text to Image")
                            .font(Typography.semibold16)
                            .lineSpacing(20)
                            .foregroundColor(.white)
                    }
                    .padding(EdgeInsets(top: 20, leading: 153, bottom: 20, trailing: 153))
                    .frame(width: 343, height: 46)
                    .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                    .cornerRadius(31.50)
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            // 自动聚焦到文本框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        HStack {
            // 返回按钮
            Button(action: {
                if let currentPage = currentPage {
                    currentPage.wrappedValue = .home
                } else {
                    showWrite = false
                }
            }) {
                Image("Close-B")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }

            Spacer()

            // 标题
            Text("Write")
                .font(Typography.bold20)
                .foregroundColor(.black)

            Spacer()

            // 右侧占位（保持对称）
            Color.clear
                .frame(width: 24, height: 24)
        }
        .frame(height: DesignTokens.topBarHeight)
        .padding(.horizontal, 16)
        .background(.white)
    }
}

// MARK: - Preview

#Preview {
    WriteView(showWrite: .constant(true))
}
