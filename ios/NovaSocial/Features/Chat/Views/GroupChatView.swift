import SwiftUI

// MARK: - Group Chat Message Model
struct GroupChatMessage: Identifiable, Equatable {
    let id: String
    let text: String
    let senderId: String
    let senderName: String
    let senderAvatarUrl: String?
    let isFromMe: Bool
    let timestamp: Date

    static func == (lhs: GroupChatMessage, rhs: GroupChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Group Chat View
struct GroupChatView: View {
    @Binding var showGroupChat: Bool

    let conversationId: String
    let groupName: String
    let memberCount: Int

    // MARK: - State
    @State private var messageText = ""
    @State private var messages: [GroupChatMessage] = []
    @State private var showAttachmentOptions = false
    @State private var isLoading = false
    @FocusState private var isInputFocused: Bool

    // MARK: - Preview Mode
    @State private var isPreviewMode = false

    #if DEBUG
    private static var usePreviewMode: Bool {
        #if targetEnvironment(simulator)
        return false  // 关闭模拟器预览模式，使用真实API
        #else
        return false
        #endif
    }
    #else
    private static let usePreviewMode = false
    #endif

    init(showGroupChat: Binding<Bool>, conversationId: String, groupName: String, memberCount: Int) {
        self._showGroupChat = showGroupChat
        self.conversationId = conversationId
        self.groupName = groupName
        self.memberCount = memberCount
    }

    var body: some View {
        ZStack {
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - Navigation Bar
                navigationBar

                // MARK: - Messages List
                messagesListView

                // MARK: - Input Area
                inputAreaView
            }
        }
        .task {
            await loadMessages()
        }
    }

    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack(spacing: 0) {
            Button(action: {
                showGroupChat = false
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(DesignTokens.textPrimary)
                    .frame(width: 24, height: 24)
            }
            .frame(width: 60, alignment: .leading)

            Spacer()

            Text("\(groupName)(\(memberCount))")
                .font(Font.custom("Helvetica Neue", size: 20).weight(.medium))
                .foregroundColor(DesignTokens.textPrimary)

            Spacer()

            Button(action: {
                // TODO: Group settings
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundColor(DesignTokens.textPrimary)
                    .frame(width: 24, height: 24)
            }
            .frame(width: 60, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .padding(.horizontal, 16)
        .background(DesignTokens.surface)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(DesignTokens.borderColor),
            alignment: .bottom
        )
    }

    // MARK: - Messages List
    private var messagesListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Preview mode indicator
                    if isPreviewMode {
                        HStack {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 12))
                            Text("Preview Mode - Mock Data")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
                        .padding(.vertical, 8)
                    }

                    ForEach(groupedMessages, id: \.date) { group in
                        // Date separator
                        Text(formatDateHeader(group.date))
                            .font(Font.custom("Helvetica Neue", size: 12))
                            .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59))
                            .padding(.vertical, 8)

                        // Messages in this group
                        ForEach(group.messages) { message in
                            GroupMessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: messages.count) { _, _ in
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .onTapGesture {
            isInputFocused = false
            if showAttachmentOptions {
                showAttachmentOptions = false
            }
        }
    }

    // MARK: - Input Area
    private var inputAreaView: some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: 0.5)
                .background(DesignTokens.borderColor)

            HStack(spacing: 12) {
                // Attachment button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAttachmentOptions.toggle()
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(DesignTokens.accentColor, lineWidth: 2)
                            .frame(width: 30, height: 30)

                        Image(systemName: showAttachmentOptions ? "xmark" : "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignTokens.accentColor)
                    }
                }

