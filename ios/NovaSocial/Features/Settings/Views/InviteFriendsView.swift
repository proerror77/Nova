import SwiftUI

struct InviteFriendsView: View {
    @Binding var currentPage: AppPage
    @State private var searchText = ""

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        currentPage = .setting
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Text("Invite Friends")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.black)

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(Color.white)

                // 分隔线
                Rectangle()
                    .fill(Color(red: 0.74, green: 0.74, blue: 0.74))
                    .frame(height: 0.5)

                VStack(spacing: 20) {
                    // MARK: - 搜索栏
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                        TextField("Search people on Icered", text: $searchText)
                            .font(.system(size: 15))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(height: 32)
                    .background(Color(red: 0.89, green: 0.88, blue: 0.87))
                    .cornerRadius(32)
                    .padding(.horizontal, 12)
                    .padding(.top, 20)

                    // MARK: - 分享邀请链接按钮
                    Button(action: {
                        // TODO: 分享邀请链接
                    }) {
                        HStack(spacing: 24) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .foregroundColor(Color(red: 0.82, green: 0.11, blue: 0.26))

                            Text("Share invitation link")
                                .font(.system(size: 15))
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                            Spacer()
                        }
                        .padding(.horizontal, 37)
                        .padding(.vertical, 7)
                        .frame(height: 35)
                    }
                    .background(Color.white)
                    .cornerRadius(23)
                    .overlay(
                        RoundedRectangle(cornerRadius: 23)
                            .stroke(Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.5)
                    )
                    .padding(.horizontal, 12)

                    // MARK: - 剩余邀请次数
                    Text("You have 3 invitations left.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))
                        .padding(.top, 5)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
}

#Preview {
    InviteFriendsView(currentPage: .constant(.setting))
}
