import SwiftUI

/// 名称显示类型
enum AccountDisplayType: Equatable {
    case primary    // 真实名称 (User)
    case alias      // 别名 (Dreamer)
}

/// 账户切换弹窗组件 - 用于选择 Profile 页显示的名称类型
struct AccountSwitcherSheet: View {
    @Binding var isPresented: Bool
    @Binding var selectedAccountType: AccountDisplayType
    @EnvironmentObject private var authManager: AuthenticationManager

    var body: some View {
        ZStack {
            // 半透明背景
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // 弹窗内容
            VStack {
                Spacer()

                VStack(spacing: 0) {
                    // 顶部拖拽指示条
                    Rectangle()
                        .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .frame(width: 56, height: 7)
                        .cornerRadius(3.5)
                        .padding(.top, 12)
                        .padding(.bottom, 16)

                    // 标题
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preferred name display")
                            .font(Font.custom("SFProDisplay-Medium", size: 20.f))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))

                        Text("Choose how your name will appear when posting")
                            .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                            .foregroundColor(Color(red: 0.68, green: 0.68, blue: 0.68))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                    // 分隔线
                    Rectangle()
                        .fill(Color(red: 0.77, green: 0.77, blue: 0.77))
                        .frame(height: 0.4)

                    // MARK: - 真实名称选项 (User)
                    Button {
                        selectedAccountType = .primary
                        isPresented = false
                    } label: {
                        HStack(spacing: 18) {
                            // 头像
                            avatarView(isSelected: selectedAccountType == .primary)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(authManager.currentUser?.displayName ?? authManager.currentUser?.username ?? "User")
                                    .font(Font.custom("SFProDisplay-Bold", size: 19.f))
                                    .foregroundColor(.black)

                                Text(authManager.currentUser?.username ?? "username")
                                    .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                                    .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54))
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .frame(height: 97)
                        .background(Color.white)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // 分隔线
                    Rectangle()
                        .fill(Color(red: 0.77, green: 0.77, blue: 0.77))
                        .frame(height: 0.4)

                    // MARK: - 别名选项 (Dreamer)
                    Button {
                        selectedAccountType = .alias
                        isPresented = false
                    } label: {
                        HStack(spacing: 18) {
                            // 头像
                            avatarView(isSelected: selectedAccountType == .alias)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Dreamer")
                                    .font(Font.custom("SFProDisplay-Bold", size: 19.f))
                                    .foregroundColor(.black)

                                Text("Alias name")
                                    .font(Font.custom("SFProDisplay-Regular", size: 15.f))
                                    .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54))
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .frame(height: 97)
                        .background(Color.white)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 11, topTrailingRadius: 11)
                        .fill(.white)
                )
                .safeAreaInset(edge: .bottom) {
                    Color.white
                        .frame(height: 0)
                }
                .offset(y: 20)
            }
            .background(
                VStack {
                    Spacer()
                    Color.white
                        .frame(height: 50)
                }
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
    }

    // MARK: - 头像视图
    @ViewBuilder
    private func avatarView(isSelected: Bool) -> some View {
        let borderColor = isSelected ? Color(red: 0.82, green: 0.11, blue: 0.26) : Color(red: 0.37, green: 0.37, blue: 0.37)

        ZStack {
            if let pendingAvatar = AvatarManager.shared.pendingAvatar {
                Image(uiImage: pendingAvatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 67, height: 67)
                    .clipShape(Circle())
            } else if let avatarUrl = authManager.currentUser?.avatarUrl,
                      let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    DefaultAvatarView(size: 67)
                }
                .frame(width: 67, height: 67)
                .clipShape(Circle())
            } else {
                DefaultAvatarView(size: 67)
            }
        }
        .overlay(
            Circle()
                .stroke(borderColor, lineWidth: 1)
        )
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

// MARK: - Previews

#Preview("AccountSwitcher - Default") {
    @Previewable @State var isPresented = true
    @Previewable @State var selectedType: AccountDisplayType = .primary

    AccountSwitcherSheet(
        isPresented: $isPresented,
        selectedAccountType: $selectedType
    )
    .environmentObject(AuthenticationManager.shared)
}

#Preview("AccountSwitcher - Dark Mode") {
    @Previewable @State var isPresented = true
    @Previewable @State var selectedType: AccountDisplayType = .primary

    AccountSwitcherSheet(
        isPresented: $isPresented,
        selectedAccountType: $selectedType
    )
    .environmentObject(AuthenticationManager.shared)
    .preferredColorScheme(.dark)
}
