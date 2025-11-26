import SwiftUI

// MARK: - Login View

struct LoginView: View {
    // MARK: - State
    @State private var isLoginMode = true
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false

    // MARK: - Validation State
    @State private var emailError: String?
    @State private var passwordError: String?
    @State private var usernameError: String?

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
                        // ICERED Logo Icon at top
                        Image("Login-Icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 90)
                            .offset(x: 0, y: -290)

                        // Welcome Text
                        Text("Welcome to Icered—for the masters of the universe.")
                            .font(Font.custom("Helvetica Neue", size: 16).weight(.thin))
                            .lineSpacing(20)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .offset(x: 0.50, y: -180)

                        // Labels removed - placeholder text provides field hints

                        // Forgot password
                        Text("Forgot password?")
                            .font(Font.custom("Helvetica Neue", size: 10).weight(.light))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                            .offset(x: 132, y: 44)
                            .onTapGesture {
                                // TODO: Handle forgot password
                            }

                        // SHOW/HIDE password toggle
                        Text(showPassword ? "HIDE" : "SHOW")
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            .offset(x: 138.50, y: -1)
                            .onTapGesture {
                                showPassword.toggle()
                            }

                        // Sign In Button
                        Button(action: {
                            Task {
                                if isLoginMode {
                                    await handleLogin()
                                } else {
                                    await handleRegister()
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                                Text(isLoginMode ? "Sign In" : "Sign Up")
                                    .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                                    .lineSpacing(20)
                                    .foregroundColor(.white)
                            }
                            .frame(width: 343, height: 46)
                            .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .cornerRadius(31.50)
                        }
                        .disabled(isLoading)
                        .offset(x: 0, y: 87)

                        // "or you can" text
                        Text("or you can")
                            .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                            .lineSpacing(20)
                            .foregroundColor(.white)
                            .offset(x: 0.50, y: 150)

                        // Create Account / Back to Sign In Button
                        Button(action: {
                            toggleMode()
                        }) {
                            HStack(spacing: 8) {
                                Text(isLoginMode ? "Create An Account" : "Back to Sign In")
                                    .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                                    .lineSpacing(20)
                                    .foregroundColor(.white)
                            }
                            .frame(width: 343, height: 46)
                            .cornerRadius(31.50)
                            .overlay(
                                RoundedRectangle(cornerRadius: 31.50)
                                    .inset(by: 0.20)
                                    .stroke(.white, lineWidth: 0.20)
                            )
                        }
                        .offset(x: 0, y: 213)

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

                    Group {
                        // Email/Username Input Field
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(width: 343, height: 49)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .inset(by: 0.20)
                                            .stroke(emailError != nil ? Color.red : .white, lineWidth: emailError != nil ? 1 : 0.20)
                                    )

                                if isLoginMode {
                                    TextField("", text: $email, prompt: Text("Enter your email").foregroundColor(Color.white.opacity(0.4)))
                                        .foregroundColor(.white)
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .padding(.horizontal, 16)
                                        .autocapitalization(.none)
                                        .keyboardType(.emailAddress)
                                        .autocorrectionDisabled()
                                        .onChange(of: email) { _, newValue in
                                            validateEmailRealtime(newValue)
                                        }
                                } else {
                                    TextField("", text: $username, prompt: Text("Choose a username").foregroundColor(Color.white.opacity(0.4)))
                                        .foregroundColor(.white)
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .padding(.horizontal, 16)
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .onChange(of: username) { _, newValue in
                                            validateUsernameRealtime(newValue)
                                        }
                                }
                            }

                            // Inline error for email/username
                            if let error = isLoginMode ? emailError : usernameError {
                                Text(error)
                                    .font(Font.custom("Helvetica Neue", size: 11))
                                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                                    .padding(.leading, 4)
                            }
                        }
                        .offset(x: 0, y: -69.50)

                        // Password Input Field
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(width: 343, height: 49)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .inset(by: 0.20)
                                            .stroke(passwordError != nil ? Color.red : .white, lineWidth: passwordError != nil ? 1 : 0.20)
                                    )

