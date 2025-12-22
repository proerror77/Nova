import SwiftUI
import PhotosUI

// MARK: - Edit Profile View
/// 編輯個人資料視圖
/// 允許用戶編輯顯示名稱、簡介和位置
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthenticationManager

    // MARK: - State
    @State private var displayName: String = ""
    @State private var bio: String = ""
    @State private var location: String = ""
    @State private var website: String = ""

    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasChanges = false

    // Avatar States
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedAvatarImage: UIImage?
    @State private var isUploadingAvatar = false

    // Services
    private let identityService = IdentityService()
    private let mediaService = MediaService()

    // Callback for successful update
    var onProfileUpdated: (() -> Void)?

    // MARK: - Character Limits
    private let displayNameLimit = 50
    private let bioLimit = 160
    private let locationLimit = 100
    private let websiteLimit = 100

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Avatar Section
                    avatarSection

                    // MARK: - Form Fields
                    VStack(spacing: 20) {
                        // Display Name
                        editField(
                            title: "顯示名稱",
                            placeholder: "輸入顯示名稱",
                            text: $displayName,
                            limit: displayNameLimit
                        )

                        // Bio
                        editTextArea(
                            title: "簡介",
                            placeholder: "介紹一下自己...",
                            text: $bio,
                            limit: bioLimit
                        )

                        // Location
                        editField(
                            title: "位置",
                            placeholder: "你在哪裡？",
                            text: $location,
                            limit: locationLimit,
                            icon: "location.fill"
                        )

                        // Website
                        editField(
                            title: "網站",
                            placeholder: "https://example.com",
                            text: $website,
                            limit: websiteLimit,
                            icon: "link",
                            keyboardType: .URL
                        )
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 20)
                .padding(.bottom, 100)
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("編輯個人資料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        Task {
                            await saveProfile()
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(hasChanges ? DesignTokens.accentColor : .gray)
                    .disabled(!hasChanges || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                }
            }
            .alert("錯誤", isPresented: $showError) {
                Button("確定", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadCurrentProfile()
            }
            .onChange(of: displayName) { _, _ in checkForChanges() }
            .onChange(of: bio) { _, _ in checkForChanges() }
            .onChange(of: location) { _, _ in checkForChanges() }
            .onChange(of: website) { _, _ in checkForChanges() }
        }
    }

    // MARK: - Avatar Section
    private var avatarSection: some View {
        VStack(spacing: 12) {
            // Avatar Image with PhotosPicker
            let currentAvatarUrl = authManager.currentUser?.avatarUrl
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                ZStack {
                    // Show selected image, or current avatar, or default
                    if let selectedImage = selectedAvatarImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                    } else if let avatarUrl = currentAvatarUrl,
                              let url = URL(string: avatarUrl) {
                        CachedAsyncImage(
                            url: url,
                            targetSize: CGSize(width: 200, height: 200),
                            enableProgressiveLoading: false,
                            priority: .high
                        ) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                    } else {
                        DefaultAvatarView(size: 100)
                    }

                    // Camera overlay
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 100, height: 100)
                        .overlay {
                            if isUploadingAvatar {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                        }
                        .opacity(0.7)
                }
            }
            .disabled(isUploadingAvatar)
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    await loadSelectedPhoto(from: newItem)
                }
            }

            Text(isUploadingAvatar ? "上傳中..." : "點擊更換頭像")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Load Selected Photo
    private func loadSelectedPhoto(from item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    selectedAvatarImage = image
                    hasChanges = true
                }

                // Upload avatar immediately
                await uploadAvatar(image)
            }
        } catch {
            await MainActor.run {
                errorMessage = "無法載入圖片：\(error.localizedDescription)"
                showError = true
            }
        }
    }

    // MARK: - Upload Avatar
    private func uploadAvatar(_ image: UIImage) async {
        guard let userId = authManager.currentUser?.id,
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        await MainActor.run {
            isUploadingAvatar = true
        }

        do {
            // Upload image to MediaService
            let avatarUrl = try await mediaService.uploadImage(image: imageData, userId: userId)

            // Update profile with new avatar URL
            let updates = UserProfileUpdate(
                displayName: nil,
                bio: nil,
                avatarUrl: avatarUrl,
                coverUrl: nil,
                website: nil,
                location: nil
            )

            let updatedUser = try await identityService.updateUser(userId: userId, updates: updates)

            await MainActor.run {
                authManager.updateCurrentUser(updatedUser)
                isUploadingAvatar = false
            }

            #if DEBUG
            print("✅ Avatar uploaded successfully: \(avatarUrl)")
            #endif
        } catch {
            await MainActor.run {
                isUploadingAvatar = false
                errorMessage = "頭像上傳失敗：\(error.localizedDescription)"
                showError = true
                // Revert to original avatar
                selectedAvatarImage = nil
            }
        }
    }

    // MARK: - Edit Field
    private func editField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        limit: Int,
        icon: String? = nil,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title with character count
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(text.wrappedValue.count)/\(limit)")
                    .font(.system(size: 12))
                    .foregroundColor(text.wrappedValue.count > limit ? .red : .secondary)
            }

            // Input field
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                }

                TextField(placeholder, text: text)
                    .font(.system(size: 16))
                    .keyboardType(keyboardType)
                    .autocapitalization(keyboardType == .URL ? .none : .words)
                    .disableAutocorrection(keyboardType == .URL)
            }
            .padding(14)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Edit Text Area (for bio)
    private func editTextArea(
        title: String,
        placeholder: String,
        text: Binding<String>,
        limit: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title with character count
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(text.wrappedValue.count)/\(limit)")
                    .font(.system(size: 12))
                    .foregroundColor(text.wrappedValue.count > limit ? .red : .secondary)
            }

            // Text editor
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 16))
                        .foregroundColor(Color(UIColor.placeholderText))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }

                TextEditor(text: text)
                    .font(.system(size: 16))
                    .frame(minHeight: 100)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .background(Color(UIColor.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Load Current Profile
    private func loadCurrentProfile() {
        guard let user = authManager.currentUser else { return }

        displayName = user.displayName ?? ""
        bio = user.bio ?? ""
        location = user.location ?? ""
        website = user.website ?? ""

        // Reset hasChanges after loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            hasChanges = false
        }
    }

    // MARK: - Check for Changes
    private func checkForChanges() {
        guard let user = authManager.currentUser else {
            hasChanges = false
            return
        }

        let originalDisplayName = user.displayName ?? ""
        let originalBio = user.bio ?? ""
        let originalLocation = user.location ?? ""
        let originalWebsite = user.website ?? ""

        hasChanges = displayName != originalDisplayName ||
                     bio != originalBio ||
                     location != originalLocation ||
                     website != originalWebsite
    }

    // MARK: - Save Profile
    private func saveProfile() async {
        guard let userId = authManager.currentUser?.id else {
            errorMessage = "無法獲取用戶資訊"
            showError = true
            return
        }

        // Validate limits
        if displayName.count > displayNameLimit {
            errorMessage = "顯示名稱超過字數限制"
            showError = true
            return
        }

        if bio.count > bioLimit {
            errorMessage = "簡介超過字數限制"
            showError = true
            return
        }

        isLoading = true

        do {
            let updates = UserProfileUpdate(
                displayName: displayName.isEmpty ? nil : displayName,
                bio: bio.isEmpty ? nil : bio,
                avatarUrl: nil,  // Avatar is updated separately
                coverUrl: nil,
                website: website.isEmpty ? nil : website,
                location: location.isEmpty ? nil : location
            )

            let updatedUser = try await identityService.updateUser(
                userId: userId,
                updates: updates
            )

            // Update local auth manager
            await MainActor.run {
                authManager.updateCurrentUser(updatedUser)
                isLoading = false
                onProfileUpdated?()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "更新失敗：\(error.localizedDescription)"
                showError = true
            }
        }
    }
}

// MARK: - Preview
#Preview {
    EditProfileView()
        .environmentObject(AuthenticationManager.shared)
}
