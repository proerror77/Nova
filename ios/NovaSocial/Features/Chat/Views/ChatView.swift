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

    // MARK: - View Models & Handlers

    @StateObject private var typingHandler: ChatTypingHandler
    @StateObject private var locationManager = ChatLocationManager()

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
            DesignTokens.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                navigationBar

                Divider()
                    .frame(height: 0.5)
                    .background(DesignTokens.borderColor)

                messageListView

                inputAreaView
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

    private var navigationBar: some View {
        HStack(spacing: 13) {
            Button(action: {
                showChat = false
            }) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
                    .foregroundColor(DesignTokens.textPrimary)
            }

            HStack(spacing: 13) {
                // Avatar
                if userName.lowercased() == "alice" {
                    Image("alice-avatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    DefaultAvatarView(size: 40)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(userName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)

                    // Matrix E2EE status indicator
                    if viewModel.isMatrixE2EEEnabled {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                            Text("End-to-end encrypted")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    viewModel.showUserProfile = true
                }
            }

            Spacer()
        }
        .frame(height: DesignTokens.topBarHeight)
        .padding(.horizontal, 16)
        .background(DesignTokens.surface)
    }

    // MARK: - Message List View

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Load more history button
                    if viewModel.hasMoreMessages && !viewModel.isLoadingHistory {
                        Button(action: {
                            Task { await viewModel.loadMoreMessages() }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.system(size: 14))
                                Text("載入更多歷史消息")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(DesignTokens.accentColor)
                            .padding(.vertical, 10)
                        }
                    }

                    // Preview mode indicator
                    #if DEBUG
                    if viewModel.isPreviewMode {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 12))
                            Text("Preview Mode - Mock Data (Simulator)")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange.opacity(0.1))
                    }
                    #endif

                    // Loading indicator
                    if viewModel.isLoadingHistory {
                        ProgressView("Loading messages...")
                            .padding()
                    }

                    // Error message
                    if let error = viewModel.error {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 30))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 14))
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
                        .font(Font.custom("Helvetica Neue", size: 12))
                        .lineSpacing(20)
                        .foregroundColor(Color(red: 0.59, green: 0.59, blue: 0.59))
                        .padding(.top, 16)

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
                            }
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
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }

                    // Typing indicator
                    if typingHandler.isOtherUserTyping {
                        HStack(spacing: 6) {
                            AvatarView(image: nil, url: otherUserAvatarUrl, size: 30)

                            HStack(spacing: 4) {
                                Text("\(typingHandler.typingUserName.isEmpty ? userName : typingHandler.typingUserName) is typing")
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .foregroundColor(DesignTokens.textMuted)
                                    .italic()

                                TypingDotsView()
                            }
                            .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .background(DesignTokens.chatBubbleOther.opacity(0.5))
                            .cornerRadius(16)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input Area View

    private var inputAreaView: some View {
        VStack(spacing: 0) {
            if viewModel.showAttachmentOptions {
                attachmentOptionsView
            }

            HStack(spacing: 12) {
                // Attachment button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewModel.showAttachmentOptions.toggle()
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(DesignTokens.accentColor)
                        .rotationEffect(.degrees(viewModel.showAttachmentOptions ? 45 : 0))
                }

                // Text input
                HStack(spacing: 8) {
                    TextField("Type a message...", text: $viewModel.messageText)
                        .font(.system(size: 16))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .focused($isInputFocused)
                        .onChange(of: viewModel.messageText) { _, newValue in
                            viewModel.sendTypingIndicator(isTyping: !newValue.isEmpty)
                        }

                    // Voice record / Send button
                    if viewModel.messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        voiceRecordButton
                    } else {
                        Button(action: {
                            viewModel.sendMessage()
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(DesignTokens.accentColor)
                        }
                    }
                }
                .background(DesignTokens.surface)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(DesignTokens.borderColor, lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(DesignTokens.surface)
        }
    }

    // MARK: - Attachment Options View

    private var attachmentOptionsView: some View {
        HStack(spacing: 20) {
            // Photo picker
            PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 22))
                    Text("Album")
                        .font(.system(size: 11))
                }
                .foregroundColor(DesignTokens.textSecondary)
                .frame(width: 60, height: 60)
            }

            // Camera
            Button(action: {
                viewModel.checkCameraPermissionAndOpen()
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "camera")
                        .font(.system(size: 22))
                    Text("Camera")
                        .font(.system(size: 11))
                }
                .foregroundColor(DesignTokens.textSecondary)
                .frame(width: 60, height: 60)
            }

            // Video call
            Button(action: {
                viewModel.showVideoCall = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "video")
                        .font(.system(size: 22))
                    Text("Video")
                        .font(.system(size: 11))
                }
                .foregroundColor(DesignTokens.textSecondary)
                .frame(width: 60, height: 60)
            }

            // Voice call
            Button(action: {
                viewModel.showVoiceCall = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "phone")
                        .font(.system(size: 22))
                    Text("Call")
                        .font(.system(size: 11))
                }
                .foregroundColor(DesignTokens.textSecondary)
                .frame(width: 60, height: 60)
            }

            // Location
            Button(action: {
                locationManager.requestLocation()
                viewModel.showLocationAlert = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "location")
                        .font(.system(size: 22))
                    Text("Location")
                        .font(.system(size: 11))
                }
                .foregroundColor(DesignTokens.textSecondary)
                .frame(width: 60, height: 60)
            }

            // File picker
            Button(action: {
                viewModel.showFilePicker = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.system(size: 22))
                    Text("File")
                        .font(.system(size: 11))
                }
                .foregroundColor(DesignTokens.textSecondary)
                .frame(width: 60, height: 60)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(DesignTokens.surface)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Voice Record Button

    private var voiceRecordButton: some View {
        ZStack {
            // Recording indicator
            if viewModel.isRecordingVoice {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .scaleEffect(1.0 + sin(Date().timeIntervalSince1970 * 3) * 0.1)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: viewModel.isRecordingVoice)
            }

            // Microphone button
            Image(systemName: viewModel.isRecordingVoice ? "stop.circle.fill" : "mic.circle.fill")
                .font(.system(size: 28))
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
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                    Text("Release to cancel")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                }
                .offset(y: -50)
            }

            // Recording duration
            if viewModel.isRecordingVoice {
                Text(viewModel.formatDuration(viewModel.audioRecorder.recordingDuration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.red)
                    .offset(y: 25)
            }
        }
        .frame(width: 44, height: 44)
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
