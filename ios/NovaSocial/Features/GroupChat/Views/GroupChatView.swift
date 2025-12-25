import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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

    // 通話相關
    @State private var showVoiceCall = false
    @State private var showVideoCall = false

    // 圖片選擇
    @State private var selectedPhotoItem: PhotosPickerItem?

    // 檔案選擇
    @State private var showFilePicker = false

    // 語音錄製
    @State private var audioRecorder = AudioRecorderService()
    @State private var isRecordingVoice = false
    @State private var voiceRecordDragOffset: CGFloat = 0
    private let voiceCancelThreshold: CGFloat = -60

    // Matrix 服務
    private let matrixBridge = MatrixBridgeService.shared

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
        .fullScreenCover(isPresented: $showVoiceCall) {
            CallView(
                roomId: conversationId,
                roomName: groupName,
                isVideoCall: false,
                intent: .startCall
            )
        }
        .fullScreenCover(isPresented: $showVideoCall) {
            CallView(
                roomId: conversationId,
                roomName: groupName,
                isVideoCall: true,
                intent: .startCall
            )
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView(
                onDocumentPicked: { data, filename, mimeType in
                    handleDocumentPicked(data: data, filename: filename, mimeType: mimeType)
                },
                onError: { error in
                    #if DEBUG
                    print("[GroupChatView] ❌ Cannot access file: \(error)")
                    #endif
                }
            )
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            handlePhotoSelection(newItem)
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

                // Send button or Voice record button
                if messageText.isEmpty {
                    voiceRecordButton
                } else {
                    Button(action: {
                        sendMessage()
                    }) {
                        Circle()
                            .fill(DesignTokens.accentColor)
                            .frame(width: 33, height: 33)
                            .overlay(
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            )
                    }
                }
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
            // Album (使用 PhotosPicker)
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                VStack(spacing: 4) {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(width: 60, height: 60)
                        .background(DesignTokens.surface)
                        .cornerRadius(10)
                        .overlay(
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor(DesignTokens.textPrimary)
                        )
                    Text("Album")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textPrimary)
                }
                .frame(width: 60)
            }

            GroupAttachmentButton(icon: "video.fill", title: "Video Call") {
                showAttachmentOptions = false
                showVideoCall = true
            }

            GroupAttachmentButton(icon: "phone.fill", title: "Voice Call") {
                showAttachmentOptions = false
                showVoiceCall = true
            }

            GroupAttachmentButton(icon: "doc.fill", title: "File") {
                showAttachmentOptions = false
                showFilePicker = true
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.tileBackground)
    }

    // MARK: - Voice Record Button
    private var voiceRecordButton: some View {
        ZStack {
            // 錄音時的脈衝動畫背景
            if isRecordingVoice {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .scaleEffect(audioRecorder.audioLevel > 0.3 ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: audioRecorder.audioLevel)
            }

            // 主按鈕
            Circle()
                .fill(isRecordingVoice ? Color.red : Color.gray.opacity(0.3))
                .frame(width: 33, height: 33)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isRecordingVoice ? .white : DesignTokens.textMuted)
                )
                .scaleEffect(isRecordingVoice ? 1.1 : 1.0)
                .offset(y: voiceRecordDragOffset)
                .animation(.spring(response: 0.3), value: isRecordingVoice)

            // 取消提示
            if isRecordingVoice && voiceRecordDragOffset < voiceCancelThreshold {
                VStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                    Text("鬆開取消")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .offset(y: -70)
            }

            // 錄音時長顯示
            if isRecordingVoice {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)

                    Text(formatRecordingDuration(audioRecorder.recordingDuration))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.red)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)

                    Text("上滑取消")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                .offset(y: -55)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    handleVoiceRecordDragChanged(value)
                }
                .onEnded { value in
                    handleVoiceRecordDragEnded(value)
                }
        )
    }

    // MARK: - Voice Recording Gesture Handlers
    private func handleVoiceRecordDragChanged(_ value: DragGesture.Value) {
        // 開始錄音
        if !isRecordingVoice && !audioRecorder.isRecording {
            startVoiceRecording()
        }

        // 追蹤拖動偏移（只允許向上）
        voiceRecordDragOffset = min(0, value.translation.height)
    }

    private func handleVoiceRecordDragEnded(_ value: DragGesture.Value) {
        // 檢查是否應該取消
        if value.translation.height < voiceCancelThreshold {
            cancelVoiceRecording()
        } else {
            stopAndSendVoiceMessage()
        }

        // 重置狀態
        voiceRecordDragOffset = 0
    }

    // MARK: - Voice Recording Control
    private func startVoiceRecording() {
        Task {
            let success = await audioRecorder.startRecording()
            await MainActor.run {
                isRecordingVoice = success
            }
        }
    }

    private func cancelVoiceRecording() {
        audioRecorder.cancelRecording()
        isRecordingVoice = false
        #if DEBUG
        print("[GroupChatView] 🎙️ Voice recording cancelled")
        #endif
    }

    private func stopAndSendVoiceMessage() {
        guard isRecordingVoice else { return }

        if let result = audioRecorder.stopRecording() {
            // 最少 0.5 秒才發送
            if result.duration >= 0.5 {
                sendVoiceMessage(data: result.data, duration: result.duration)
            }
            audioRecorder.cleanupTempFiles()
        }

        isRecordingVoice = false
    }

    private func sendVoiceMessage(data: Data, duration: TimeInterval) {
        Task {
            do {
                // 保存到臨時檔案
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent("\(UUID().uuidString).m4a")
                try data.write(to: tempFileURL)

                // 通過 Matrix 發送語音消息
                _ = try await matrixBridge.sendMessage(
                    conversationId: conversationId,
                    content: "Voice message (\(Int(duration))s)",
                    mediaURL: tempFileURL,
                    mimeType: "audio/mp4"
                )

                // 清理臨時檔案
                try? FileManager.default.removeItem(at: tempFileURL)

                #if DEBUG
                print("[GroupChatView] 🎙️ Voice message sent: \(duration)s, \(data.count) bytes")
                #endif
            } catch {
                #if DEBUG
                print("[GroupChatView] ❌ Failed to send voice message: \(error)")
                #endif
            }
        }
    }

    private func formatRecordingDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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

    // MARK: - Photo Selection
    private func handlePhotoSelection(_ newItem: PhotosPickerItem?) {
        Task {
            do {
                if let data = try await newItem?.loadTransferable(type: Data.self) {
                    // 將圖片複製到臨時目錄
                    let tempDir = FileManager.default.temporaryDirectory
                    let tempFileURL = tempDir.appendingPathComponent("\(UUID().uuidString).jpg")
                    try data.write(to: tempFileURL)

                    // 使用 Matrix 發送圖片
                    _ = try await matrixBridge.sendMessage(
                        conversationId: conversationId,
                        content: "Image",
                        mediaURL: tempFileURL,
                        mimeType: "image/jpeg"
                    )

                    // 清理臨時檔案
                    try? FileManager.default.removeItem(at: tempFileURL)

                    #if DEBUG
                    print("[GroupChatView] ✅ Image sent via Matrix")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[GroupChatView] ❌ Failed to send image: \(error)")
                #endif
            }
        }
    }

    // MARK: - Document Handling
    /// 處理選擇的檔案（數據已在 DocumentPicker 回調中讀取）
    private func handleDocumentPicked(data: Data, filename: String, mimeType: String) {
        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent(filename)
                try data.write(to: tempFileURL)

                _ = try await matrixBridge.sendMessage(
                    conversationId: conversationId,
                    content: filename,
                    mediaURL: tempFileURL,
                    mimeType: mimeType
                )

                try? FileManager.default.removeItem(at: tempFileURL)

                #if DEBUG
                print("[GroupChatView] ✅ File sent via Matrix: \(filename)")
                #endif
            } catch {
                #if DEBUG
                print("[GroupChatView] ❌ Failed to send file: \(error)")
                #endif
            }
        }
    }

    private func getMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "application/pdf"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "txt": return "text/plain"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "mp3": return "audio/mpeg"
        case "mp4": return "video/mp4"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Group Document Picker (uses shared DocumentPickerView)
// GroupDocumentPickerView removed - now using shared DocumentPickerView from Chat/Views/Components

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
