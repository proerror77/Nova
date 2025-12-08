import SwiftUI

struct AccountsView: View {
    @Binding var currentPage: AppPage

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
                            .frame(width: 24, height: 24)
                            .foregroundColor(DesignTokens.textPrimary)
                    }

                    Spacer()

                    Text("Accounts")
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

                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: - Create alias account 按钮
                        Button(action: {
                            // TODO: 创建别名账户
                        }) {
                            HStack {
                                Text("Create alias account")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(DesignTokens.accentColor)

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(DesignTokens.surface)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignTokens.borderColor, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 20)

                        // MARK: - 说明文字
                        Text("Alias account is an anonymous account.\nOne person can have one alias.")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.textPrimary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)

                        // MARK: - Account_one 账户卡片
                        Button(action: {
                            // TODO: 切换到此账户
                        }) {
                            HStack(spacing: 16) {
                                // 头像
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 56, height: 56)

                                    Circle()
                                        .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                                        .frame(width: 54, height: 54)
                                }

                                // 账户信息
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Account_one")
                                        .font(.system(size: 19, weight: .medium))
                                        .foregroundColor(DesignTokens.textPrimary)

                                    Text("Primary account")
                                        .font(.system(size: 15))
                                        .foregroundColor(DesignTokens.textSecondary)
                                }

                                Spacer()

                                // 右箭头
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignTokens.textMuted)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(DesignTokens.surface)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignTokens.borderColor, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    }
                }

                Spacer()
            }
        }
    }
}

#Preview {
    AccountsView(currentPage: .constant(.setting))
}