                // Text input field
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textMuted)

                    TextField("Type a message...", text: $messageText)
                        .font(Font.custom("Helvetica Neue", size: 16))
                        .foregroundColor(DesignTokens.textPrimary)
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
                        }
                }
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                .cornerRadius(28)
                .onChange(of: isInputFocused) { _, focused in
                    if focused && showAttachmentOptions {
                        showAttachmentOptions = false
                    }
                }

                // Send button
                Button(action: {
                    sendMessage()
                }) {
                    Circle()
                        .fill(messageText.isEmpty ? Color.gray : DesignTokens.accentColor)
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
            .background(DesignTokens.surface)

            // Attachment options
            if showAttachmentOptions {
                attachmentOptionsView
                    .transition(.move(edge: .bottom))
            }
        }
    }

    // MARK: - Attachment Options
    private var attachmentOptionsView: some View {
        HStack(spacing: 15) {
            GroupAttachmentButton(icon: "photo.on.rectangle", title: "Album") {
                showAttachmentOptions = false
            }

            GroupAttachmentButton(icon: "camera", title: "Camera") {
                showAttachmentOptions = false
            }

            GroupAttachmentButton(icon: "video.fill", title: "Video Call") {
                showAttachmentOptions = false
            }

            GroupAttachmentButton(icon: "phone.fill", title: "Voice Call") {
                showAttachmentOptions = false
            }

            GroupAttachmentButton(icon: "location.fill", title: "Location") {
                showAttachmentOptions = false
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.tileBackground)
    }

    // MARK: - Grouped Messages
    private var groupedMessages: [(date: Date, messages: [GroupChatMessage])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        return grouped.map { (date: $0.key, messages: $0.value) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Date Formatting
    private func formatDateHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd  HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Load Messages
    private func loadMessages() async {
        if Self.usePreviewMode {
            loadMockMessages()
            isPreviewMode = true
            return
        }

        isLoading = true
        // TODO: Load real messages from API
        isLoading = false
    }

    // MARK: - Send Message
    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let newMessage = GroupChatMessage(
            id: UUID().uuidString,
            text: trimmedText,
            senderId: "me",
            senderName: "Me",
            senderAvatarUrl: nil,
            isFromMe: true,
            timestamp: Date()
        )

        messages.append(newMessage)
        messageText = ""
        showAttachmentOptions = false

        // TODO: Send message to API
    }

    // MARK: - Mock Data
    private func loadMockMessages() {
        let mockDate = Calendar.current.date(from: DateComponents(year: 2025, month: 10, day: 22, hour: 12, minute: 0)) ?? Date()

        messages = [
            GroupChatMessage(
                id: "1",
                text: "Has everyone come in?",
                senderId: "user1",
                senderName: "Alice",
                senderAvatarUrl: nil,
                isFromMe: false,
                timestamp: mockDate
            ),
            GroupChatMessage(
                id: "2",
                text: "yup!",
                senderId: "user2",
                senderName: "Bob",
                senderAvatarUrl: nil,
                isFromMe: false,
                timestamp: mockDate.addingTimeInterval(30)
            ),
            GroupChatMessage(
                id: "3",
                text: "I'm already in.",
                senderId: "me",
                senderName: "Me",
                senderAvatarUrl: nil,
                isFromMe: true,
                timestamp: mockDate.addingTimeInterval(60)
            ),
            GroupChatMessage(
                id: "4",
                text: "Let's proceed to the next step.",
                senderId: "user3",
                senderName: "Charlie",
                senderAvatarUrl: nil,
                isFromMe: false,
                timestamp: mockDate.addingTimeInterval(120)
            ),
        ]
    }
}

// MARK: - Group Message Bubble View
struct GroupMessageBubbleView: View {
    let message: GroupChatMessage

    private let myBubbleColor = Color(red: 0.92, green: 0.20, blue: 0.34)
    private let otherBubbleColor = Color(red: 0.92, green: 0.92, blue: 0.92)
    private let otherTextColor = Color(red: 0.34, green: 0.34, blue: 0.34)

    var body: some View {
        if message.isFromMe {
            myMessageView
        } else {
            otherMessageView
        }
    }

    // MARK: - My Message (Right side)
    private var myMessageView: some View {
        HStack(alignment: .top, spacing: 10) {
            Spacer()

            Text(message.text)
                .font(Font.custom("Helvetica Neue", size: 16))
                .lineSpacing(4)
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))
                .background(myBubbleColor)
                .cornerRadius(14)
                .frame(maxWidth: 220, alignment: .trailing)

            avatarView(url: message.senderAvatarUrl)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Other's Message (Left side)
    private var otherMessageView: some View {
        HStack(alignment: .top, spacing: 10) {
            avatarView(url: message.senderAvatarUrl)

            Text(message.text)
                .font(Font.custom("Helvetica Neue", size: 16))
                .lineSpacing(4)
                .foregroundColor(otherTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))
                .background(otherBubbleColor)
                .cornerRadius(14)
                .frame(maxWidth: 220, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Avatar View
    @ViewBuilder
    private func avatarView(url: String?) -> some View {
        if let avatarUrl = url, let imageUrl = URL(string: avatarUrl) {
            AsyncImage(url: imageUrl) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Circle()
                    .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50))
                .frame(width: 40, height: 40)
        }
    }
}

// MARK: - Group Attachment Button
struct GroupAttachmentButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Rectangle()
                .foregroundColor(.clear)
                .frame(width: 60, height: 60)
                .background(DesignTokens.surface)
                .cornerRadius(10)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(DesignTokens.textPrimary)
                )

            Text(title)
                .font(.system(size: 12))
                .foregroundColor(DesignTokens.textPrimary)
        }
        .frame(width: 60)
        .onTapGesture {
            action()
        }
    }
}

// MARK: - Previews

#Preview("GroupChat - Default") {
    GroupChatView(
        showGroupChat: .constant(true),
        conversationId: "preview_group_123",
        groupName: "ICERED",
        memberCount: 5
    )
    .environmentObject(AuthenticationManager.shared)
    .environmentObject(ThemeManager.shared)
}

#Preview("GroupChat - Dark Mode") {
    GroupChatView(
        showGroupChat: .constant(true),
        conversationId: "preview_group_123",
        groupName: "ICERED",
        memberCount: 5
    )
    .environmentObject(AuthenticationManager.shared)
    .environmentObject(ThemeManager.shared)
    .preferredColorScheme(.dark)
}
