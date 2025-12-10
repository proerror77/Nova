import SwiftUI
import PhotosUI

// MARK: - Create Account View

struct CreateAccountView: View {
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

    var body: some View {
        ZStack {
            // Background Image - Fixed size to prevent scaling when keyboard appears
            Image("Registration-background")
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea(.all)

            // Dark overlay to dim the background
            Color.black
                .opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 使用固定高度替代Spacer，防止键盘推动布局
                Color.clear
                    .frame(height: max(0, (UIScreen.main.bounds.height - 812) / 2))

                // Main Content
                ZStack {
                    Group {
                        // Profile Picture Circle - 显示选择的头像或默认头像
                        AvatarView(image: selectedAvatar, url: nil, size: 136)
                            .offset(x: 0.50, y: -290)

                        // Add Photo Button - 使用 PhotosPicker
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.87, green: 0.11, blue: 0.26))
                                    .frame(width: 35, height: 35)

                                Image(systemName: selectedAvatar != nil ? "checkmark" : "plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                            }
                        }
                        .offset(x: 48, y: -242.50)


                        // SHOW button for PASSWORD - 优化点击响应
                        Button(action: {
                            // 直接切换显示状态，不需要延迟
                            let wasFocused = focusedField == .password
                            withAnimation(.none) {
                                showPassword.toggle()
                            }
                            // 如果之前有焦点，立即恢复焦点
                            if wasFocused {
                                focusedField = .password
                            }
                        }) {
                            Text(showPassword ? "HIDE" : "SHOW")
                                .font(.system(size: 12, weight: .light))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                                .padding(.horizontal, 30)
                                .padding(.vertical, 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 138.50, y: -20)

                        // SHOW button for CONFIRM PASSWORD - 优化点击响应
                        Button(action: {
                            // 直接切换显示状态，不需要延迟
                            let wasFocused = focusedField == .confirmPassword
                            withAnimation(.none) {
                                showConfirmPassword.toggle()
                            }
                            // 如果之前有焦点，立即恢复焦点
                            if wasFocused {
                                focusedField = .confirmPassword
                            }
                        }) {
                            Text(showConfirmPassword ? "HIDE" : "SHOW")
                                .font(.system(size: 12, weight: .light))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                                .padding(.horizontal, 30)
                                .padding(.vertical, 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 138.50, y: 49)

                        // Email Input Field
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 343, height: 49)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .inset(by: 0.20)
                                    .stroke(.white, lineWidth: 0.20)
                            )
                            .offset(x: 0, y: -157.50)

                        // Username Input Field
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 343, height: 49)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .inset(by: 0.20)
                                    .stroke(.white, lineWidth: 0.20)
                            )
                            .offset(x: 0, y: -88.50)