                                if showPassword {
                                    TextField("", text: $password, prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.4)))
                                        .foregroundColor(.white)
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .padding(.horizontal, 16)
                                        .padding(.trailing, 60)
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .onChange(of: password) { _, newValue in
                                            validatePasswordRealtime(newValue)
                                        }
                                } else {
                                    SecureField("", text: $password, prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.4)))
                                        .foregroundColor(.white)
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .padding(.horizontal, 16)
                                        .padding(.trailing, 60)
                                        .onChange(of: password) { _, newValue in
                                            validatePasswordRealtime(newValue)
                                        }
                                }
                            }

                            // Inline error for password
                            if let error = passwordError {
                                Text(error)
                                    .font(Font.custom("Helvetica Neue", size: 11))
                                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                                    .padding(.leading, 4)
                            }
                        }
                        .offset(x: 0, y: -0.50)

                        // Additional field for registration: Email (when in register mode)
                        if !isLoginMode {
                            VStack(alignment: .leading, spacing: 4) {
                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .foregroundColor(.clear)
                                        .frame(width: 343, height: 49)
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .inset(by: 0.20)
                                                .stroke(emailError != nil ? Color.red : .white, lineWidth: emailError != nil ? 1 : 0.20)
                                        )

                                    TextField("", text: $email, prompt: Text("Enter your email").foregroundColor(Color.white.opacity(0.4)))
                                        .foregroundColor(.white)
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .padding(.horizontal, 16)
                                        .autocapitalization(.none)
                                        .keyboardType(.emailAddress)
                                        .autocorrectionDisabled()
                                        .onChange(of: email) { _, newValue in
                                            validateEmailRealtime(newValue)
                                        }
                                }

                                // Inline error for email in register mode
                                if let error = emailError {
                                    Text(error)
                                        .font(Font.custom("Helvetica Neue", size: 11))
                                        .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                                        .padding(.leading, 4)
                                }
                            }
                            .offset(x: 0, y: -138)

                            Text("EMAIL")
                                .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                                .lineSpacing(20)
                                .foregroundColor(.white)
                                .offset(x: -139.50, y: -155)
                        }

                        // Decorative lines
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 120, height: 0)
                            .overlay(Rectangle()
                                .stroke(.white, lineWidth: 0.20))
                            .offset(x: -111.50, y: 152)

                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 120, height: 0)
                            .overlay(Rectangle()
                                .stroke(.white, lineWidth: 0.20))
                            .offset(x: 111.50, y: 152)
                    }
                }
                .frame(width: 375, height: 812)

                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func handleLogin() async {
        guard validateLogin() else { return }

        isLoading = true
        errorMessage = nil

        do {
            // Use email for login in this new UI
            let _ = try await authManager.login(
                username: email,
                password: password
            )
            // Success - AuthenticationManager will update isAuthenticated
        } catch {
            errorMessage = "Login failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func handleRegister() async {
        guard validateRegister() else { return }

        isLoading = true
        errorMessage = nil

        do {
            let _ = try await authManager.register(
                username: username,
                email: email,
                password: password,
                displayName: displayName.isEmpty ? username : displayName
            )
            // Success - AuthenticationManager will update isAuthenticated
        } catch {
            errorMessage = "Registration failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func toggleMode() {
        isLoginMode.toggle()
        errorMessage = nil
        // Clear fields and validation errors when switching modes
        email = ""
        username = ""
        password = ""
        displayName = ""
        emailError = nil
        passwordError = nil
        usernameError = nil
    }

    // MARK: - Validation

    private func validateLogin() -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedEmail.isEmpty {
            errorMessage = "Please enter your email"
            return false
        }

        if !isValidEmail(trimmedEmail) {
            errorMessage = "Please enter a valid email address"
            return false
        }

        if password.isEmpty {
            errorMessage = "Please enter your password"
            return false
        }

        return true
    }

    private func validateRegister() -> Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        // Username validation
        if trimmedUsername.isEmpty {
            errorMessage = "Please enter a username"
            return false
        }

        if trimmedUsername.count < 3 {
            errorMessage = "Username must be at least 3 characters"
            return false
        }

        if trimmedUsername.count > 30 {
            errorMessage = "Username must be less than 30 characters"
            return false
        }

        if !isValidUsername(trimmedUsername) {
            errorMessage = "Username can only contain letters, numbers, and underscores"
            return false
        }

        // Email validation
        if trimmedEmail.isEmpty {
            errorMessage = "Please enter an email"
            return false
        }

        if !isValidEmail(trimmedEmail) {
            errorMessage = "Please enter a valid email address"
            return false
        }

        // Password validation
        if password.isEmpty {
            errorMessage = "Please enter a password"
            return false
        }

        if password.count < 8 {
            errorMessage = "Password must be at least 8 characters"
            return false
        }

        if !hasPasswordStrength(password) {
            errorMessage = "Password must contain at least one uppercase letter, one lowercase letter, and one number"
            return false
        }

        return true
    }

    // MARK: - Realtime Validation

    private func validateEmailRealtime(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            emailError = nil  // Don't show error for empty field until submit
        } else if !isValidEmail(trimmed) {
            emailError = "Invalid email format"
        } else {
            emailError = nil
        }
    }

    private func validatePasswordRealtime(_ value: String) {
        if value.isEmpty {
            passwordError = nil  // Don't show error for empty field until submit
        } else if !isLoginMode {
            // Only check strength for registration
            if value.count < 8 {
                passwordError = "At least 8 characters required"
            } else if !hasPasswordStrength(value) {
                passwordError = "Need uppercase, lowercase, and number"
            } else {
                passwordError = nil
            }
        } else {
            passwordError = nil
        }
    }

    private func validateUsernameRealtime(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            usernameError = nil  // Don't show error for empty field until submit
        } else if trimmed.count < 3 {
            usernameError = "At least 3 characters required"
        } else if trimmed.count > 30 {
            usernameError = "Maximum 30 characters"
        } else if !isValidUsername(trimmed) {
            usernameError = "Letters, numbers, underscores only"
        } else {
            usernameError = nil
        }
    }

    // MARK: - Validation Helpers

    private func isValidEmail(_ email: String) -> Bool {
        // Basic email format validation using regex
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    private func isValidUsername(_ username: String) -> Bool {
        // Username: alphanumeric and underscores only
        let usernameRegex = #"^[A-Za-z0-9_]+$"#
        return username.range(of: usernameRegex, options: .regularExpression) != nil
    }

    private func hasPasswordStrength(_ password: String) -> Bool {
        // Check for at least one uppercase, one lowercase, and one digit
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        return hasUppercase && hasLowercase && hasDigit
    }
}

// MARK: - Preview

#Preview {
    LoginView()
}
