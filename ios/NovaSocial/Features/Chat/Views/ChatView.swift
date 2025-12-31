import SwiftUI
import PhotosUI
import CoreLocation
import MapKit
import Combine
import AVFoundation
import UniformTypeIdentifiers

// MARK: - ChatView
struct ChatView: View {
    // MARK: - Parameters

    @Binding var showChat: Bool
    let conversationId: String
    var userName: String = "User"
    var otherUserAvatarUrl: String?

    // MARK: - ViewModel

    @State private var viewModel = ChatViewModel()
    @State private var showMessageSearch = false

    // MARK: - View Models & Handlers

    @StateObject private var typingHandler: ChatTypingHandler
    @StateObject private var locationManager = ChatLocationManager()

    // MARK: - Scroll State

    @State private var isAtBottom = true
    @State private var newMessageCount = 0
    @Namespace private var bottomID

    // MARK: - Focus State (must stay in View)

    @FocusState private var isInputFocused: Bool

    // MARK: - Initializer

    init(showChat: Binding<Bool>, conversationId: String, userName: String = "User", otherUserAvatarUrl: String? = nil) {
        self._showChat = showChat
        self.conversationId = conversationId
        self.userName = userName
        self.otherUserAvatarUrl = otherUserAvatarUrl

        // Initialize typing handler
        let currentUserId = KeychainService.shared.get(.userId) ?? "unknown"
        self._typingHandler = StateObject(wrappedValue: ChatTypingHandler(
            chatService: ChatService.shared,
            conversationId: conversationId,
            currentUserId: currentUserId
        ))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 顶部导航栏（功能完整版，支持深色模式）
                ZStack(alignment: .bottom) {
                    Rectangle()
                        .foregroundColor(.clear)
                        .frame(height: 98.h)
                        .frame(maxWidth: .infinity)
                        .background(DesignTokens.surface)
                    
                    // 导航栏内容
                    HStack(spacing: 12.w) {
                        // 返回按钮
                        Button {
                            showChat = false
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18.f, weight: .semibold))
                                .foregroundColor(DesignTokens.textPrimary)
                                .frame(width: 24.s, height: 24.s)
                        }
                        
                        // 头像 - 可点击查看个人资料
                        Button {
                            viewModel.showUserProfile = true
                        } label: {
                            AvatarView(
                                image: nil,
                                url: otherUserAvatarUrl,
                                size: 36.s
                            )
                        }
                        
                        // 用户名和 E2EE 状态
                        VStack(alignment: .leading, spacing: 2.h) {
                            Text(userName)
                                .font(.system(size: 16.f, weight: .semibold))
                                .foregroundColor(DesignTokens.textPrimary)
                                .lineLimit(1)
                            
                            // E2EE 状态指示器
                            if viewModel.isMatrixE2EEEnabled {
                                HStack(spacing: 4.w) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 10.f))
                                    Text("End-to-end encrypted")
                                        .font(.system(size: 11.f))
                                }
                                .foregroundColor(DesignTokens.textMuted)
                            }
                        }
                        
                        Spacer()
                        
                        // 搜索按钮
                        Button {
                            showMessageSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 18.f))
                                .foregroundColor(DesignTokens.textPrimary)
                                .frame(width: 24.s, height: 24.s)
                        }
                    }
                    .padding(.horizontal, 16.w)
                    .padding(.bottom, 12.h)
                }

                Divider()
                    .frame(height: 0.5)
                    .background(DesignTokens.borderColor)

                messageListView

                // 底部信息输入栏（功能完整版）
                inputAreaView
            }
            .background(DesignTokens.backgroundColor)
            .ignoresSafeArea(edges: [.top, .bottom])

            // 新消息浮動按鈕
            if !isAtBottom && newMessageCount > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            // 滾動到底部
                            withAnimation {
                                if let lastMessage = viewModel.messages.last {
                                    // 需要透過 ScrollViewReader 來滾動
                                    viewModel.scrollToMessageId = lastMessage.id
                                }
                            }
                            newMessageCount = 0
                        } label: {
                            HStack(spacing: 6.s) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 12.f, weight: .semibold))
                                Text("\(newMessageCount) 則新訊息")
                                    .font(.system(size: 13.f, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14.w)
                            .padding(.vertical, 8.h)
                            .background(DesignTokens.accentColor)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 80.h)  // 在輸入欄上方
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: newMessageCount)
            }
        }
        .fullScreenCover(isPresented: $viewModel.showUserProfile) {
            UserProfileView(
                showUserProfile: $viewModel.showUserProfile,
                userId: conversationId
            )
        }
        .fullScreenCover(isPresented: $viewModel.showCamera) {
            CameraView(image: $viewModel.cameraImage)
        }
        .fullScreenCover(isPresented: $viewModel.showVoiceCall) {
            CallView(
                roomId: conversationId,
                roomName: userName,
                isVideoCall: false,
                intent: .startCallDM
            )
        }
        .fullScreenCover(isPresented: $viewModel.showVideoCall) {
            CallView(
                roomId: conversationId,
                roomName: userName,
                isVideoCall: true,
                intent: .startCallDM
            )
        }
        .sheet(isPresented: $viewModel.showFilePicker) {
            DocumentPickerView(
                onDocumentPicked: { data, filename, mimeType in
                    viewModel.handleDocumentPicked(data: data, filename: filename, mimeType: mimeType)
                },
                onError: { error in
                    viewModel.error = "Cannot access file: \(error.localizedDescription)"
                }
            )
        }
        .sheet(isPresented: $showMessageSearch) {
            MessageSearchView(
                isPresented: $showMessageSearch,
                conversationId: conversationId,
                onMessageSelected: { message in
                    viewModel.scrollToMessageId = message.id
                    showMessageSearch = false
                }
            )
        }
        .sheet(isPresented: $viewModel.showVoiceOptions) {
            VoiceMessageOptionsView(
                isPresented: $viewModel.showVoiceOptions,
                duration: viewModel.pendingVoiceDuration,
                audioURL: viewModel.pendingVoiceURL ?? URL(fileURLWithPath: "/tmp"),
                audioData: viewModel.pendingVoiceData ?? Data(),
                recognizedText: $viewModel.recognizedVoiceText,
                isConverting: $viewModel.isConvertingVoiceToText,
                onSendVoice: {
                    viewModel.sendPendingVoiceMessage()
                },
                onSendText: { text in
                    viewModel.sendVoiceAsText(text)
                },
                onCancel: {
                    viewModel.cancelPendingVoice()
                },
                onConvertToText: {
                    viewModel.convertVoiceToText()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: viewModel.selectedPhotoItem) { _, newItem in
            viewModel.handlePhotoSelection(newItem)
        }
        .onChange(of: viewModel.cameraImage) { _, newImage in
            viewModel.handleCameraImage(newImage)
        }
        .onReceive(locationManager.$location) { newLocation in
            viewModel.handleLocationUpdate(newLocation)
        }
        .alert("Share Location", isPresented: $viewModel.showLocationAlert) {
            Button("Share") {
                if let location = locationManager.location {
                    viewModel.sendLocationMessage(location: location)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Share your current location?")
        }
        .alert("Camera Access Required", isPresented: $viewModel.showCameraPermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
        } message: {
            Text("Please enable camera access in Settings to take photos.")
        }
        .alert("Microphone Access Required", isPresented: $viewModel.showMicrophonePermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
        } message: {
            Text("Please enable microphone access in Settings to record voice messages.")
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .task {
            // Configure ViewModel
            viewModel.configure(
                conversationId: conversationId,
                userName: userName,
                otherUserAvatarUrl: otherUserAvatarUrl,
                typingHandler: typingHandler,
                onDismiss: { showChat = false }
            )

            await viewModel.loadChatData()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Navigation Bar

    // MARK: - Message List View

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16.h) {
                    // Loading indicator
                    if viewModel.isLoadingHistory {
                        ProgressView("Loading messages...")
                            .padding()
                    }

                    // Error message
                    if let error = viewModel.error {
                        VStack(spacing: 8.h) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 30.f))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 14.f))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") {
                                Task { await viewModel.loadChatData() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    }

                    // Date separator
                    Text(viewModel.currentDateString())
                        .font(Font.custom("Helvetica Neue", size: 12.f))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59))
                        .padding(.top, 16.h)
                        .padding(.horizontal, 16.w)

                    // Message list
                    ForEach(viewModel.messages) { message in
                        MessageBubbleView(
                            message: message,
                            audioPlayer: viewModel.audioPlayer,
                            senderAvatarUrl: otherUserAvatarUrl,
                            myAvatarUrl: viewModel.currentUserAvatarUrl,
                            onLongPress: { msg in
                                viewModel.handleMessageLongPress(msg)
                            },
                            onRetry: { msg in
                                viewModel.retryFailedMessage(msg)
                            },
                            onReply: { msg in
                                viewModel.startReply(to: msg)
                            },
                            onTapReply: { messageId in
                                viewModel.scrollToMessageId = messageId
                            },
                            onEdit: { msg in
                                viewModel.startEdit(message: msg)
                            },
                            onReaction: { msg, emoji in
                                viewModel.toggleReaction(on: msg, emoji: emoji)
                            },
                            onRecall: { msg in
                                viewModel.recallMessage(msg)
                            },
                            currentUserId: viewModel.currentUserId
                        )
                        .id(message.id)
                        .onAppear {
                            if message.id == viewModel.messages.first?.id && viewModel.hasMoreMessages && !viewModel.isLoadingHistory {
                                Task { await viewModel.loadMoreMessages() }
                            }
                        }
                    }

                    // Sending indicator
                    if viewModel.isSending {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Sending...")
                                .font(.system(size: 12.f))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }

                    // Typing indicator
                    if typingHandler.isOtherUserTyping {
                        HStack(spacing: 6.w) {
                            AvatarView(image: nil, url: otherUserAvatarUrl, size: 30.s)

                            HStack(spacing: 4.w) {
                                Text("\(typingHandler.typingUserName.isEmpty ? userName : typingHandler.typingUserName) is typing")
                                    .font(Font.custom("Helvetica Neue", size: 14.f))
                                    .foregroundColor(DesignTokens.textMuted)
                                    .italic()

                                TypingDotsView()
                            }
                            .padding(EdgeInsets(top: 8.h, leading: 12.w, bottom: 8.h, trailing: 12.w))
                            .background(DesignTokens.chatBubbleOther.opacity(0.5))
                            .cornerRadius(16.s)

                            Spacer()
                        }
                        .padding(.horizontal, 16.w)
                        .transition(.opacity)
                    }

                    // 底部錨點 - 用於檢測是否在底部
                    Color.clear
                        .frame(height: 1)
                        .id("bottomAnchor")
                        .onAppear { isAtBottom = true; newMessageCount = 0 }
                        .onDisappear { isAtBottom = false }
                }
                .padding(.bottom, 10.h)
            }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                if isAtBottom {
                    // 在底部時自動滾動到最新消息
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                    newMessageCount = 0
                } else if newCount > oldCount {
                    // 不在底部時累加新消息計數
                    newMessageCount += (newCount - oldCount)
                }
            }
            .onChange(of: viewModel.scrollToMessageId) { _, messageId in
                if let messageId = messageId {
                    withAnimation {
                        proxy.scrollTo(messageId, anchor: .center)
                    }
                    // Clear the scroll target after scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        viewModel.scrollToMessageId = nil
                    }
                }
            }
        }
    }

    // MARK: - Input Area View

    private var inputAreaView: some View {
        VStack(spacing: 0) {
            // 回覆預覽
            if let replyPreview = viewModel.replyingToMessage {
                HStack {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DesignTokens.accentColor)
                        .frame(width: 3.w)

                    VStack(alignment: .leading, spacing: 2.h) {
                        Text("回覆 \(replyPreview.senderName)")
                            .font(.system(size: 12.f, weight: .medium))
                            .foregroundColor(DesignTokens.accentColor)
                        Text(replyPreview.content)
                            .font(.system(size: 12.f))
                            .foregroundColor(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        viewModel.cancelReply()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18.f))
                            .foregroundColor(DesignTokens.textMuted)
                    }
                }
                .padding(.horizontal, 16.w)
                .padding(.vertical, 8.h)
                .background(DesignTokens.surface)
            }

            // 編輯模式預覽
            if let editingMsg = viewModel.editingMessage {
                HStack {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.orange)
                        .frame(width: 3.w)

                    VStack(alignment: .leading, spacing: 2.h) {
                        Text("編輯消息")
                            .font(.system(size: 12.f, weight: .medium))
                            .foregroundColor(.orange)
                        Text(editingMsg.text)
                            .font(.system(size: 12.f))
                            .foregroundColor(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        viewModel.cancelEdit()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18.f))
                            .foregroundColor(DesignTokens.textMuted)
                    }
                }
                .padding(.horizontal, 16.w)
                .padding(.vertical, 8.h)
                .background(DesignTokens.surface)
            }

            if viewModel.showAttachmentOptions {
                attachmentOptionsView
            }

            HStack(spacing: 12.w) {
                // Attachment button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.showAttachmentOptions.toggle()
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24.f))
                        .foregroundColor(DesignTokens.accentColor)
                        .rotationEffect(.degrees(viewModel.showAttachmentOptions ? 45 : 0))
                }

                // Text input
                HStack(spacing: 8.w) {
                    TextField(viewModel.editingMessage != nil ? "編輯消息..." : "Type a message...", text: $viewModel.messageText)
                        .font(.system(size: 16.f))
                        .padding(.horizontal, 12.w)
                        .padding(.vertical, 8.h)
                        .focused($isInputFocused)
                        .onChange(of: viewModel.messageText) { _, newValue in
                            if viewModel.editingMessage == nil {
                                viewModel.sendTypingIndicator(isTyping: !newValue.isEmpty)
                            }
                        }

                    // Voice record / Send / Save Edit button
                    if viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && viewModel.editingMessage == nil {
                        voiceRecordButton
                    } else {
                        Button(action: {
                            if viewModel.editingMessage != nil {
                                Task { await viewModel.saveEdit() }
                            } else {
                                viewModel.sendMessage()
                            }
                        }) {
                            if viewModel.isSavingEdit {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 28.s, height: 28.s)
                            } else {
                                Image(systemName: viewModel.editingMessage != nil ? "checkmark.circle.fill" : "arrow.up.circle.fill")
                                    .font(.system(size: 28.f))
                                    .foregroundColor(viewModel.editingMessage != nil ? .orange : DesignTokens.accentColor)
                            }
                        }
                        .disabled(viewModel.isSavingEdit)
                    }
                }
                .background(DesignTokens.surface)
                .cornerRadius(20.s)
                .overlay(
                    RoundedRectangle(cornerRadius: 20.s)
                        .stroke(DesignTokens.borderColor, lineWidth: 1)
                )
            }
            .padding(.horizontal, 16.w)
            .padding(.vertical, 8.h)
            .background(DesignTokens.surface)
        }
    }

    // MARK: - Attachment Options View

    private var attachmentOptionsView: some View {
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ]

        return LazyVGrid(columns: columns, spacing: 16.h) {
            // Photo picker
            PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                attachmentButton(icon: "photo.on.rectangle", label: "Album")
            }

            // Camera
            Button(action: {
                viewModel.checkCameraPermissionAndOpen()
            }) {
                attachmentButton(icon: "camera", label: "Camera")
            }

            // Video call
            Button(action: {
                viewModel.showVideoCall = true
            }) {
                attachmentButton(icon: "video", label: "Video")
            }

            // Voice call
            Button(action: {
                viewModel.showVoiceCall = true
            }) {
                attachmentButton(icon: "phone", label: "Call")
            }

            // Location
            Button(action: {
                locationManager.requestLocation()
                viewModel.showLocationAlert = true
            }) {
                attachmentButton(icon: "location", label: "Location")
            }

            // File picker
            Button(action: {
                viewModel.showFilePicker = true
            }) {
                attachmentButton(icon: "doc", label: "File")
            }
        }
        .padding(.vertical, 12.h)
        .padding(.horizontal, 16.w)
        .background(DesignTokens.surface)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Attachment Button Helper

    @ViewBuilder
    private func attachmentButton(icon: String, label: String) -> some View {
        VStack(spacing: 6.h) {
            Image(systemName: icon)
                .font(.system(size: 24.f))
            Text(label)
                .font(.system(size: 12.f))
        }
        .foregroundColor(DesignTokens.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 60.s)
    }

    // MARK: - Voice Record Button

    private var voiceRecordButton: some View {
        ZStack {
            // Recording indicator
            if viewModel.isRecordingVoice {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 60.s, height: 60.s)
                    .scaleEffect(1.0 + sin(Date().timeIntervalSince1970 * 3) * 0.1)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: viewModel.isRecordingVoice)
            }

            // Microphone button
            Image(systemName: viewModel.isRecordingVoice ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 28.f))
                .foregroundColor(viewModel.isRecordingVoice ? .red : DesignTokens.textSecondary)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !viewModel.isRecordingVoice {
                                viewModel.startVoiceRecording()
                            }
                            viewModel.handleVoiceRecordDragChanged(value)
                        }
                        .onEnded { value in
                            viewModel.handleVoiceRecordDragEnded(value)
                        }
                )

            // Cancel indicator
            if viewModel.isRecordingVoice && viewModel.voiceRecordDragOffset < viewModel.voiceCancelThreshold {
                VStack {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24.f))
                        .foregroundColor(.red)
                    Text("Release to cancel")
                        .font(.system(size: 10.f))
                        .foregroundColor(.red)
                }
                .offset(y: -50.h)
            }

            // Recording duration
            if viewModel.isRecordingVoice {
                Text(viewModel.formatDuration(viewModel.audioRecorder.recordingDuration))
                    .font(.system(size: 12.f, design: .monospaced))
                    .foregroundColor(.red)
                    .offset(y: 25.h)
            }
        }
        .frame(width: 44.s, height: 44.s)
    }
}

// MARK: - Previews

#Preview("Chat - Default") {
    ChatView(
        showChat: .constant(true),
        conversationId: "preview_conversation_123",
        userName: "Alice AI"
    )
}

#Preview("Chat - Dark Mode") {
    ChatView(
        showChat: .constant(true),
        conversationId: "preview_conversation_123",
        userName: "Alice AI"
    )
    .preferredColorScheme(.dark)
}