                        // Password Input Field
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 343, height: 49)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .inset(by: 0.20)
                                    .stroke(.white, lineWidth: 0.20)
                            )
                            .offset(x: 0, y: -19.50)

                        // Confirm Password Input Field
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 343, height: 49)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .inset(by: 0.20)
                                    .stroke(.white, lineWidth: 0.20)
                            )
                            .offset(x: 0, y: 49.50)
                    }

                    Group {
                        // Text fields for input
                        TextField("", text: $email, prompt: Text("Enter your email").foregroundColor(Color.white.opacity(0.4)))
                            .foregroundColor(.white)
                            .font(.system(size: 14))
                            .padding(.horizontal, 16)
                            .frame(width: 343, height: 49)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .offset(x: 0, y: -157.50)
                            .accessibilityIdentifier("emailTextField")

                        TextField("", text: $username, prompt: Text("Your Username").foregroundColor(Color.white.opacity(0.4)))
                            .foregroundColor(.white)
                            .font(.system(size: 14))
                            .padding(.horizontal, 16)
                            .frame(width: 343, height: 49)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .offset(x: 0, y: -88.50)
                            .accessibilityIdentifier("usernameTextField")

                        // Password field - 优化版本，避免视图重建
                        Group {
                            if showPassword {
                                TextField("", text: $password, prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .textContentType(.password)
                                    .accessibilityIdentifier("passwordTextField")
                                    .focused($focusedField, equals: .password)
                            } else {
                                SecureField("", text: $password, prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .textContentType(.password)
                                    .accessibilityIdentifier("passwordTextField")
                                    .focused($focusedField, equals: .password)
                            }
                        }
                        .offset(x: 0, y: -19.50)

                        // Confirm Password field - 优化版本，避免视图重建
                        Group {
                            if showConfirmPassword {
                                TextField("", text: $confirmPassword, prompt: Text("Confirm your password").foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .textContentType(.password)
                                    .accessibilityIdentifier("confirmPasswordTextField")
                                    .focused($focusedField, equals: .confirmPassword)
                            } else {
                                SecureField("", text: $confirmPassword, prompt: Text("Confirm your password").foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .textContentType(.password)
                                    .accessibilityIdentifier("confirmPasswordTextField")
                                    .focused($focusedField, equals: .confirmPassword)
                            }
                        }
                        .offset(x: 0, y: 49.50)

                        // Sign up Button
                        Button(action: {
                            Task {
                                await handleRegister()
                            }
                        }) {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                                Text(LocalizedStringKey("Sign_Up"))
                                    .font(.system(size: 16, weight: .medium))
                                    .lineSpacing(20)
                                    .foregroundColor(.white)
                            }
                            .frame(width: 343, height: 46)
                            .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .cornerRadius(31.50)
                        }
                        .disabled(isLoading)
                        .offset(x: 0, y: 137)
                        .accessibilityIdentifier("signUpButton")

                        // "or you can" text
                        Text(LocalizedStringKey("Or_you_can"))
                            .font(.system(size: 16, weight: .medium))
                            .lineSpacing(20)
                            .foregroundColor(.white)
                            .offset(x: 0.50, y: 200)

                        // Decorative lines
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 120, height: 0)
                            .overlay(Rectangle()
                                .stroke(.white, lineWidth: 0.20))
                            .offset(x: -111.50, y: 202)

                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 120, height: 0)
                            .overlay(Rectangle()
                                .stroke(.white, lineWidth: 0.20))
                            .offset(x: 111.50, y: 202)

                        // Social login buttons
                        HStack(spacing: 54) {
                            // Phone button
                            Button(action: {
                                // TODO: Phone login
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "iphone")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 46, height: 46)
                                .cornerRadius(23)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 23)
                                        .inset(by: 0.20)
                                        .stroke(.white, lineWidth: 0.20)
                                )
                            }

                            // Apple button
                            Button(action: {
                                // TODO: Apple login
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 46, height: 46)
                                .cornerRadius(23)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 23)
                                        .inset(by: 0.20)
                                        .stroke(.white, lineWidth: 0.20)
                                )
                            }

                            // Google button
                            Button(action: {
                                // TODO: Google login
                            }) {
                                HStack(spacing: 8) {
                                    Text("G")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 46, height: 46)
                                .cornerRadius(23)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 23)
                                        .inset(by: 0.20)
                                        .stroke(.white, lineWidth: 0.20)
                                )
                            }
                        }
                        .offset(x: 0.50, y: 263)

                        // Already have an account
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .font(.system(size: 16, weight: .light))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))

                            Button(action: {
                                currentPage = .login
                            }) {
                                Text(LocalizedStringKey("Sign_in"))
                                    .font(.system(size: 16, weight: .bold))
                                    .lineSpacing(20)
                                    .underline()
                                    .foregroundColor(.white)
                            }
                        }
                        .offset(x: 0, y: 326)

                        // Error Message
                        if let errorMessage = errorMessage {
                            Text(LocalizedStringKey(errorMessage))
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                .offset(x: 0, y: 100)
                        }
                    }
                }
                .frame(width: 375, height: 812)

                // 使用固定高度替代Spacer，防止键盘推动布局
                Color.clear
                    .frame(height: max(0, (UIScreen.main.bounds.height - 812) / 2))
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        // 移除 .ignoresSafeArea(.keyboard) 防止页面随键盘浮动
        .scrollDismissesKeyboard(.interactively)
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
                    print("[CreateAccountView] 头像已选择并保存")
                    #endif
                }
            }
        }
    }

    // MARK: - Actions

    private func handleRegister() async {
        guard validateRegister() else { return }

        isLoading = true
        errorMessage = nil

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalInviteCode = inviteCode.isEmpty ? "NOVATEST" : inviteCode

        #if DEBUG
        print("[CreateAccountView] Starting registration")
        print("[CreateAccountView] Username: \(trimmedUsername)")
        print("[CreateAccountView] Email: \(trimmedEmail)")
        print("[CreateAccountView] Invite Code: \(finalInviteCode)")
        #endif

        do {
            _ = try await authManager.register(
                username: trimmedUsername,
                email: trimmedEmail,
                password: password,
                displayName: displayName.isEmpty ? username : displayName,
                inviteCode: finalInviteCode
            )
            #if DEBUG
            print("[CreateAccountView] Registration successful!")
            #endif
            // Success - Navigate to home page
            await MainActor.run {
                currentPage = .home
            }
        } catch {
            #if DEBUG
            print("[CreateAccountView] Registration error: \(error)")
            print("[CreateAccountView] Error type: \(type(of: error))")
            print("[CreateAccountView] Error description: \(error.localizedDescription)")
            #endif

            // Provide user-friendly error messages
            if error.localizedDescription.contains("409") || error.localizedDescription.contains("already exists") {
                errorMessage = "Username_or_email_exists"
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                errorMessage = "Network_error"
            } else if error.localizedDescription.contains("invite") || error.localizedDescription.contains("code") {
                errorMessage = "Invalid_invite_code"
            } else {
                errorMessage = String(format: NSLocalizedString("Registration_failed", comment: ""), error.localizedDescription)
            }
        }

        isLoading = false
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
}

// MARK: - Preview

#Preview {
    CreateAccountView(currentPage: .constant(.createAccount))
        .environmentObject(AuthenticationManager.shared)
}
