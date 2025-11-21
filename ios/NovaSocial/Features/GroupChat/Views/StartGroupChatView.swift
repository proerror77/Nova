import SwiftUI

struct StartGroupChatView: View {
    @Binding var currentPage: AppPage
    @State private var selectedContacts: Set<Int> = []

    var body: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                ZStack {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 375, height: 88)
                        .background(.white)
                        .overlay(
                            Rectangle()
                                .inset(by: 0.20)
                                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                        )

                    HStack(spacing: 50) {
                        Button(action: {
                            currentPage = .message
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20))
                                .foregroundColor(.black)
                                .frame(width: 24, height: 24)
                        }

                        Text("Start Group Chat")
                            .font(Font.custom("Helvetica Neue", size: 24).weight(.medium))
                            .lineSpacing(20)
                            .foregroundColor(.black)

                        Button(action: {
                            // TODO: 保存群聊
                        }) {
                            Text("Save")
                                .font(Font.custom("Helvetica Neue", size: 14))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                        }
                        .frame(width: 36, height: 20)
                    }
                    .frame(width: 343, height: 24)
                    .offset(y: 22)
                }
                .frame(height: 88)

                // MARK: - 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                    Text("Search")
                        .font(Font.custom("Helvetica Neue", size: 15))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37))

                    Spacer()
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(width: 351, height: 32)
                .background(Color(red: 0.91, green: 0.91, blue: 0.91))
                .cornerRadius(32)
                .padding(.top, 20)

                // MARK: - Select an existing group
                HStack {
                    Text("Select an existing group")
                        .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                        .lineSpacing(20)
                        .foregroundColor(.black)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
                .frame(maxWidth: .infinity)
                .overlay(
                    Rectangle()
                        .inset(by: 0.20)
                        .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
                )

                // MARK: - Starred Friends 标题
                HStack {
                    Text("Starred Friends")
                        .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // MARK: - 联系人列表
                ScrollView {
                    VStack(spacing: 0) {
                        // Starred contact
                        ContactRow(name: "Bruce Li", isSelected: selectedContacts.contains(0))
                            .onTapGesture {
                                toggleSelection(0)
                            }

                        // A section
                        HStack {
                            Text("A")
                                .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        // Contacts
                        ForEach(1..<9, id: \.self) { index in
                            ContactRow(name: "Bruce Li", isSelected: selectedContacts.contains(index))
                                .onTapGesture {
                                    toggleSelection(index)
                                }
                        }
                    }
                }
            }
        }
    }

    private func toggleSelection(_ index: Int) {
        if selectedContacts.contains(index) {
            selectedContacts.remove(index)
        } else {
            selectedContacts.insert(index)
        }
    }
}

// MARK: - 联系人行组件
struct ContactRow: View {
    let name: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 13) {
            // 选择圆圈
            ZStack {
                Circle()
                    .stroke(Color(red: 0.53, green: 0.53, blue: 0.53), lineWidth: 0.50)
                    .frame(width: 20, height: 20)

                if isSelected {
                    Circle()
                        .fill(Color(red: 0.82, green: 0.11, blue: 0.26))
                        .frame(width: 12, height: 12)
                }
            }

            // 头像
            Ellipse()
                .foregroundColor(.clear)
                .frame(width: 50, height: 50)
                .background(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))

            // 名字
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                    .lineSpacing(20)
                    .foregroundColor(.black)
            }
            .frame(width: 105, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.97, green: 0.97, blue: 0.97))
        .overlay(
            Rectangle()
                .inset(by: 0.20)
                .stroke(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 0.20)
        )
    }
}

#Preview {
    StartGroupChatView(currentPage: .constant(.startGroupChat))
}
