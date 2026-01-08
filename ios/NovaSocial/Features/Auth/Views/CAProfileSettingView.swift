import SwiftUI
import PhotosUI

struct CAProfileSettingView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager

    // Form fields
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var dateOfBirth: Date?
    @State private var location = ""

    // Profile image
    @State private var selectedImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem?

    // UI State
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDatePicker = false
    @State private var showLocationPicker = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case firstName, lastName, username
    }

    // Colors from Figma
    private let backgroundColor = Color(red: 0.03, green: 0.11, blue: 0.21)  // #071B36
    private let cardBackground = Color(red: 1, green: 1, blue: 1).opacity(0.20)  // White 20%
    private let nameCardBackground = Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25)  // Gray 25%
    private let pinkAccent = Color(red: 0.87, green: 0.11, blue: 0.26)  // #DE1C42
    private let placeholderColor = Color(red: 0.75, green: 0.75, blue: 0.75)  // #BFBFBF
    private let avatarGray = Color(red: 0.85, green: 0.85, blue: 0.85)  // #D9D9D9

    // Validation
    private var isFormValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        username.count >= 3
    }

    private var formattedDateOfBirth: String {
        guard let date = dateOfBirth else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date)
    }

    var body: some View {
        ZStack {
            // Background - Solid color from Figma
            backgroundColor

            // Content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 110.h)  // Figma: 44 status + 46 header + 20 spacing

                    // Profile Image Picker
                    profileImageSection

                    Spacer().frame(height: 20.h)

                    // Form Fields
                    VStack(spacing: 16.h) {
                        // Name Card (First + Last name grouped)
                        nameCard

                        // Username Card
                        usernameCard

                        // Date of Birth Card
                        dateOfBirthCard

                        // Location Card
                        locationCard
                    }
                    .frame(width: 301.w)

                    // Error Message
                    errorMessageView

                    Spacer().frame(height: 32.h)

                    // Submit Button
                    submitButton
                        .frame(width: 301.w)

                    Spacer().frame(height: 40.h)
                }
                .frame(maxWidth: .infinity)
            }

            // Back Button Header - Figma: 375x64, padding 8
            VStack(spacing: 0) {
                Spacer().frame(height: 44.h)  // Status bar safe area
                HStack(spacing: 8.s) {
                    Button(action: { currentPage = .createAccount }) {
                        ZStack {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 40.s, height: 40.s)
                            Image(systemName: "chevron.left")
                                .font(.system(size: 24.f, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 24.s, height: 24.s)
                        }
                        .frame(width: 48.s, height: 48.s)
                    }
                    Spacer()
                }
                .padding(8.s)
                .frame(height: 46.h)  // Figma: 46pt header height
                Spacer()
            }

            // Date Picker Overlay
            if showDatePicker {
                datePickerOverlay
            }

            // Location Picker Overlay
            if showLocationPicker {
                locationPickerOverlay
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, newItem in
            Task {
                guard let photoItem = newItem else { return }

                do {
                    guard let data = try await photoItem.loadTransferable(type: Data.self) else {
                        await MainActor.run {
                            errorMessage = "Unable to load the selected photo"
                        }
                        return
                    }

                    guard let image = UIImage(data: data) else {
                        await MainActor.run {
                            errorMessage = "The selected image format is not supported"
                        }
                        return
                    }

                    await MainActor.run {
                        selectedImage = image
                        errorMessage = nil
                    }
                } catch {
                    #if DEBUG
                    print("[CAProfileSettingView] Photo loading error: \(error)")
                    #endif
                    await MainActor.run {
                        errorMessage = "Failed to load photo. Please try a different image."
                    }
                }
            }
        }
        .onAppear {
            validateVerificationTokens()
        }
    }

    // MARK: - Token Validation

    private func validateVerificationTokens() {
        // If user is already authenticated (came from old email registration flow),
        // they can still complete their profile
        if authManager.isAuthenticated {
            #if DEBUG
            print("[CAProfileSettingView] User already authenticated, allowing profile completion")
            #endif
            return
        }

        // For verification flow, check if tokens are valid
        if !authManager.hasValidVerificationToken {
            #if DEBUG
            print("[CAProfileSettingView] No valid verification token found, redirecting")
            #endif
            errorMessage = "Verification expired. Please verify your email or phone again."
            // Navigate back to create account
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                currentPage = .createAccount
            }
        }
    }

    // MARK: - Profile Image Section

    private var profileImageSection: some View {
        Button(action: { showPhotoPicker = true }) {
            ZStack {
                // Pink Ring Border (103x103 with 1pt stroke)
                Circle()
                    .stroke(pinkAccent, lineWidth: 2)
                    .frame(width: 103.s, height: 103.s)

                // Inner Gray Circle (90x90)
                Circle()
                    .fill(avatarGray)
                    .frame(width: 90.s, height: 90.s)

                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 90.s, height: 90.s)
                        .clipShape(Circle())
                }

                // Plus Badge (24x24) - 右下角
                ZStack {
                    Circle()
                        .fill(pinkAccent)
                        .frame(width: 24.s, height: 24.s)

                    Image(systemName: "plus")
                        .font(.system(size: 12.f, weight: .bold))
                        .foregroundColor(.white)
                }
                .offset(x: 38.s, y: 38.s)
            }
            .frame(width: 110.s, height: 110.s)
        }
        .padding(.vertical, 20.h)
    }

    // MARK: - Name Card (First + Last name grouped)

    private var nameCard: some View {
        VStack(spacing: 0) {
            // First Name
            HStack(spacing: 10) {
                TextField("", text: $firstName, prompt: Text("First name")
                    .font(Font.custom("SF Pro Display", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(placeholderColor))
                    .font(Font.custom("SF Pro Display", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(.white)
                    .focused($focusedField, equals: .firstName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
            }
            .frame(width: 269.w, alignment: .leading)
            .frame(height: 24.h)
            
            Spacer().frame(height: 12.h)
            
            // Divider line
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 269.w, height: 1)
            
            Spacer().frame(height: 12.h)

            // Last Name
            HStack(spacing: 10) {
                TextField("", text: $lastName, prompt: Text("Last name")
                    .font(Font.custom("SF Pro Display", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(placeholderColor))
                    .font(Font.custom("SF Pro Display", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(.white)
                    .focused($focusedField, equals: .lastName)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
            }
            .frame(width: 269.w, alignment: .leading)
            .frame(height: 24.h)
        }
        .padding(EdgeInsets(top: 16.h, leading: 16.w, bottom: 16.h, trailing: 16.w))
        .frame(width: 301.w)
        .background(nameCardBackground)
        .cornerRadius(6.s)
        .overlay(
            RoundedRectangle(cornerRadius: 6.s)
                .inset(by: 0.5)
                .stroke(.white, lineWidth: 0.5)
        )
    }

    // MARK: - Username Card

    private var usernameCard: some View {
        VStack(alignment: .leading, spacing: 8.h) {
            HStack(spacing: 10) {
                TextField("", text: $username, prompt: Text("Username")
                    .font(Font.custom("SF Pro Display", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(placeholderColor))
                    .font(Font.custom("SF Pro Display", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(.white)
                    .focused($focusedField, equals: .username)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: username) { _, newValue in
                        let filtered = newValue.filter { $0.isLetter || $0.isNumber || $0 == "_" }
                        if filtered != newValue {
                            username = filtered
                        }
                    }
            }
            .padding(16.s)
            .frame(width: 301.w)
            .background(cardBackground)
            .cornerRadius(5.s)
            .overlay(
                RoundedRectangle(cornerRadius: 5.s)
                    .stroke(.white, lineWidth: 0.5)
            )

            Text("Choose wisely.  Username may not be changed.")
                .font(Font.custom("SF Pro Display", size: 12.f))
                .tracking(0.24)
                .foregroundColor(placeholderColor)
        }
    }

    // MARK: - Date of Birth Card

    private var dateOfBirthCard: some View {
        Button(action: {
            focusedField = nil
            withAnimation(.easeInOut(duration: 0.3)) {
                showDatePicker = true
            }
        }) {
            HStack(spacing: 10) {
                Text(dateOfBirth == nil ? "Date of Birth" : formattedDateOfBirth)
                    .font(Font.custom("SF Pro Display", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(dateOfBirth == nil ? placeholderColor : .white)
                Spacer()
            }
            .padding(16.s)
            .frame(width: 301.w)
            .background(cardBackground)
            .cornerRadius(5.s)
            .overlay(
                RoundedRectangle(cornerRadius: 5.s)
                    .stroke(.white, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Location Card

    private var locationCard: some View {
        Button(action: {
            focusedField = nil
            withAnimation(.easeInOut(duration: 0.3)) {
                showLocationPicker = true
            }
        }) {
            HStack(spacing: 10) {
                Text(location.isEmpty ? "Location" : location)
                    .font(Font.custom("SF Pro Display", size: 14.f))
                    .tracking(0.28)
                    .foregroundColor(location.isEmpty ? placeholderColor : .white)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14.f, weight: .medium))
                    .foregroundColor(placeholderColor)
                    .frame(width: 24.s, height: 24.s)
            }
            .padding(16.s)
            .frame(width: 301.w)
            .background(cardBackground)
            .cornerRadius(5.s)
            .overlay(
                RoundedRectangle(cornerRadius: 5.s)
                    .stroke(.white, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Error Message

    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage {
            Text(LocalizedStringKey(errorMessage))
                .font(Font.custom("SF Pro Display", size: 12.f))
                .tracking(0.24)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .frame(width: 301.w)
                .padding(.top, 12.h)
        }
    }

    // MARK: - Submit Button

    private var submitButton: some View {
        Button(action: { Task { await submitProfile() } }) {
            HStack(spacing: 10.s) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.03, green: 0.11, blue: 0.21)))
                        .scaleEffect(0.9)
                }
                Text("Submit")
                    .font(Font.custom("SF Pro Display", size: 16.f).weight(.bold))
                    .foregroundColor(Color(red: 0.03, green: 0.11, blue: 0.21))
            }
            .frame(width: 301.w, height: 48.h)
            .background(Color(red: 1, green: 1, blue: 1))
            .cornerRadius(50.s)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isFormValid && !isLoading)
    }

    // MARK: - Date Picker Overlay

    private var datePickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showDatePicker = false
                    }
                }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showDatePicker = false
                        }
                    }
                    .font(Font.custom("SF Pro Display", size: 16.f))
                    .foregroundColor(.white)

                    Spacer()

                    Text("Date of Birth")
                        .font(Font.custom("SF Pro Display", size: 16.f).weight(.semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Button("Done") {
                        if dateOfBirth == nil {
                            dateOfBirth = Calendar.current.date(byAdding: .year, value: -18, to: Date())
                        }
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showDatePicker = false
                        }
                    }
                    .font(Font.custom("SF Pro Display", size: 16.f).weight(.semibold))
                    .foregroundColor(pinkAccent)
                }
                .padding(.horizontal, 16.w)
                .padding(.vertical, 12.h)

                Divider()
                    .background(Color.white.opacity(0.2))

                DatePicker(
                    "",
                    selection: Binding(
                        get: { dateOfBirth ?? Calendar.current.date(byAdding: .year, value: -18, to: Date())! },
                        set: { dateOfBirth = $0 }
                    ),
                    in: ...Calendar.current.date(byAdding: .year, value: -13, to: Date())!,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .padding(.horizontal, 16.w)
                .padding(.bottom, 20.h)
            }
            .background(backgroundColor)
            .cornerRadius(16.s)
            .padding(.horizontal, 24.w)
        }
    }

    // MARK: - Location Picker Overlay

    private var locationPickerOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showLocationPicker = false
                    }
                }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showLocationPicker = false
                        }
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16.f, weight: .medium))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Text("Location")
                        .font(Font.custom("SF Pro Display", size: 16.f).weight(.semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showLocationPicker = false
                        }
                    }
                    .font(Font.custom("SF Pro Display", size: 16.f).weight(.semibold))
                    .foregroundColor(pinkAccent)
                }
                .padding(.horizontal, 16.w)
                .padding(.vertical, 12.h)

                Divider()
                    .background(Color.white.opacity(0.2))

                // Location List
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sampleLocations, id: \.self) { loc in
                            Button(action: {
                                location = loc
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    showLocationPicker = false
                                }
                            }) {
                                HStack {
                                    Text(loc)
                                        .font(Font.custom("SF Pro Display", size: 14.f))
                                        .tracking(0.28)
                                        .foregroundColor(.white)
                                    Spacer()
                                    if location == loc {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14.f, weight: .medium))
                                            .foregroundColor(pinkAccent)
                                    }
                                }
                                .padding(.horizontal, 16.w)
                                .padding(.vertical, 14.h)
                            }

                            Divider()
                                .background(Color.white.opacity(0.1))
                        }
                    }
                }
                .frame(maxHeight: 300.h)
            }
            .background(backgroundColor)
            .cornerRadius(16.s)
            .padding(.horizontal, 24.w)
        }
    }

    // Sample locations
    private var sampleLocations: [String] {
        [
            "China's Mainland Shanghai",
            "United States New York",
            "United States Los Angeles",
            "United Kingdom London",
            "Japan Tokyo",
            "Singapore",
            "Hong Kong",
            "Australia Sydney"
        ]
    }

    // MARK: - Actions

    private let identityService = IdentityService()
    private let mediaService = MediaService()

    private func submitProfile() async {
        guard isFormValid else { return }

        isLoading = true
        errorMessage = nil

        do {
            // Check if user is already authenticated (came from old email registration)
            if authManager.isAuthenticated, let userId = authManager.currentUser?.id {
                // Use profile UPDATE flow for already authenticated users
                try await updateExistingProfile(userId: userId)
                return
            }

            // Use profile SETUP flow for verification-based registration
            let profileService = ProfileSetupService.shared
            let response: ProfileSetupService.ProfileSetupResponse

            // Determine which flow (email or phone) based on what's verified
            if let email = authManager.verifiedEmail,
               let verificationToken = authManager.emailVerificationToken,
               authManager.isEmailVerificationTokenValid {
                // Email-based registration
                response = try await profileService.completeEmailProfileSetup(
                    email: email,
                    verificationToken: verificationToken,
                    username: username,
                    firstName: firstName.isEmpty ? nil : firstName,
                    lastName: lastName.isEmpty ? nil : lastName,
                    dateOfBirth: dateOfBirth,
                    location: location.isEmpty ? nil : location,
                    avatarImage: selectedImage,
                    inviteCode: authManager.validatedInviteCode
                )
            } else if let phoneNumber = authManager.verifiedPhoneNumber,
                      let verificationToken = authManager.phoneVerificationToken,
                      authManager.isPhoneVerificationTokenValid {
                // Phone-based registration
                response = try await profileService.completePhoneProfileSetup(
                    phoneNumber: phoneNumber,
                    verificationToken: verificationToken,
                    username: username,
                    firstName: firstName.isEmpty ? nil : firstName,
                    lastName: lastName.isEmpty ? nil : lastName,
                    dateOfBirth: dateOfBirth,
                    location: location.isEmpty ? nil : location,
                    avatarImage: selectedImage,
                    inviteCode: authManager.validatedInviteCode
                )
            } else {
                throw ProfileSetupError.invalidVerificationToken
            }

            // Save authentication
            APIClient.shared.setAuthToken(response.token)

            // Update auth manager with new user
            await MainActor.run {
                authManager.updateCurrentUser(response.user)
                authManager.isAuthenticated = true
                authManager.clearVerificationTokens()
                authManager.validatedInviteCode = nil

                // Navigate to home
                currentPage = .home
            }

            #if DEBUG
            print("[CAProfileSettingView] Profile created successfully: \(response.user.id)")
            #endif

        } catch let error as ProfileSetupError {
            #if DEBUG
            print("[CAProfileSettingView] Profile setup error: \(error)")
            #endif
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        } catch {
            #if DEBUG
            print("[CAProfileSettingView] Unexpected error: \(error)")
            #endif
            await MainActor.run {
                errorMessage = "Failed to create profile. Please try again."
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    /// Update profile for already authenticated users (from old email registration flow)
    private func updateExistingProfile(userId: String) async throws {
        #if DEBUG
        print("[CAProfileSettingView] Updating existing profile for user: \(userId)")
        #endif

        // Upload avatar if provided
        var avatarUrl: String? = nil
        if let image = selectedImage,
           let imageData = image.jpegData(compressionQuality: 0.8) {
            avatarUrl = try await mediaService.uploadImage(
                imageData: imageData,
                filename: "avatar_\(UUID().uuidString).jpg"
            )
        }

        // Build display name from first + last name
        let displayName: String?
        if !firstName.isEmpty || !lastName.isEmpty {
            displayName = [firstName, lastName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } else {
            displayName = nil
        }

        // Update user profile
        let updates = UserProfileUpdate(
            displayName: displayName,
            bio: nil,
            avatarUrl: avatarUrl,
            coverUrl: nil,
            website: nil,
            location: location.isEmpty ? nil : location
        )

        let updatedUser = try await identityService.updateUser(userId: userId, updates: updates)

        await MainActor.run {
            authManager.updateCurrentUser(updatedUser)
            isLoading = false
            currentPage = .home
        }

        #if DEBUG
        print("[CAProfileSettingView] Profile updated successfully for: \(userId)")
        #endif
    }
}

#Preview {
    CAProfileSettingView(currentPage: .constant(.profileSetup))
        .environmentObject(AuthenticationManager.shared)
}
