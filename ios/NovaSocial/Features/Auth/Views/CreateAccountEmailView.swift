import SwiftUI
import PhotosUI

// MARK: - Create Account View

struct CreateAccountEmailView: View {
    // MARK: - Bindings
    @Binding var currentPage: AppPage

    // MARK: - State
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedAvatar: UIImage?
    @State private var showErrorView = false
    @State private var isGoogleLoading = false
    @State private var isAppleLoading = false

    // MARK: - Focus State
    @FocusState private var focusedField: Field?

    enum Field {
        case email
        case username
        case password
        case confirmPassword
    }

    // Access global AuthenticationManager
    @EnvironmentObject private var authManager: AuthenticationManager

    // Access AvatarManager
    @StateObject private var avatarManager = AvatarManager.shared

    // Services
    private let mediaService = MediaService()
    private let identityService = IdentityService()

    var body: some View {
        GeometryReader { geometry in
        ZStack {
            // Background - Linear Gradient (same as InviteCodeView)
            LinearGradient(
                colors: [
                    Color(red: 0.027, green: 0.106, blue: 0.212),  // #071B36
                    Color(red: 0.271, green: 0.310, blue: 0.388)   // #454F63
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                if showErrorView, let error = errorMessage {
                    // Full-screen error view with retry
                    VStack {
                        Spacer()
                        ErrorStateView(
                            errorMessage: error,
                            onRetry: {
                                showErrorView = false
                                errorMessage = nil
                                await handleRegister()
                            },
                            onDismiss: {
                                showErrorView = false
                                errorMessage = nil
                            }
                        )
                        Spacer()
                    }
                } else {
                    // 使用固定高度替代Spacer，防止键盘推动布局
                    Color.clear
                        .frame(height: max(0, (geometry.size.height - 812) / 2))

                    // Main Content - 四个输入框整体
                    // 距顶部298pt, 左边距38pt, 右边距37pt, 框间距16pt
                    VStack {
                        Spacer().frame(height: 298.h)

                        ZStack {
                            Group {
                                // Email Input Field
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(width: 300.w, height: 48.h)
                                    .background(Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25))
                                    .cornerRadius(6.s)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6.s)
                                            .inset(by: 0.50)
                                            .stroke(.white, lineWidth: 0.50)
                                    )
                                    .offset(x: 0, y: -96.h)

                                // Username Input Field
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(width: 300.w, height: 48.h)
                                    .background(Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25))
                                    .cornerRadius(6.s)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6.s)
                                            .inset(by: 0.50)
                                            .stroke(.white, lineWidth: 0.50)
                                    )
                                    .offset(x: 0, y: -32.h)

                                // Password Input Field
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(width: 300.w, height: 48.h)
                                    .background(Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25))
                                    .cornerRadius(6.s)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6.s)
                                            .inset(by: 0.50)
                                            .stroke(.white, lineWidth: 0.50)
                                    )
                                    .offset(x: 0, y: 32.h)

