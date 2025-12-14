import SwiftUI
import AuthenticationServices

// MARK: - Login View

struct LoginView: View {
    // MARK: - Binding
    @Binding var currentPage: AppPage

    // MARK: - State
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var isGoogleLoading = false
    @State private var isAppleLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var showForgotPassword = false

    // MARK: - Validation State
    @State private var emailError: String?
    @State private var passwordError: String?

    // MARK: - Focus State
    @FocusState private var focusedField: Field?

    enum Field {
        case email
        case password
    }

    // Access global AuthenticationManager
    @EnvironmentObject private var authManager: AuthenticationManager

    var body: some View {
        ZStack {
            // Background Image - Fixed size to prevent scaling when keyboard appears
            Image("Registration-background")
                .resizable()
                .scaledToFill()
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .clipped()
                .ignoresSafeArea(.all)

            // Dark overlay
            Color.black
                .opacity(0.4)
                .ignoresSafeArea()

            // Main Content
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // ============================================
                        // 📐 整体内容垂直位置调整
                        // 修改下面的 offset 值来调整整体位置
                        // 正值 = 向下移动，负值 = 向上移动
                        // ============================================
                        let contentVerticalOffset: CGFloat = 140

                        // 内容容器
                        VStack(spacing: 0) {
                            // Logo Section
                            logoSection

                            Spacer()
                                .frame(height: 40)

                            // Welcome Text
                            Text("Welcome to Icered")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundColor(.white)

                            Spacer()
                                .frame(height: 36)

                            // Input Fields
                            VStack(spacing: 16) {
                                // Email Field
                                emailTextField

                                // Password Field
                                passwordTextField
                            }
                            .padding(.horizontal, 16)

                            // Forgot Password
                            HStack {
                                Spacer()
                                Button(action: {
                                    showForgotPassword = true
                                }) {
                                    Text(LocalizedStringKey("Forgot_Password"))
                                        .font(.system(size: 12, weight: .light))
                                        .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                            // Error Message
                            if let errorMessage = errorMessage {
                                Text(LocalizedStringKey(errorMessage))
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 40)
                                    .padding(.top, 12)
                            }

                            Spacer()
                                .frame(height: 32)

                            // Buttons
                            VStack(spacing: 16) {
                                // Sign In Button
                                signInButton

                                // Create Account Button
                                createAccountButton

                                // Divider
                                orDivider

                                // Social Sign-In Buttons
                                socialSignInButtons
                            }
                            .padding(.horizontal, 16)
                        }
                        .offset(y: contentVerticalOffset)

                        Spacer()
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $showForgotPassword) {
            ForgotPasswordView()
                .environmentObject(authManager)
        }
    }

    // MARK: - Logo Section
    private var logoSection: some View {
        VStack(spacing: 4) {
            Image("Logo-R")
                .resizable()
                .scaledToFit()
                .frame(height: 90)
                .colorInvert()
                .brightness(1)
        }
    }

    // MARK: - Email TextField
    private var emailTextField: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
                    .frame(height: 49)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(emailError != nil ? Color.red : Color.white.opacity(0.3), lineWidth: emailError != nil ? 1 : 0.5)
                    )

