import SwiftUI
import PhotosUI

/// View for managing group chat settings
/// Features: member list, group info, leave group, mute notifications
struct GroupSettingsView: View {
    @Binding var isPresented: Bool
    let conversationId: String
    let groupName: String
    let memberCount: Int
    let onGroupInfoUpdated: ((String, String?) -> Void)?

    @State private var members: [GroupMemberDisplayInfo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isMuted = false
    @State private var showLeaveConfirmation = false
    @State private var isLeaving = false
    @State private var currentGroupName: String
    @State private var currentAvatarUrl: String?
    @State private var showEditGroupInfo = false
    @State private var showUserProfile = false
    @State private var selectedUserId: String = ""

    private let matrixBridge = MatrixBridgeService.shared
    private let userService = UserService.shared

    init(
        isPresented: Binding<Bool>,
        conversationId: String,
        groupName: String,
        memberCount: Int,
        onGroupInfoUpdated: ((String, String?) -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.conversationId = conversationId
        self.groupName = groupName
        self.memberCount = memberCount
        self.onGroupInfoUpdated = onGroupInfoUpdated
        self._currentGroupName = State(initialValue: groupName)
        self._currentAvatarUrl = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.backgroundColor
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading...")
                        .foregroundColor(DesignTokens.textSecondary)
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40.f))
                            .foregroundColor(DesignTokens.accentColor)
                        Text(error)
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(DesignTokens.textSecondary)
                        Button("Retry") {
                            Task { await loadGroupDetails() }
                        }
                        .foregroundColor(DesignTokens.accentColor)
                    }
                } else {
                    List {
                        // Group Info Section
                        Section {
                            groupInfoRow
                        }

                        // Members Section
                        Section {
                            ForEach(members) { member in
                                MemberRow(member: member) {
                                    openProfile(for: member)
                                }
                            }
                        } header: {
                            Text("Members (\(members.count))")
                                .font(Font.custom("SFProDisplay-Semibold", size: 13.f))
                                .foregroundColor(DesignTokens.textSecondary)
                        }

                        // Settings Section
                        Section {
                            muteToggleRow
                        } header: {
                            Text("Notifications")
                                .font(Font.custom("SFProDisplay-Semibold", size: 13.f))
                                .foregroundColor(DesignTokens.textSecondary)
                        }

                        // Actions Section
                        Section {
                            leaveGroupButton
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Group Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(DesignTokens.textPrimary)
                }
            }
        }
        .task {
            await loadGroupDetails()
        }
        .sheet(isPresented: $showEditGroupInfo) {
            EditGroupInfoView(
                roomId: conversationId,
                currentName: currentGroupName,
                currentAvatarUrl: currentAvatarUrl
            ) { updatedName, updatedAvatarUrl in
                currentGroupName = updatedName
                currentAvatarUrl = updatedAvatarUrl
                onGroupInfoUpdated?(updatedName, updatedAvatarUrl)
            }
        }
        .fullScreenCover(isPresented: $showUserProfile) {
            UserProfileView(
                showUserProfile: $showUserProfile,
                userId: selectedUserId
            )
        }
        .alert("Leave Group", isPresented: $showLeaveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                Task { await leaveGroup() }
            }
        } message: {
            Text("Are you sure you want to leave \"\(groupName)\"? You will no longer receive messages from this group.")
        }
    }

    // MARK: - Group Info Row

    private var groupInfoRow: some View {
        Button {
            showEditGroupInfo = true
        } label: {
            HStack(spacing: 16) {
                AvatarView(image: nil, url: currentAvatarUrl, size: 60, name: currentGroupName)

                VStack(alignment: .leading, spacing: 4) {
                    Text(currentGroupName)
                        .font(Font.custom("SFProDisplay-Semibold", size: 18.f))
                        .foregroundColor(DesignTokens.textPrimary)

                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12.f))
                            .foregroundColor(.green)
                        Text("End-to-end encrypted")
                            .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14.f, weight: .semibold))
                    .foregroundColor(DesignTokens.textSecondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .listRowBackground(DesignTokens.surface)
    }

    // MARK: - Mute Toggle Row

    private var muteToggleRow: some View {
        Toggle(isOn: $isMuted) {
            HStack(spacing: 12) {
                Image(systemName: isMuted ? "bell.slash.fill" : "bell.fill")
                    .font(Font.custom("SFProDisplay-Regular", size: 18.f))
                    .foregroundColor(DesignTokens.textPrimary)
                    .frame(width: 28)

                Text("Mute Notifications")
                    .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                    .foregroundColor(DesignTokens.textPrimary)
            }
        }
        .tint(DesignTokens.accentColor)
        .listRowBackground(DesignTokens.surface)
    }

    // MARK: - Leave Group Button

    private var leaveGroupButton: some View {
        Button(action: {
            showLeaveConfirmation = true
        }) {
            HStack {
                Spacer()
                if isLeaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .red))
                } else {
                    Text("Leave Group")
                        .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                        .foregroundColor(.red)
                }
                Spacer()
            }
        }
        .disabled(isLeaving)
        .listRowBackground(DesignTokens.surface)
    }

    // MARK: - Load Group Details

    private func loadGroupDetails() async {
        isLoading = true
        errorMessage = nil

        do {
            if !matrixBridge.isInitialized {
                try await matrixBridge.initialize()
            }

            // Refresh room metadata (name/avatar)
            if let room = try await matrixBridge.getMatrixRooms().first(where: { $0.id == conversationId }) {
                let name = (room.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                currentGroupName = name.isEmpty ? groupName : name
                currentAvatarUrl = room.avatarURL
            }

            // Get real members from Matrix SDK
            let roomMembers = try await matrixBridge.getConversationMembers(conversationId: conversationId)

            // Convert to display info
            members = roomMembers.map { member in
                // Extract username from Matrix user ID (e.g., "@username:server" -> "username")
                let displayName = member.displayName ?? extractUsername(from: member.userId)

                return GroupMemberDisplayInfo(
                    id: member.userId,
                    displayName: displayName,
                    avatarUrl: member.avatarUrl,
                    isAdmin: member.isAdmin
                )
            }

            // Sort: admins first, then by display name
            members.sort { first, second in
                if first.isAdmin != second.isAdmin {
                    return first.isAdmin
                }
                return first.displayName < second.displayName
            }

            #if DEBUG
            print("[GroupSettingsView] Loaded \(members.count) real members")
            #endif

        } catch {
            errorMessage = "Failed to load group details"
            #if DEBUG
            print("[GroupSettingsView] Error: \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - Leave Group

    private func leaveGroup() async {
        isLeaving = true

        do {
            try await matrixBridge.leaveRoom(roomId: conversationId)
            isPresented = false
        } catch {
            errorMessage = "Failed to leave group"
            #if DEBUG
            print("[GroupSettingsView] Leave error: \(error)")
            #endif
        }

        isLeaving = false
    }

    // MARK: - Helpers

    private func extractUsername(from matrixUserId: String) -> String {
        if matrixUserId.hasPrefix("@") {
            let parts = matrixUserId.dropFirst().split(separator: ":")
            if let username = parts.first {
                return String(username)
            }
        }
        return matrixUserId
    }

    private func openProfile(for member: GroupMemberDisplayInfo) {
        let novaIdentifier =
            matrixBridge.matrixService.convertToNovaUserId(matrixUserId: member.id) ??
            extractUsername(from: member.id)

        userService.invalidateCache(userId: novaIdentifier)
        selectedUserId = novaIdentifier
        showUserProfile = true
    }
}

// MARK: - Member Display Info

struct GroupMemberDisplayInfo: Identifiable {
    let id: String
    let displayName: String
    let avatarUrl: String?
    let isAdmin: Bool
}

// MARK: - Member Row

private struct MemberRow: View {
    let member: GroupMemberDisplayInfo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarView(image: nil, url: member.avatarUrl, size: 44, name: member.displayName)

                // Name and role
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName)
                        .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                        .foregroundColor(DesignTokens.textPrimary)

                    if member.isAdmin {
                        Text("Admin")
                            .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                            .foregroundColor(DesignTokens.accentColor)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14.f, weight: .semibold))
                    .foregroundColor(DesignTokens.textSecondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(DesignTokens.surface)
    }
}

// MARK: - Edit Group Info

private struct EditGroupInfoView: View {
    let roomId: String
    let currentName: String
    let currentAvatarUrl: String?
    let onUpdated: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftName: String
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let matrixBridge = MatrixBridgeService.shared

    init(
        roomId: String,
        currentName: String,
        currentAvatarUrl: String?,
        onUpdated: @escaping (String, String?) -> Void
    ) {
        self.roomId = roomId
        self.currentName = currentName
        self.currentAvatarUrl = currentAvatarUrl
        self.onUpdated = onUpdated
        self._draftName = State(initialValue: currentName)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Group Photo") {
                    HStack(spacing: 16) {
                        AvatarView(image: nil, url: currentAvatarUrl, size: 72, name: draftName)

                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Text("Change Photo")
                                .foregroundColor(DesignTokens.accentColor)
                        }
                        .disabled(isSaving)
                    }
                    .listRowBackground(DesignTokens.surface)
                }

                Section("Group Name") {
                    TextField("Group name", text: $draftName)
                        .disabled(isSaving)
                        .listRowBackground(DesignTokens.surface)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                    }
                    .listRowBackground(DesignTokens.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.backgroundColor)
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                selectedImageData = try? await newItem.loadTransferable(type: Data.self)
            }
        }
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                errorMessage = "Group name cannot be empty."
                return
            }

            if trimmedName != currentName {
                try await matrixBridge.setRoomName(conversationOrRoomId: roomId, name: trimmedName)
            }

            var updatedAvatarUrl = currentAvatarUrl
            if let selectedImageData {
                // Default to JPEG; Matrix accepts PNG/JPEG, and JPEG is smaller.
                let mimeType = "image/jpeg"
                if let jpeg = UIImage(data: selectedImageData)?.jpegData(compressionQuality: 0.9) {
                    updatedAvatarUrl = try await matrixBridge.setRoomAvatar(
                        conversationOrRoomId: roomId,
                        imageData: jpeg,
                        mimeType: mimeType
                    )
                } else {
                    updatedAvatarUrl = try await matrixBridge.setRoomAvatar(
                        conversationOrRoomId: roomId,
                        imageData: selectedImageData,
                        mimeType: "image/png"
                    )
                }
            }

            onUpdated(trimmedName, updatedAvatarUrl)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    GroupSettingsView(
        isPresented: .constant(true),
        conversationId: "!room:matrix.org",
        groupName: "Test Group",
        memberCount: 5,
        onGroupInfoUpdated: nil
    )
}
