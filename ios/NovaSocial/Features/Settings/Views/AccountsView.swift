import SwiftUI

struct AccountsView: View {
    @Binding var currentPage: AppPage

    var body: some View {
        ZStack {
            DesignTokens.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: {
                        currentPage = .setting
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(DesignTokens.text)
                    }

                    Spacer()

                    Text("Accounts")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(DesignTokens.text)

                    Spacer()

                    // 占位，保持标题居中
                    Color.clear
                        .frame(width: 20)
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 20)
                .background(DesignTokens.card)

                // 分隔线
                Rectangle()
                    .fill(DesignTokens.border)
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
                                    .foregroundColor(DesignTokens.accent)

                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(DesignTokens.card)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignTokens.border, lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, 20)

                        // MARK: - 说明文字
                        Text("Alias account is an anonymous account.\nOne person can have one alias.")
                            .font(.system(size: 12))
                            .foregroundColor(DesignTokens.text)
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
                                        .fill(DesignTokens.card)
                                        .frame(width: 56, height: 56)

                                    Circle()
                                        .fill(DesignTokens.placeholder)
                                        .frame(width: 54, height: 54)
                                }

                                // 账户信息
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Account_one")
                                        .font(.system(size: 19, weight: .medium))
                                        .foregroundColor(DesignTokens.text)

                                    Text("Primary account")
                                        .font(.system(size: 15))
                                        .foregroundColor(DesignTokens.textLight)
                                }

                                Spacer()

                                // 右箭头
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(DesignTokens.textLight)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }
                        .background(DesignTokens.card)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DesignTokens.border, lineWidth: 0.5)
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
