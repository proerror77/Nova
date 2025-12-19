import SwiftUI

/// 账户切换弹窗组件
/// 显示主账户、添加匿名账户选项，以及账户中心入口
struct AccountSwitcherSheet: View {
    @Binding var isPresented: Bool

    // Actions
    var onAccountSelected: ((AccountType) -> Void)?
    var onAddAliasAccount: (() -> Void)?
    var onGoToAccountCenter: (() -> Void)?

    // 当前选中的账户
    @State private var selectedAccount: AccountType = .primary

    enum AccountType {
        case primary
        case alias
    }

    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isPresented = false
                    }
                }

            // 弹窗内容
            VStack {
                Spacer()

                sheetContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Sheet Content
    private var sheetContent: some View {
        VStack(spacing: 20) {
            // 顶部拖拽指示器
            dragIndicator

            // 账户列表
            accountListSection

            // 前往账户中心按钮
            goToAccountCenterButton

            // 底部 Logo
            logoSection
        }
        .padding(.top, 12)
        .padding(.bottom, 30)
        .padding(.horizontal, 26)
        .background(.white)
        .cornerRadius(10.5, corners: [.topLeft, .topRight])
    }

    // MARK: - Drag Indicator
    private var dragIndicator: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(width: 53.44, height: 6.68)
            .background(Color(red: 0.82, green: 0.11, blue: 0.26))
            .cornerRadius(3.34)
    }

    // MARK: - Account List Section
    private var accountListSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            // 主账户
            accountRow(
                avatarColor: Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50),
                avatarImage: "avatar_placeholder", // 可替换为实际头像
                title: "Account_one (Primary)",
                isSelected: selectedAccount == .primary,
                action: {
                    selectedAccount = .primary
                    onAccountSelected?(.primary)
                }
            )

            // 添加匿名账户
            addAliasAccountRow
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .overlay(
            RoundedRectangle(cornerRadius: 17.18)
                .stroke(Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.48)
        )
    }

    // MARK: - Account Row
    private func accountRow(
        avatarColor: Color,
        avatarImage: String?,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // 头像
                if let imageName = avatarImage, UIImage(named: imageName) != nil {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(avatarColor)
                        .frame(width: 40, height: 40)
                }

                // 账户名
                Text(title)
                    .font(.system(size: 13.36))
                    .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))

                Spacer()

                // 选中标记
                if isSelected {
                    Circle()
                        .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(Typography.bold12)
                                .foregroundColor(.white)
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Add Alias Account Row
    private var addAliasAccountRow: some View {
        Button(action: {
            onAddAliasAccount?()
        }) {
            HStack(spacing: 10) {
                // 加号图标
                ZStack {
                    Circle()
                        .fill(Color(red: 0.53, green: 0.53, blue: 0.54))
                        .frame(width: 40, height: 40)

                    Image(systemName: "plus")
                        .font(Typography.semibold18)
                        .foregroundColor(.white)
                }

                // 文字
                Text("Add an alias account (Anonymous)")
                    .font(.system(size: 13.36))
                    .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))

                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Go to Account Center Button
    private var goToAccountCenterButton: some View {
        Button(action: {
            onGoToAccountCenter?()
        }) {
            Text("Go to the Account center")
                .font(.system(size: 13.36))
                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 29.58)
                        .stroke(Color(red: 0.75, green: 0.75, blue: 0.75), lineWidth: 0.48)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logo Section
    private var logoSection: some View {
        Image("Logo-R")
            .resizable()
            .scaledToFit()
            .frame(height: 100)
            .padding(.top, 10)
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        AccountSwitcherSheet(
            isPresented: .constant(true),
            onAccountSelected: { account in
                print("Selected account: \(account)")
            },
            onAddAliasAccount: {
                print("Add alias account tapped")
            },
            onGoToAccountCenter: {
                print("Go to account center tapped")
            }
        )
    }
}
