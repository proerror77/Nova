import SwiftUI

/// 名称显示类型
enum NameDisplayType {
    case realName
    case alias
}

/// 名称选择弹窗 - 用于选择发帖时显示的名称类型（真实名称或别名）
struct NameSelectorModal: View {
    @Binding var isPresented: Bool
    @Binding var selectedNameType: NameDisplayType
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
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(Color(red: 0.18, green: 0.18, blue: 0.18))

                        Text("Choose how your name will appear when posting")
                            .font(.system(size: 12))
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
                        selectedNameType = .realName
                        isPresented = false
                    } label: {
                        HStack(spacing: 18) {
                            // 头像
                            avatarView(isSelected: selectedNameType == .realName)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(authManager.currentUser?.displayName ?? authManager.currentUser?.username ?? "User")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundColor(.black)

                                Text(authManager.currentUser?.username ?? "username")
                                    .font(.system(size: 15))
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
                        selectedNameType = .alias
                        isPresented = false
                    } label: {
                        HStack(spacing: 18) {
                            // 头像
                            avatarView(isSelected: selectedNameType == .alias)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Dreamer")
                                    .font(.system(size: 19, weight: .bold))
                                    .foregroundColor(.black)

                                Text("Alias name")
                                    .font(.system(size: 15))
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

// MARK: - Preview
#Preview {
    @Previewable @State var isPresented = true
    @Previewable @State var selectedType: NameDisplayType = .realName

    NameSelectorModal(
        isPresented: $isPresented,
        selectedNameType: $selectedType
    )
    .environmentObject(AuthenticationManager.shared)
}

// MARK: - Save Draft Modal
struct SaveDraftModal: View {
    @Binding var isPresented: Bool
    var onNo: () -> Void
    var onYes: () -> Void

    var body: some View {
        ZStack {
            // 背景遮罩
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // 点击遮罩不关闭，必须选择 Yes 或 No
                }

            // 弹窗内容
            VStack(spacing: 0) {
                Text("Do you want to save it")
                    .font(.system(size: 17, weight: .semibold))
                    .lineSpacing(20)
                    .foregroundColor(.black)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                Divider()

                HStack(spacing: 0) {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onNo()
                        }
                    }) {
                        Text("No")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }

                    Divider()
                        .frame(height: 44)

                    Button(action: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            onYes()
                        }
                    }) {
                        Text("Yes")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
            }
            .frame(width: 270)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(red: 0.97, green: 0.97, blue: 0.97))
            )
            .scaleEffect(isPresented ? 1 : 1.1)
            .opacity(isPresented ? 1 : 0)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
    }
}