                                // Confirm Password Input Field
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(width: 300.w, height: 48.h)
                                    .background(Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25))
                                    .cornerRadius(6.s)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6.s)
                                            .inset(by: 0.50)
                                            .stroke(.white, lineWidth: 0.50)
                                    )
                                    .offset(x: 0, y: 96.h)
                            }

                            Group {
                                // Text fields for input
                                TextField("", text: $email, prompt: Text("Enter your email").foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(.system(size: 14.f))
                                    .tracking(0.28)
                                    .padding(.horizontal, 16.w)
                                    .frame(width: 300.w, height: 48.h)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                                    .offset(x: 0, y: -96.h)
                                    .accessibilityIdentifier("emailTextField")

                                TextField("", text: $username, prompt: Text("Your username").foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(.system(size: 14.f))
                                    .tracking(0.28)
                                    .padding(.horizontal, 16.w)
                                    .frame(width: 300.w, height: 48.h)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .offset(x: 0, y: -32.h)
                                    .accessibilityIdentifier("usernameTextField")

                                // Password field
                                ZStack {
                                    if showPassword {
                                        TextField("", text: $password, prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.4)))
                                            .foregroundColor(.white)
                                            .font(.system(size: 14.f))
                                            .tracking(0.28)
                                            .padding(.horizontal, 16.w)
                                            .frame(width: 300.w, height: 48.h)
                                            .autocapitalization(.none)
                                            .autocorrectionDisabled()
                                            .textContentType(.password)
                                            .accessibilityIdentifier("passwordTextField")
                                            .focused($focusedField, equals: .password)
                                    } else {
                                        SecureField("", text: $password, prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.4)))
                                            .foregroundColor(.white)
                                            .font(.system(size: 14.f))
                                            .tracking(0.28)
                                            .padding(.horizontal, 16.w)
                                            .frame(width: 300.w, height: 48.h)
                                            .textContentType(.password)
                                            .accessibilityIdentifier("passwordTextField")
                                            .focused($focusedField, equals: .password)
                                    }

                                    // SHOW/HIDE button for password
                                    Button(action: {
                                        let wasFocused = focusedField == .password
                                        withAnimation(.none) { showPassword.toggle() }
                                        if wasFocused { focusedField = .password }
                                    }) {
                                        Image(systemName: showPassword ? "eye.slash" : "eye")
                                            .foregroundColor(.white.opacity(0.6))
                                            .frame(width: 24.s, height: 24.s)
                                    }
                                    .offset(x: 122.w, y: 0)
                                }
                                .offset(x: 0, y: 32.h)

                                // Confirm Password field
                                ZStack {
                                    if showConfirmPassword {
                                        TextField("", text: $confirmPassword, prompt: Text("Confirm your password").foregroundColor(Color.white.opacity(0.4)))
                                            .foregroundColor(.white)
                                            .font(.system(size: 14.f))
                                            .tracking(0.28)
                                            .padding(.horizontal, 16.w)
                                            .frame(width: 300.w, height: 48.h)
                                            .autocapitalization(.none)
                                            .autocorrectionDisabled()
                                            .textContentType(.password)
                                            .accessibilityIdentifier("confirmPasswordTextField")
                                            .focused($focusedField, equals: .confirmPassword)
                                    } else {
                                        SecureField("", text: $confirmPassword, prompt: Text("Confirm your password").foregroundColor(Color.white.opacity(0.4)))
                                            .foregroundColor(.white)
                                            .font(.system(size: 14.f))
                                            .tracking(0.28)
                                            .padding(.horizontal, 16.w)
                                            .frame(width: 300.w, height: 48.h)
                                            .textContentType(.password)
                                            .accessibilityIdentifier("confirmPasswordTextField")
                                            .focused($focusedField, equals: .confirmPassword)
                                    }

                                    // SHOW/HIDE button for confirm password
                                    Button(action: {
                                        let wasFocused = focusedField == .confirmPassword
                                        withAnimation(.none) { showConfirmPassword.toggle() }
                                        if wasFocused { focusedField = .confirmPassword }
                                    }) {
                                        Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                            .foregroundColor(.white.opacity(0.6))
                                            .frame(width: 24.s, height: 24.s)
                                    }
                                    .offset(x: 122.w, y: 0)
                                }
                                .offset(x: 0, y: 96.h)
                            }
                        }
                        .frame(width: 300.w, height: 240.h)
                        .padding(.leading, 38.w)
                        .padding(.trailing, 37.w)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Error Message (如果有)
                    if let errorMessage = errorMessage {
                        Text(LocalizedStringKey(errorMessage))
                            .font(.system(size: 12.f))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40.w)
                            .padding(.top, 550.h)
                    }

                    // 使用固定高度替代Spacer，防止键盘推动布局
                    Color.clear
                        .frame(height: max(0, (geometry.size.height - 812) / 2))
                }
            }

            // Logo - 顶部，居中
            VStack {
                Spacer().frame(height: 167.h)
                ZStack {
                    Image("Login-Icon")
                        .resizable()
                        .scaledToFit()
                }
                .frame(width: 84.w, height: 52.h)
                Spacer()
            }

            // Title - "Sign in with Email" 距顶部239pt，居中
            VStack {
                Spacer().frame(height: 239.h)
                Text("Sign in with Email")
                    .font(.system(size: 24.f, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
            }

            // Back Button - 左上角
            VStack {
                HStack {
                    Button(action: { currentPage = .createAccount }) {
                        Image("back-white")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24.s, height: 24.s)
                    }
                    .padding(.leading, 16.w)
                    .padding(.top, 56.h)
                    Spacer()
                }
                Spacer()
            }

            // Next Button - 距底部202pt
            VStack {
                Spacer()
                Button(action: {
                    Task {
                        await handleRegister()
                    }
                }) {
                    HStack(spacing: 8.s) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        }
                        Text("Next")
                            .font(.system(size: 16.f, weight: .heavy))
                            .tracking(0.32)
                            .foregroundColor(.black)
                    }
                    .frame(width: 300.w, height: 48.h)
                    .background(.white)
                    .cornerRadius(43.s)
                }
                .disabled(isLoading)
                .padding(.leading, 38.w)
                .padding(.trailing, 37.w)
                .padding(.bottom, 202.h)
            }

            // "Already have an account? Sign in" - 距底部140pt，居中
            VStack {
                Spacer()
                HStack(spacing: 0) {
                    Text("Already have an account? ")
                        .font(.system(size: 14.f))
                        .tracking(0.28)
                        .foregroundColor(.white)

                    Button(action: {
                        currentPage = .login
                    }) {
                        Text("Sign in")
                            .font(.system(size: 14.f, weight: .bold))
                            .tracking(0.28)
                            .underline()
                            .foregroundColor(.white)
                    }
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.bottom, 140.h)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .onChange(of: selectedPhotoItem) { oldValue, newValue in
            Task {
                if let photoItem = newValue,
                   let data = try? await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    // 显示选择的头像
                    selectedAvatar = image
                    // 保存到 AvatarManager
                    avatarManager.savePendingAvatar(image)

                    #if DEBUG
                    print("[CreateAccountEmailView] 头像已选择并保存")
                    #endif
                }
            }
        }
        } // GeometryReader
    }

    // MARK: - Actions

    private func handleRegister() async {
        guard validateRegister() else { return }

        isLoading = true
        errorMessage = nil
        showErrorView = false

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalInviteCode = inviteCode.isEmpty ? "NOVATEST" : inviteCode

        #if DEBUG
        print("[CreateAccountEmailView] Starting registration")
        print("[CreateAccountEmailView] Username: \(trimmedUsername)")
        print("[CreateAccountEmailView] Email: \(trimmedEmail)")
        print("[CreateAccountEmailView] Invite Code: \(finalInviteCode)")
        #endif

        do {
            let user = try await authManager.register(
                username: trimmedUsername,
                email: trimmedEmail,
                password: password,
                displayName: displayName.isEmpty ? username : displayName,
                inviteCode: finalInviteCode
            )

            await uploadAvatarIfNeeded(userId: user.id)
            #if DEBUG
            print("[CreateAccountEmailView] Registration successful!")
            #endif
            // Success - Navigate to home page
            await MainActor.run {
                currentPage = .home
            }
        } catch {
            #if DEBUG
            print("[CreateAccountEmailView] Registration error: \(error)")
            print("[CreateAccountEmailView] Error type: \(type(of: error))")
            print("[CreateAccountEmailView] Error description: \(error.localizedDescription)")
            #endif

            // Provide user-friendly error messages
            if error.localizedDescription.contains("409") || error.localizedDescription.contains("already exists") {
                errorMessage = "This username or email is already registered. Please try a different one."
                showErrorView = true
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                errorMessage = "Unable to connect to the server. Please check your internet connection and try again."
                showErrorView = true
            } else if error.localizedDescription.contains("invite") || error.localizedDescription.contains("code") {
                errorMessage = "Invalid invite code. Please check your code and try again."
                showErrorView = true
            } else {
                errorMessage = "Registration failed. Please try again later."
                showErrorView = true
            }
        }

        isLoading = false
    }

    private func uploadAvatarIfNeeded(userId: String) async {
        guard let image = selectedAvatar ?? avatarManager.getPendingAvatar(),
              let imageData = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        do {
            let avatarUrl = try await mediaService.uploadImage(imageData: imageData, filename: "avatar.jpg")
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
                avatarManager.clearPendingAvatar()
            }
            #if DEBUG
            print("[CreateAccountEmailView] Avatar uploaded after registration: \(avatarUrl)")
            #endif
        } catch {
            #if DEBUG
            print("[CreateAccountEmailView] Avatar upload failed after registration: \(error)")
            #endif
            // Non-blocking: registration success should not fail due to avatar upload
        }
    }

    // MARK: - Validation

    private func validateRegister() -> Bool {
            if email.isEmpty {
                errorMessage = "Please_enter_an_email"
            return false
        }

            if !isValidEmail(email) {
                errorMessage = "Please_enter_a_valid_email"
            return false
        }

            if username.isEmpty {
                errorMessage = "Please_enter_a_username"
            return false
        }

            if password.isEmpty {
                errorMessage = "Please_enter_a_password"
            return false
        }

        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters"
            return false
        }

        if !isStrongPassword(password) {
            errorMessage = "Password must be at least 6 characters"
            return false
        }

        if confirmPassword.isEmpty {
            errorMessage = "Please confirm your password"
            return false
        }

            if password != confirmPassword {
                errorMessage = "Passwords_do_not_match"
            return false
        }

        return true
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    private func isStrongPassword(_ password: String) -> Bool {
        // Simplified validation - only check minimum length
        return password.count >= 6
    }

    // MARK: - Social Login

    private func handleGoogleSignIn() async {
        isGoogleLoading = true
        errorMessage = nil

        do {
            let _ = try await authManager.loginWithGoogle()
            await MainActor.run {
                currentPage = .home
            }
        } catch {
            #if DEBUG
            print("[CreateAccountEmailView] Google sign in error: \(error)")
            #endif
            errorMessage = "Google sign in failed. Please try again."
            showErrorView = true
        }

        isGoogleLoading = false
    }

    private func handleAppleSignIn() async {
        isAppleLoading = true
        errorMessage = nil

        do {
            let _ = try await authManager.loginWithApple()
            await MainActor.run {
                currentPage = .home
            }
        } catch {
            #if DEBUG
            print("[CreateAccountEmailView] Apple sign in error: \(error)")
            #endif
            errorMessage = "Apple sign in failed. Please try again."
            showErrorView = true
        }

        isAppleLoading = false
    }
}

// MARK: - Preview

#Preview {
    CreateAccountEmailView(currentPage: .constant(.createAccount))
        .environmentObject(AuthenticationManager.shared)
}
