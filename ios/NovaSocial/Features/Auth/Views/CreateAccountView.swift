import SwiftUI

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

    // Access global AuthenticationManager
    private let authManager = AuthenticationManager.shared

    var body: some View {
        ZStack {
            // Background Image
            GeometryReader { geometry in
                Image("Login-Background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
            .edgesIgnoringSafeArea(.all)

            // Dark overlay to dim the background
            Color.black
                .opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Main Content
                ZStack {
                    Group {
                        // Profile Picture Circle
                        Circle()
                            .fill(Color(red: 0.77, green: 0.77, blue: 0.77))
                            .frame(width: 136, height: 136)
                            .offset(x: 0.50, y: -290)

                        // Add Photo Button
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.87, green: 0.11, blue: 0.26))
                                .frame(width: 35, height: 35)

                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .offset(x: 48, y: -242.50)
                        .onTapGesture {
                            // TODO: Handle photo picker
                        }

                        // EMAIL Label (只在输入框为空时显示)
                        if email.isEmpty {
                            Text("EMAIL")
                                .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                                .lineSpacing(20)
                                .foregroundColor(.white)
                                .offset(x: -139.50, y: -158)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.2), value: email.isEmpty)
                        }

                        // USERNAME Label (只在输入框为空时显示)
                        if username.isEmpty {
                            Text("USERNAME")
                                .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                                .lineSpacing(20)
                                .foregroundColor(.white)
                                .offset(x: -124.50, y: -89)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.2), value: username.isEmpty)
                        }

                        // PASSWORD Label (只在输入框为空时显示)
                        if password.isEmpty {
                            Text("PASSWORD")
                                .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                                .lineSpacing(20)
                                .foregroundColor(.white)
                                .offset(x: -123.50, y: -20)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.2), value: password.isEmpty)
                        }

                        // CONFIRM PASSWORD Label (只在输入框为空时显示)
                        if confirmPassword.isEmpty {
                            Text("CONFIRM PASSWORD")
                                .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                                .lineSpacing(20)
                                .foregroundColor(.white)
                                .offset(x: -95.50, y: 49)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.2), value: confirmPassword.isEmpty)
                        }

                        // SHOW button for PASSWORD
                        Text(showPassword ? "HIDE" : "SHOW")
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            .offset(x: 138.50, y: -20)
                            .onTapGesture {
                                showPassword.toggle()
                            }

                        // SHOW button for CONFIRM PASSWORD
                        Text(showConfirmPassword ? "HIDE" : "SHOW")
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            .offset(x: 138.50, y: 49)
                            .onTapGesture {
                                showConfirmPassword.toggle()
                            }

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
                        TextField("", text: $email)
                            .foregroundColor(.white)
                            .font(Font.custom("Helvetica Neue", size: 14))
                            .padding(.horizontal, 16)
                            .frame(width: 343, height: 49)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .offset(x: 0, y: -157.50)
                            .accessibilityIdentifier("emailTextField")

                        TextField("", text: $username)
                            .foregroundColor(.white)
                            .font(Font.custom("Helvetica Neue", size: 14))
                            .padding(.horizontal, 16)
                            .frame(width: 343, height: 49)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .offset(x: 0, y: -88.50)
                            .accessibilityIdentifier("usernameTextField")

                        // Password field
                        ZStack {
                            if showPassword {
                                TextField("", text: $password)
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("passwordTextField")
                            } else {
                                SecureField("", text: $password)
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .accessibilityIdentifier("passwordTextField")
                            }
                        }
                        .offset(x: 0, y: -19.50)

                        // Confirm Password field
                        ZStack {
                            if showConfirmPassword {
                                TextField("", text: $confirmPassword)
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("confirmPasswordTextField")
                            } else {
                                SecureField("", text: $confirmPassword)
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .accessibilityIdentifier("confirmPasswordTextField")
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
                                Text("Sign up")
                                    .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
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
                        Text("or you can")
                            .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
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
                                .font(Font.custom("Helvetica Neue", size: 16).weight(.light))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))

                            Button(action: {
                                currentPage = .login
                            }) {
                                Text("Sign in")
                                    .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                                    .lineSpacing(20)
                                    .underline()
                                    .foregroundColor(.white)
                            }
                        }
                        .offset(x: 0, y: 326)

                        // Error Message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(Font.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                .offset(x: 0, y: 100)
                        }
                    }
                }
                .frame(width: 375, height: 812)

                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                errorMessage = "Username or email already exists. Please try another."
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                errorMessage = "Network error. Please check your connection."
            } else if error.localizedDescription.contains("invite") || error.localizedDescription.contains("code") {
                errorMessage = "Invalid invite code. Please contact support."
            } else {
                errorMessage = "Registration failed: \(error.localizedDescription)"
            }
        }

        isLoading = false
    }

    // MARK: - Validation

    private func validateRegister() -> Bool {
        if email.isEmpty {
            errorMessage = "Please enter an email"
            return false
        }

        if !isValidEmail(email) {
            errorMessage = "Please enter a valid email address"
            return false
        }

        if username.isEmpty {
            errorMessage = "Please enter a username"
            return false
        }

        if password.isEmpty {
            errorMessage = "Please enter a password"
            return false
        }

        if password.count < 12 {
            errorMessage = "Password must be at least 12 characters"
            return false
        }

        if !isStrongPassword(password) {
            errorMessage = "Password must contain uppercase, lowercase, number, and special character (!@#$%)"
            return false
        }

        if confirmPassword.isEmpty {
            errorMessage = "Please confirm your password"
            return false
        }

        if password != confirmPassword {
            errorMessage = "Passwords do not match"
            return false
        }

        return true
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    private func isStrongPassword(_ password: String) -> Bool {
        // Check for at least one uppercase letter
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil

        // Check for at least one lowercase letter
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil

        // Check for at least one number
        let hasNumber = password.range(of: "[0-9]", options: .regularExpression) != nil

        // Check for at least one special character
        let hasSpecial = password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil

        // Check minimum length (backend requires 8+)
        let hasMinLength = password.count >= 12

        // Avoid common patterns that zxcvbn scores poorly
        let hasCommonPattern = password.lowercased().contains("password") ||
                               password.lowercased().contains("123456") ||
                               password.lowercased().contains("qwerty")

        return hasUppercase && hasLowercase && hasNumber && hasSpecial && hasMinLength && !hasCommonPattern
    }
}

// MARK: - Preview

#Preview {
    CreateAccountView(currentPage: .constant(.createAccount))
}
