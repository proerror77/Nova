import SwiftUI

struct AddFriendsView: View {
    @Binding var currentPage: AppPage

    var body: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        currentPage = .message
                    }) {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 24)
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Text("Add friends")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)

                    Spacer()

                    // 占位空间，保持标题居中
                    Color.clear
                        .frame(width: 20, height: 20)
                }
                .frame(height: 56)
                .padding(.horizontal, 16)
                .background(Color.white)

                Divider()

                // MARK: - 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                    Text("Search")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                    Spacer()
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                .cornerRadius(32)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // MARK: - Icered contacts above 标题
                HStack {
                    Text("Icered contacts above")
                        .font(.system(size: 17.50, weight: .bold))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                // MARK: - 用户卡片
                HStack(spacing: 13) {
                    // 头像
                    Ellipse()
                        .foregroundColor(.clear)
                        .frame(width: 50, height: 50)
                        .background(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Bruce Li (you)")
                            .font(.system(size: 16, weight: .bold))
                            .lineSpacing(20)
                            .foregroundColor(.black)
                        Text("+86 199xxxx6164")
                            .font(.system(size: 11.50, weight: .medium))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.65, green: 0.65, blue: 0.65))
                    }

                    Spacer()

                    // 右箭头
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(Color.gray.opacity(0.5))
                }
                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .frame(width: 351, height: 67)
                .background(Color(red: 0.97, green: 0.96, blue: 0.96))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .inset(by: 0.50)
                        .stroke(Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.50)
                )
                .padding(.top, 12)

                // MARK: - Share invitation link 按钮
                Button(action: {
                    // TODO: 分享邀请链接
                }) {
                    HStack(spacing: 24) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                        Text("Share invitation link")
                            .font(.system(size: 15))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                        Spacer()
                    }
                    .padding(EdgeInsets(top: 7, leading: 37, bottom: 7, trailing: 37))
                    .frame(width: 351, height: 35)
                }
                .background(Color.white)
                .cornerRadius(23)
                .overlay(
                    RoundedRectangle(cornerRadius: 23)
                        .inset(by: 0.50)
                        .stroke(Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.50)
                )
                .padding(.top, 16)

                Spacer()
            }
        }
    }
}

#Preview {
    AddFriendsView(currentPage: .constant(.addFriends))
}
