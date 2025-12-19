import SwiftUI

struct NewChatView: View {
    @Binding var currentPage: AppPage
    @State private var selectedContacts: Set<Int> = []

    var body: some View {
        ZStack {
            // 背景色
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack(spacing: 0) {
                    Button(action: {
                        currentPage = .message
                    }) {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 24)
                            .foregroundColor(.black)
                    }
                    .frame(width: 60, alignment: .leading)

                    Spacer()

                    Text("New Chat")
                        .font(Typography.semibold24)
                        .foregroundColor(.black)

                    Spacer()

                    Button(action: {
                        if !selectedContacts.isEmpty {
                            currentPage = .groupChat
                        }
                    }) {
                        Text(selectedContacts.isEmpty ? "Save" : "Save(\(selectedContacts.count))")
                            .font(Typography.regular14)
                            .foregroundColor(selectedContacts.isEmpty ? Color(red: 0.53, green: 0.53, blue: 0.53) : Color(red: 0.87, green: 0.11, blue: 0.26))
                    }
                    .frame(width: 60, alignment: .trailing)
                    .disabled(selectedContacts.isEmpty)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .padding(.horizontal, 16)
                .background(.white)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(red: 0.74, green: 0.74, blue: 0.74)),
                    alignment: .bottom
                )

                // MARK: - 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(Typography.regular15)
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    Text("Search")
                        .font(Typography.regular15)
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    Spacer()
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(height: 32)
                .background(Color(red: 0.89, green: 0.88, blue: 0.87))
                .cornerRadius(32)
                .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

                // MARK: - Select an existing group
                HStack {
                    Text("Select an existing group")
                        .font(Typography.semibold16)
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
                        .font(Typography.semibold16)
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
                                .font(Typography.semibold16)
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
            Circle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(width: 42, height: 42)

            // 名字
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(Typography.semibold16)
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
    NewChatView(currentPage: .constant(.newChat))
}
