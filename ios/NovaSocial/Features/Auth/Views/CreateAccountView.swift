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

    var body: some View {
        ZStack {
            // Background Image - Fixed size to prevent scaling when keyboard appears
            Image("Login-Background")
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


                        // SHOW button for PASSWORD
                        Text(showPassword ? "HIDE" : "SHOW")
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            .offset(x: 138.50, y: -20)
                            .onTapGesture {
                                let wasFocused = focusedField == .password
                                showPassword.toggle()
                                if wasFocused {
                                    // Maintain focus after toggle
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        focusedField = .password
                                    }
                                }
                            }

                        // SHOW button for CONFIRM PASSWORD
                        Text(showConfirmPassword ? "HIDE" : "SHOW")
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            .offset(x: 138.50, y: 49)
                            .onTapGesture {
                                let wasFocused = focusedField == .confirmPassword
                                showConfirmPassword.toggle()
                                if wasFocused {
                                    // Maintain focus after toggle
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        focusedField = .confirmPassword
                                    }
                                }
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
                        TextField("", text: $email, prompt: Text("Enter your email").foregroundColor(Color.white.opacity(0.4)))
                            .foregroundColor(.white)
                            .font(Font.custom("Helvetica Neue", size: 14))
                            .padding(.horizontal, 16)
                            .frame(width: 343, height: 49)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .offset(x: 0, y: -157.50)
                            .accessibilityIdentifier("emailTextField")

                        TextField("", text: $username, prompt: Text("Your Username").foregroundColor(Color.white.opacity(0.4)))
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
                                TextField("", text: $password, prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("passwordTextField")
                                    .focused($focusedField, equals: .password)
                                    .id("password_visible")
                            } else {
                                SecureField("", text: $password, prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .accessibilityIdentifier("passwordTextField")
                                    .focused($focusedField, equals: .password)
                                    .id("password_secure")
                            }
                        }
                        .offset(x: 0, y: -19.50)
                        .animation(.none, value: showPassword)

                        // Confirm Password field
                        ZStack {
                            if showConfirmPassword {
                                TextField("", text: $confirmPassword, prompt: Text("Confirm your password").foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                    .accessibilityIdentifier("confirmPasswordTextField")
                                    .focused($focusedField, equals: .confirmPassword)
                                    .id("confirmPassword_visible")
                            } else {
                                SecureField("", text: $confirmPassword, prompt: Text("Confirm your password").foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .frame(width: 343, height: 49)
                                    .accessibilityIdentifier("confirmPasswordTextField")
                                    .focused($focusedField, equals: .confirmPassword)
                                    .id("confirmPassword_secure")
                            }
                        }
                        .offset(x: 0, y: 49.50)
                        .animation(.none, value: showConfirmPassword)

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
                        Text(LocalizedStringKey("Or_you_can"))
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
                                Text(LocalizedStringKey("Sign_in"))
                                    .font(Font.custom("Helvetica Neue", size: 16).weight(.bold))
                                    .lineSpacing(20)
                                    .underline()
                                    .foregroundColor(.white)
                            }
                        }
                        .offset(x: 0, y: 326)

                        // Error Message
                        if let errorMessage = errorMessage {
                            Text(LocalizedStringKey(errorMessage))
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
        .ignoresSafeArea(.keyboard)
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
            errorMessage = "Password must contain uppercase, lowercase, number, and special character (!@#$%)"
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
        // Check for at least one uppercase letter
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil

        // Check for at least one lowercase letter
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil

        // Check for at least one number
        let hasNumber = password.range(of: "[0-9]", options: .regularExpression) != nil

        // Check for at least one special character
        let hasSpecial = password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil

        // Check minimum length (relaxed to 6 for testing)
        let hasMinLength = password.count >= 6

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
        .environmentObject(AuthenticationManager.shared)
}
