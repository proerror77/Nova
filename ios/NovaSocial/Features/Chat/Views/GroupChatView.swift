import SwiftUI

struct GroupChatView: View {
    @Binding var currentPage: AppPage
    @State private var messageText = ""
    @State private var messages: [GroupChatMessage] = []
    @State private var showAttachmentOptions = false
    @FocusState private var isInputFocused: Bool

    let groupName: String
    let memberCount: Int

    init(currentPage: Binding<AppPage>, groupName: String = "ICERED", memberCount: Int = 5) {
        self._currentPage = currentPage
        self.groupName = groupName
        self.memberCount = memberCount
    }

    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.97, blue: 0.97)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack(spacing: 0) {
                    Button(action: {
                        currentPage = .message
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20))
                            .foregroundColor(.black)
                            .frame(width: 24, height: 24)
                    }

                    Spacer()

                    Text("\(groupName)(\(memberCount))")
                        .font(Font.custom("Helvetica Neue", size: 20).weight(.medium))
                        .foregroundColor(.black)

                    Spacer()

                    Button(action: {
                        // TODO: 群聊设置
                    }) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20))
                            .foregroundColor(.black)
                            .frame(width: 24, height: 24)
                    }
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

                // MARK: - 消息列表
                ScrollView {
                    VStack(spacing: 16) {
                        Text(currentDateString())
                            .font(Font.custom("Helvetica Neue", size: 12))
                            .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59))
                            .padding(.top, 16)

                        ForEach(messages) { message in
                            GroupMessageBubbleView(message: message)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    if showAttachmentOptions {
                        showAttachmentOptions = false
                    }
                }

                // MARK: - 输入区域
                inputAreaView
            }
        }
    }

    // MARK: - 输入区域
    private var inputAreaView: some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: 0.5)
                .background(Color(red: 0.74, green: 0.74, blue: 0.74))

            HStack(spacing: 12) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAttachmentOptions.toggle()
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(Color(red: 0.91, green: 0.18, blue: 0.30), lineWidth: 2)
                            .frame(width: 26, height: 26)

                        Image(systemName: showAttachmentOptions ? "xmark" : "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 0.91, green: 0.18, blue: 0.30))
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))

                    TextField("Type a message...", text: $messageText)
                        .font(Font.custom("Helvetica Neue", size: 16))
                        .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
                        }
                }
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .background(Color(red: 0.53, green: 0.53, blue: 0.53).opacity(0.20))
                .cornerRadius(26)
                .onChange(of: isInputFocused) { _, focused in
                    if focused && showAttachmentOptions {
                        showAttachmentOptions = false
                    }
                }

                Button(action: {
                    sendMessage()
                }) {
                    Circle()
                        .fill(messageText.isEmpty ? Color.gray : Color(red: 0.91, green: 0.18, blue: 0.30))
                        .frame(width: 33, height: 33)
                        .overlay(
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        )
                }
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white)

            if showAttachmentOptions {
                attachmentOptionsView
                    .transition(.move(edge: .bottom))
            }
        }
    }

    // MARK: - 附件选项视图
    private var attachmentOptionsView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                GroupChatAttachmentButton(icon: "photo.on.rectangle", title: "Album") {
                    showAttachmentOptions = false
                }

                GroupChatAttachmentButton(icon: "camera", title: "Camera") {
                    showAttachmentOptions = false
                }

                GroupChatAttachmentButton(icon: "video.fill", title: "Video Call") {
                    showAttachmentOptions = false
                }

                GroupChatAttachmentButton(icon: "phone.fill", title: "Voice Call") {
                    showAttachmentOptions = false
                }

                GroupChatAttachmentButton(icon: "location.fill", title: "Location") {
                    showAttachmentOptions = false
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.91, green: 0.91, blue: 0.91))
    }

    // MARK: - 发送消息
    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let message = GroupChatMessage(
            text: trimmedText,
            senderName: "Me",
            isFromMe: true,
            timestamp: Date()
        )
        messages.append(message)

        messageText = ""
        showAttachmentOptions = false
    }

    // MARK: - 获取当前日期字符串
    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd  HH:mm"
        return formatter.string(from: Date())
    }
}

// MARK: - 附件选项按钮（群聊专用）
private struct GroupChatAttachmentButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Rectangle()
                .foregroundColor(.clear)
                .frame(width: 60, height: 60)
                .background(.white)
                .cornerRadius(10)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(.black)
                )
            Text(title)
                .font(Font.custom("Helvetica Neue", size: 12))
                .lineSpacing(20)
                .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))
        }
        .frame(width: 60)
        .onTapGesture {
            action()
        }
    }
}

// MARK: - 群聊消息模型
struct GroupChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let senderName: String
    let isFromMe: Bool
    let timestamp: Date
}

// MARK: - 群聊消息气泡
struct GroupMessageBubbleView: View {
    let message: GroupChatMessage

    var body: some View {
        if message.isFromMe {
            myMessageView
        } else {
            otherMessageView
        }
    }

    private var myMessageView: some View {
        HStack(spacing: 6) {
            Spacer()

            Text(message.text)
                .font(Font.custom("Helvetica Neue", size: 18))
                .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                .cornerRadius(23)

            Circle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(width: 50, height: 50)
        }
        .padding(.horizontal, 16)
    }

    private var otherMessageView: some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 4) {
                Text(message.senderName)
                    .font(Font.custom("Helvetica Neue", size: 14).weight(.bold))
                    .foregroundColor(Color(red: 0.25, green: 0.25, blue: 0.25))

                Text(message.text)
                    .font(Font.custom("Helvetica Neue", size: 18))
                    .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34))
                    .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                    .cornerRadius(23)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    GroupChatView(currentPage: .constant(.groupChat))
}
