import SwiftUI

struct InviteFriendsView: View {
    @Binding var currentPage: AppPage
    @State private var searchText = ""

    var body: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        currentPage = .setting
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(DesignTokens.textPrimary)
                    }

                    Spacer()

                    Text(LocalizedStringKey("Invite_Friends_Title"))
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(DesignTokens.surface)

                // 分隔线
                Rectangle()
                    .fill(DesignTokens.borderColor)
                    .frame(height: 0.5)

                VStack(spacing: 20) {
                    // MARK: - 搜索栏
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(DesignTokens.textSecondary)

                        TextField(LocalizedStringKey("Search_people_on_Icered"), text: $searchText)
                            .font(.system(size: 15))
                            .foregroundColor(.black)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(height: 32)
                    .background(DesignTokens.tileBackground)
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
                                .foregroundColor(DesignTokens.accentColor)

	                            Text(LocalizedStringKey("Share_invitation_link"))
                                .font(.system(size: 15))
                                .foregroundColor(DesignTokens.textPrimary)

                            Spacer()
                        }
                        .padding(.horizontal, 37)
                        .padding(.vertical, 7)
                        .frame(height: 35)
                    }
	                    .background(DesignTokens.surface)
                    .cornerRadius(23)
                    .overlay(
                        RoundedRectangle(cornerRadius: 23)
	                            .stroke(DesignTokens.borderColor, lineWidth: 0.5)
                    )
                    .padding(.horizontal, 12)

                    // MARK: - 剩余邀请次数
	                    Text(LocalizedStringKey("Invitations_left"))
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textPrimary)
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
