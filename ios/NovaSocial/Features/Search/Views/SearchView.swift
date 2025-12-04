import SwiftUI

struct SearchView: View {
    @Binding var showSearch: Bool
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            // MARK: - 背景色
            Color(red: 0.97, green: 0.96, blue: 0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部搜索区域
                VStack(spacing: 0) {
                    // 搜索栏和取消按钮
                    HStack(spacing: 10) {
                        // 搜索框
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15))
                                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                            TextField("Search", text: $searchText)
                                .font(Font.custom("Helvetica Neue", size: 15))
                                .foregroundColor(.black)
                                .focused($isSearchFocused)
                        }
                        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .frame(height: 32)
                        .background(Color(red: 0.89, green: 0.88, blue: 0.87))
                        .cornerRadius(37)

                        // 取消按钮
                        Button(action: {
                            showSearch = false
                        }) {
                            Text("Cancel")
                                .font(Font.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.black)
                        }
                        .frame(width: 44)
                    }
                    .frame(height: DesignTokens.topBarHeight)
                    .padding(.horizontal, 16)
                    .background(Color.white)

                    // 分隔线
                    Divider()
                        .frame(height: 0.5)
                        .background(Color(red: 0.74, green: 0.74, blue: 0.74))
                }

                // MARK: - 搜索结果区域
                ScrollView {
                    VStack(spacing: 16) {
                        // 搜索结果将显示在这里
                        if searchText.isEmpty {
                            // 空状态
                            Text("")
                                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))
                                .padding(.top, 100)
                        } else {
                            // 搜索结果
                            ForEach(0..<5, id: \.self) { _ in
                                SearchResultItem()
                            }
                        }
                    }
                    .padding(.top, 16)
                }

                Spacer()
            }
        }
        .onAppear {
            // 自动聚焦搜索框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }
}

// MARK: - 搜索结果项组件（占位）
struct SearchResultItem: View {
    var body: some View {
        HStack(spacing: 12) {
            // 头像
            Circle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(width: 40, height: 40)

            // 内容
            VStack(alignment: .leading, spacing: 4) {
                Text("Search Result")
                    .font(Font.custom("Helvetica Neue", size: 15).weight(.semibold))
                    .foregroundColor(.black)

                Text("Description")
                    .font(Font.custom("Helvetica Neue", size: 13))
                    .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white)
    }
}

#Preview {
    SearchView(showSearch: .constant(true))
}
