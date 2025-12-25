import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Group Chat View
struct GroupChatView: View {
    @Binding var showGroupChat: Bool

    let conversationId: String
    let groupName: String
    let memberCount: Int

    // MARK: - ViewModel
    @State private var viewModel = GroupChatViewModel()

    // MARK: - State
    @FocusState private var isInputFocused: Bool

    // 圖片選擇
    @State private var selectedPhotoItem: PhotosPickerItem?

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
            viewModel.configure(
                conversationId: conversationId,
                groupName: groupName,
                memberCount: memberCount
            )
            await viewModel.loadMessages()
        }
        .fullScreenCover(isPresented: $viewModel.showVoiceCall) {
            CallView(
                roomId: conversationId,
                roomName: groupName,
                isVideoCall: false,
                intent: .startCall
            )
        }
        .fullScreenCover(isPresented: $viewModel.showVideoCall) {
            CallView(
                roomId: conversationId,
                roomName: groupName,
                isVideoCall: true,
                intent: .startCall
            )
        }
        .sheet(isPresented: $viewModel.showFilePicker) {
            DocumentPickerView(
                onDocumentPicked: { data, filename, mimeType in
                    viewModel.sendFileMessage(data: data, filename: filename, mimeType: mimeType)
                },
                onError: { fileError in
                    #if DEBUG
                    print("[GroupChatView] ❌ Cannot access file: \(fileError)")
                    #endif
                    viewModel.error = "Cannot access file: \(fileError.localizedDescription)"
                }
            )
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            handlePhotoSelection(newItem)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error)
            }
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
                    if viewModel.isPreviewMode {
                        HStack {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 12))
                            Text("Preview Mode - Mock Data")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(.orange)
                        .padding(.vertical, 8)
                    }

                    ForEach(viewModel.groupedMessages, id: \.date) { group in
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
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
        .onTapGesture {
            isInputFocused = false
            if viewModel.showAttachmentOptions {
                viewModel.showAttachmentOptions = false
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
                        viewModel.showAttachmentOptions.toggle()
                    }
                }) {
                    ZStack {
                        Circle()
                            .stroke(DesignTokens.accentColor, lineWidth: 2)
                            .frame(width: 30, height: 30)

                        Image(systemName: viewModel.showAttachmentOptions ? "xmark" : "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignTokens.accentColor)
                    }
                }

                // Text input field
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14))
                        .foregroundColor(DesignTokens.textMuted)

                    TextField("Type a message...", text: $viewModel.messageText)
                        .font(Font.custom("Helvetica Neue", size: 16))
                        .foregroundColor(DesignTokens.textPrimary)
                        .focused($isInputFocused)
                        .onSubmit {
                            viewModel.sendMessage()
                        }
                }
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .background(Color(red: 0.85, green: 0.85, blue: 0.85))
                .cornerRadius(28)
                .onChange(of: isInputFocused) { _, focused in
                    if focused && viewModel.showAttachmentOptions {
                        viewModel.showAttachmentOptions = false
                    }
                }

                // Send button or Voice record button
                if viewModel.messageText.isEmpty {
                    voiceRecordButton
                } else {
                    Button(action: {
                        viewModel.sendMessage()
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
            if viewModel.showAttachmentOptions {
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
                viewModel.showAttachmentOptions = false
                viewModel.showVideoCall = true
            }

            GroupAttachmentButton(icon: "phone.fill", title: "Voice Call") {
                viewModel.showAttachmentOptions = false
                viewModel.showVoiceCall = true
            }

            GroupAttachmentButton(icon: "doc.fill", title: "File") {
                viewModel.showAttachmentOptions = false
                viewModel.showFilePicker = true
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
            if viewModel.isRecordingVoice {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .scaleEffect(viewModel.audioRecorder.audioLevel > 0.3 ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.audioRecorder.audioLevel)
            }

            // 主按鈕
            Circle()
                .fill(viewModel.isRecordingVoice ? Color.red : Color.gray.opacity(0.3))
                .frame(width: 33, height: 33)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundColor(viewModel.isRecordingVoice ? .white : DesignTokens.textMuted)
                )
                .scaleEffect(viewModel.isRecordingVoice ? 1.1 : 1.0)
                .offset(y: viewModel.voiceRecordDragOffset)
                .animation(.spring(response: 0.3), value: viewModel.isRecordingVoice)

            // 取消提示
            if viewModel.isRecordingVoice && viewModel.voiceRecordDragOffset < viewModel.voiceCancelThreshold {
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
            if viewModel.isRecordingVoice {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)

                    Text(formatRecordingDuration(viewModel.audioRecorder.recordingDuration))
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
        if !viewModel.isRecordingVoice && !viewModel.audioRecorder.isRecording {
            startVoiceRecording()
        }

        // 追蹤拖動偏移（只允許向上）
        viewModel.voiceRecordDragOffset = min(0, value.translation.height)
    }

    private func handleVoiceRecordDragEnded(_ value: DragGesture.Value) {
        // 檢查是否應該取消
        if value.translation.height < viewModel.voiceCancelThreshold {
            cancelVoiceRecording()
        } else {
            stopAndSendVoiceMessage()
        }

        // 重置狀態
        viewModel.voiceRecordDragOffset = 0
    }

    // MARK: - Voice Recording Control
    private func startVoiceRecording() {
        Task {
            let success = await viewModel.audioRecorder.startRecording()
            await MainActor.run {
                viewModel.isRecordingVoice = success
            }
        }
    }

    private func cancelVoiceRecording() {
        viewModel.audioRecorder.cancelRecording()
        viewModel.isRecordingVoice = false
        #if DEBUG
        print("[GroupChatView] 🎙️ Voice recording cancelled")
        #endif
    }

    private func stopAndSendVoiceMessage() {
        guard viewModel.isRecordingVoice else { return }

        if let result = viewModel.audioRecorder.stopRecording() {
            // 最少 0.5 秒才發送
            if result.duration >= 0.5 {
                viewModel.sendVoiceMessage(data: result.data, duration: result.duration)
            }
            viewModel.audioRecorder.cleanupTempFiles()
        }

        viewModel.isRecordingVoice = false
    }

    private func formatRecordingDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Date Formatting
    private func formatDateHeader(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd  HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Photo Selection
    private func handlePhotoSelection(_ newItem: PhotosPickerItem?) {
        Task {
            do {
                if let data = try await newItem?.loadTransferable(type: Data.self) {
                    viewModel.sendImageMessage(data: data, mimeType: "image/jpeg")
                    #if DEBUG
                    print("[GroupChatView] ✅ Image sent via ViewModel")
                    #endif
                }
            } catch {
                #if DEBUG
                print("[GroupChatView] ❌ Failed to load image: \(error)")
                #endif
                viewModel.error = "Failed to load image"
            }
        }
    }
}

// MARK: - Group Message Bubble View
struct GroupMessageBubbleView: View {
    let message: GroupChatUIMessage

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

            messageContent
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

            VStack(alignment: .leading, spacing: 2) {
                // Sender name for group messages
                Text(message.senderName)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59))

                messageContent
                    .background(otherBubbleColor)
                    .cornerRadius(14)
            }
            .frame(maxWidth: 220, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Message Content
    @ViewBuilder
    private var messageContent: some View {
        switch message.messageType {
        case .image:
            if let image = message.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200, maxHeight: 200)
                    .cornerRadius(10)
            } else if let mediaUrl = message.mediaUrl, let url = URL(string: mediaUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(maxWidth: 200, maxHeight: 200)
                .cornerRadius(10)
            } else {
                Text("[Image]")
                    .font(Font.custom("Helvetica Neue", size: 16))
                    .foregroundColor(message.isFromMe ? .white : otherTextColor)
                    .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))
            }

        case .audio:
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 16))
                    .foregroundColor(message.isFromMe ? .white : otherTextColor)

                if let duration = message.audioDuration {
                    Text(formatDuration(duration))
                        .font(.system(size: 14))
                        .foregroundColor(message.isFromMe ? .white : otherTextColor)
                }
            }
            .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))

        case .location:
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 16))
                    .foregroundColor(message.isFromMe ? .white : otherTextColor)

                Text("Location")
                    .font(Font.custom("Helvetica Neue", size: 16))
                    .foregroundColor(message.isFromMe ? .white : otherTextColor)
            }
            .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))

        case .file:
            HStack(spacing: 8) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 16))
                    .foregroundColor(message.isFromMe ? .white : otherTextColor)

                Text(message.text)
                    .font(Font.custom("Helvetica Neue", size: 16))
                    .foregroundColor(message.isFromMe ? .white : otherTextColor)
                    .lineLimit(2)
            }
            .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))

        default:
            // Text message
            Text(message.text)
                .font(Font.custom("Helvetica Neue", size: 16))
                .lineSpacing(4)
                .foregroundColor(message.isFromMe ? .white : otherTextColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 20))
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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