                TextField("", text: $email, prompt: Text(LocalizedStringKey("email_or_phone_number")).foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77)))
                    .foregroundColor(.white)
                    .font(.system(size: 14, weight: .light))
                    .padding(.horizontal, 16)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .accessibilityIdentifier("loginEmailTextField")
                    .focused($focusedField, equals: .email)
                    .onChange(of: email) { _, newValue in
                        validateEmailRealtime(newValue)
                    }
            }

            if let error = emailError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Password TextField
    private var passwordTextField: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
                    .frame(height: 49)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(passwordError != nil ? Color.red : Color.white.opacity(0.3), lineWidth: passwordError != nil ? 1 : 0.5)
                    )

                HStack {
                    if showPassword {
                        TextField("", text: $password, prompt: Text(LocalizedStringKey("password")).foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77)))
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .light))
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .textContentType(.password)
                            .accessibilityIdentifier("loginPasswordTextField")
                            .focused($focusedField, equals: .password)
                    } else {
                        SecureField("", text: $password, prompt: Text(LocalizedStringKey("password")).foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77)))
                            .foregroundColor(.white)
                            .font(.system(size: 14, weight: .light))
                            .textContentType(.password)
                            .accessibilityIdentifier("loginPasswordTextField")
                            .focused($focusedField, equals: .password)
                    }

                    Button(action: {
                        showPassword.toggle()
                    }) {
                        Text(showPassword ? "HIDE" : "SHOW")
                            .font(.system(size: 12, weight: .light))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                    }
                }
                .padding(.horizontal, 16)
            }

            if let error = passwordError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Sign In Button
    private var signInButton: some View {
        Button(action: {
            Task {
                await handleLogin()
            }
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                }
                Text(LocalizedStringKey("Sign_In"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Color.white)
            .cornerRadius(31.50)
        }
        .disabled(isLoading || isGoogleLoading)
        .accessibilityIdentifier("signInButton")
    }

    // MARK: - Create Account Button
    private var createAccountButton: some View {
        Button(action: {
            currentPage = .welcome
        }) {
            Text(LocalizedStringKey("Create_An_Account"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 31.50)
                        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
                )
        }
        .accessibilityIdentifier("createAccountButton")
    }

    // MARK: - Or Divider
    private var orDivider: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(height: 0.5)

            Text("OR")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.6))

            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(height: 0.5)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Social Sign-In Buttons
    private var socialSignInButtons: some View {
        VStack(spacing: 12) {
            // Apple Sign-In Button
            Button(action: {
                Task {
                    await handleAppleSignIn()
                }
            }) {
                HStack(spacing: 12) {
                    if isAppleLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 18, weight: .medium))
                    }
                    Text("Sign in with Apple")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.black)
                .cornerRadius(31.50)
                .overlay(
                    RoundedRectangle(cornerRadius: 31.50)
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                )
            }
            .disabled(isLoading || isGoogleLoading || isAppleLoading)
            .accessibilityIdentifier("appleSignInButton")

            // Google Sign-In Button
            Button(action: {
                Task {
                    await handleGoogleSignIn()
                }
            }) {
                HStack(spacing: 12) {
                    if isGoogleLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.8)
                    } else {
                        Image("google-logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    Text("Sign in with Google")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.white)
                .cornerRadius(31.50)
            }
            .disabled(isLoading || isGoogleLoading || isAppleLoading)
            .accessibilityIdentifier("googleSignInButton")
        }
    }

    // MARK: - Actions

    private func handleLogin() async {
        guard validateLogin() else { return }

        isLoading = true
        errorMessage = nil

        do {
            _ = try await authManager.login(
                username: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            // Success - AuthenticationManager will update isAuthenticated
        } catch {
            // Provide user-friendly error messages
            if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                errorMessage = "Invalid_email_or_password"
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                errorMessage = "Network_error"
            } else {
                errorMessage = "Login_failed"
            }
            #if DEBUG
            print("[LoginView] Login error: \(error)")
            #endif
        }

        isLoading = false
    }

    private func handleGoogleSignIn() async {
        isGoogleLoading = true
        errorMessage = nil

        do {
            let _ = try await authManager.loginWithGoogle()
            // Success - AuthenticationManager will update isAuthenticated
        } catch {
            // Check if user cancelled (error description contains "cancelled")
            let errorDesc = error.localizedDescription.lowercased()
            if errorDesc.contains("cancel") {
                // User cancelled, no error message needed
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isGoogleLoading = false
    }

    private func handleAppleSignIn() async {
        isAppleLoading = true
        errorMessage = nil

        do {
            let _ = try await authManager.loginWithApple()
            // Success - AuthenticationManager will update isAuthenticated
        } catch {
            // Check if user cancelled
            let errorDesc = error.localizedDescription.lowercased()
            if errorDesc.contains("cancel") {
                // User cancelled, no error message needed
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isAppleLoading = false
    }

    // MARK: - Validation

    private func validateLogin() -> Bool {
        let trimmedIdentifier = email.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedIdentifier.isEmpty {
            errorMessage = "Please_enter_your_email"
            return false
        }

        // Allow both username and email formats
        // Username: alphanumeric with optional underscores/dots, 3+ chars
        // Email: standard email format
        if !isValidIdentifier(trimmedIdentifier) {
            errorMessage = "Please_enter_a_valid_email"
            return false
        }

        if password.isEmpty {
            errorMessage = "Please_enter_your_password"
            return false
        }

        return true
    }

    // MARK: - Realtime Validation

    private func validateEmailRealtime(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            emailError = nil  // Don't show error for empty field until submit
        } else if !isValidIdentifier(trimmed) {
            emailError = "Invalid_email_format"
        } else {
            emailError = nil
        }
    }

    // MARK: - Validation Helpers

    /// Validates if input is a valid email OR username
    /// Backend accepts both formats for login
    private func isValidIdentifier(_ identifier: String) -> Bool {
        // Check if it's a valid email
        if isValidEmail(identifier) {
            return true
        }
        // Check if it's a valid username (alphanumeric, underscores, dots, 3-30 chars)
        let usernameRegex = #"^[A-Za-z0-9._]{3,30}$"#
        return identifier.range(of: usernameRegex, options: .regularExpression) != nil
    }

    private func isValidEmail(_ email: String) -> Bool {
        // Basic email format validation using regex
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }
}

// MARK: - Preview

#Preview {
    LoginView(currentPage: .constant(.login))
        .environmentObject(AuthenticationManager.shared)
}
