import SwiftUI

/// 文字转图片视图 - Text to Image
struct WriteView: View {
    @Binding var showWrite: Bool
    var currentPage: Binding<AppPage>? = nil
    @State private var textContent: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            // 背景色
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                topNavigationBar

                Spacer()
                    .frame(height: 30)

                // MARK: - 文本输入框
                ZStack {
                    // 边框容器
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 323.w, height: 564.h)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 1)
                        )

                    // TextField 多行文本输入 - 自动换行，整体居中
                    TextField(
                        "",
                        text: $textContent,
                        prompt: Text("Write something...")
                            .font(.system(size: 25, weight: .medium))
                            .italic()
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53)),
                        axis: .vertical
                    )
                    .font(.system(size: 25, weight: .medium))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.leading)
                    .focused($isTextFieldFocused)
                    .frame(width: 260.w)
                    .lineLimit(1...20)
                }

                Spacer()

                // MARK: - 底部按钮
                Button(action: {
                    // TODO: 实现文字转图片功能
                    #if DEBUG
                    print("Text to Image tapped with content: \(textContent)")
                    #endif
                }) {
                    Text("Image")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(width: 343.w, height: 46.h)
                .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                .cornerRadius(31.50)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .ignoresSafeArea(.keyboard)
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    // MARK: - Top Navigation Bar
    private var topNavigationBar: some View {
        HStack {
            // 关闭按钮
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
            Text("Text to Image")
                .font(.system(size: 20, weight: .bold))
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

// MARK: - Previews

#Preview("Text to Image") {
    WriteView(showWrite: .constant(true))
        .environmentObject(AuthenticationManager.shared)
}
