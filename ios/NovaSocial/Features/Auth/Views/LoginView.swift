import SwiftUI

// MARK: - Login View

struct LoginView: View {
    // MARK: - Design Constants
    private enum Layout {
        static let contentOffset: CGFloat = 200
        static let inputFieldHeight: CGFloat = 49
        static let buttonHeight: CGFloat = 46
        static let buttonCornerRadius: CGFloat = 31.5
        static let fieldCornerRadius: CGFloat = 6
        static let fieldSpacing: CGFloat = 28
        static let errorOffset: CGFloat = 32
    }

    private enum Colors {
        static let placeholder = Color(white: 0.77)
        static let secondaryText = Color(white: 0.53)
        static let disabledText = Color(white: 0.40)
        static let errorText = Color(red: 1, green: 0.4, blue: 0.4)
        static let fieldBorder = Color.white.opacity(0.3)
    }

    // MARK: - Binding
    @Binding var currentPage: AppPage

    // MARK: - State
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var isGoogleLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false

    // MARK: - Validation State
    @State private var emailError: String?
    @State private var passwordError: String?

    // MARK: - Focus State
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    // MARK: - Environment
    @EnvironmentObject private var authManager: AuthenticationManager

    // MARK: - Computed Properties
    /// Forgot Password 按钮启用条件：email 格式正确且无错误
    private var isForgotPasswordEnabled: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedEmail.isEmpty && isValidEmail(trimmedEmail) && emailError == nil
    }

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
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Logo Section
                    logoSection

                    Spacer()
                        .frame(height: 40.h)

                    // Welcome Text
                    Text("Welcome to Icered")
                        .font(.system(size: 30.f, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()
                        .frame(height: 36.h)

                    // Input Fields
                    VStack(spacing: 28.h) {
                        // Email Field
                        emailTextField

                        // Password Field
                        passwordTextField
                    }
                    .padding(.horizontal, 16.w)

                    // Forgot Password
                    HStack {
                        Spacer()
                        Button(action: {
                            currentPage = .forgotPassword
                        }) {
                            Text(LocalizedStringKey("Forgot_Password"))
                                .font(.system(size: 12.f, weight: .light))
                                .foregroundColor(isForgotPasswordEnabled ? Colors.placeholder : Colors.disabledText)
                        }
                        .disabled(!isForgotPasswordEnabled)
                    }
                    .padding(.horizontal, 20.w)
                    .padding(.top, 12.h)

                    // Error Message - 使用固定高度容器，避免影响按钮位置
                    Text(errorMessage != nil ? LocalizedStringKey(errorMessage!) : " ")
                        .font(.system(size: 12.f))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20.w)
                        .frame(minHeight: 20.h)
                        .opacity(errorMessage != nil ? 1 : 0)

                    Spacer()
                        .frame(height: 12.h)

                    // Buttons
                    VStack(spacing: 12.h) {
                        // Log In Button
                        logInButton

                        // Google & Apple Buttons (side by side)
                        HStack(spacing: 11.w) {
                            googleButton
                            appleButton
                        }

                        // Create Account Button
                        createAccountButton
                    }
                    .padding(.horizontal, 16.w)
                }
                .offset(y: Layout.contentOffset.h)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = nil
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Logo Section
    private var logoSection: some View {
        VStack(spacing: 4.s) {
            Image("Logo-R")
                .resizable()
                .scaledToFit()
                .frame(height: 50.s)
                .colorInvert()
                .brightness(1)
        }
    }

    // MARK: - Email TextField
    private var emailTextField: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Layout.fieldCornerRadius.s)
                .fill(Color.clear)
                .frame(height: Layout.inputFieldHeight.h)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.fieldCornerRadius.s)
                        .stroke(emailError != nil ? Color.red : Colors.fieldBorder, lineWidth: emailError != nil ? 1 : 0.5)
                )

            TextField("", text: $email, prompt: Text(LocalizedStringKey("email or phone number")).foregroundColor(Colors.placeholder))
                .foregroundColor(.white)
                .font(.system(size: 14.f, weight: .light))
                .padding(.horizontal, 16.w)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .accessibilityIdentifier("loginEmailTextField")
                .focused($focusedField, equals: .email)
                .onChange(of: email) { _, newValue in
                    validateEmailRealtime(newValue)
                }

            if let error = emailError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11.f))
                    .foregroundColor(Colors.errorText)
                    .padding(.leading, 4.w)
                    .offset(y: Layout.errorOffset.h)
            }
        }
    }

    // MARK: - Password TextField
    private var passwordTextField: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Layout.fieldCornerRadius.s)
                .fill(Color.clear)
                .frame(height: Layout.inputFieldHeight.h)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.fieldCornerRadius.s)
                        .stroke(passwordError != nil ? Color.red : Colors.fieldBorder, lineWidth: passwordError != nil ? 1 : 0.5)
                )

            HStack {
                if showPassword {
                    TextField("", text: $password, prompt: Text(LocalizedStringKey("password")).foregroundColor(Colors.placeholder))
                        .foregroundColor(.white)
                        .font(.system(size: 14.f, weight: .light))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("loginPasswordTextField")
                        .focused($focusedField, equals: .password)
                } else {
                    SecureField("", text: $password, prompt: Text(LocalizedStringKey("password")).foregroundColor(Colors.placeholder))
                        .foregroundColor(.white)
                        .font(.system(size: 14.f, weight: .light))
                        .accessibilityIdentifier("loginPasswordTextField")
                        .focused($focusedField, equals: .password)
                }

                Text(showPassword ? "HIDE" : "SHOW")
                    .font(.system(size: 12.f, weight: .light))
                    .foregroundColor(Colors.secondaryText)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showPassword.toggle()
                    }
            }
            .padding(.horizontal, 16.w)

            if let error = passwordError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11.f))
                    .foregroundColor(Colors.errorText)
                    .padding(.leading, 4.w)
                    .offset(y: Layout.errorOffset.h)
            }
        }
    }

    // MARK: - Log In Button
    private var logInButton: some View {
        Button(action: {
            Task {
                await handleLogin()
            }
        }) {
            HStack(spacing: 8.w) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                }
                Text("Log in")
                    .font(Font.custom("Helvetica Neue", size: 17.f).weight(.bold))
                    .lineSpacing(20)
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.buttonHeight.h)
            .background(Color.white)
            .cornerRadius(Layout.buttonCornerRadius.s)
        }
        .disabled(isLoading || isGoogleLoading)
        .accessibilityIdentifier("logInButton")
    }

    // MARK: - Google Button (Icon Only)
    private var googleButton: some View {
        Button(action: {
            Task {
                await handleGoogleSignIn()
            }
        }) {
            ZStack {
                if isGoogleLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else {
                    Text("G")
                        .font(.system(size: 20.f, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Layout.buttonHeight.h)
            .background(Color.clear)
            .cornerRadius(65.s)
            .overlay(
                RoundedRectangle(cornerRadius: 65.s)
                    .stroke(Color.white, lineWidth: 0.5)
            )
        }
        .disabled(isLoading || isGoogleLoading)
        .accessibilityIdentifier("googleButton")
    }

    // MARK: - Apple Button (Icon Only)
    private var appleButton: some View {
        Button(action: {
            Task {
                await handleAppleSignIn()
            }
        }) {
            Image(systemName: "apple.logo")
                .font(.system(size: 20.f, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.buttonHeight.h)
                .background(Color.clear)
                .cornerRadius(65.s)
                .overlay(
                    RoundedRectangle(cornerRadius: 65.s)
                        .stroke(Color.white, lineWidth: 0.5)
                )
        }
        .disabled(isLoading || isGoogleLoading)
        .accessibilityIdentifier("appleButton")
    }

    // MARK: - Create Account Button
    private var createAccountButton: some View {
        Button(action: {
            currentPage = .welcome
        }) {
            Text("Create account")
                .font(Font.custom("Helvetica Neue", size: 17.f).weight(.bold))
                .lineSpacing(20)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.buttonHeight.h)
                .background(Color.clear)
                .cornerRadius(40.s)
                .overlay(
                    RoundedRectangle(cornerRadius: 40.s)
                        .stroke(Color.white, lineWidth: 0.5)
                )
        }
        .accessibilityIdentifier("createAccountButton")
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
        isLoading = true
        errorMessage = nil

        do {
            let _ = try await authManager.loginWithApple()
            // Success - AuthenticationManager will update isAuthenticated
        } catch {
            let errorDesc = error.localizedDescription.lowercased()
            if errorDesc.contains("cancel") {
                // User cancelled, no error message needed
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    // MARK: - Validation

    private func validateLogin() -> Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedEmail.isEmpty {
                errorMessage = "Please_enter_your_email"
            return false
        }

            if !isValidEmail(trimmedEmail) {
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
        } else if !isValidEmail(trimmed) {
            emailError = "Invalid_email_format"
        } else {
            emailError = nil
        }
    }

    // MARK: - Validation Helpers

    private func isValidEmail(_ email: String) -> Bool {
        // Basic email format validation using regex
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }
}

// MARK: - Previews

#Preview("Login - Default") {
    LoginView(currentPage: .constant(.login))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("Login - Dark Mode") {
    LoginView(currentPage: .constant(.login))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
