import SwiftUI

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
        GeometryReader { geometry in
            ZStack {
                // Background Image
                Image("Login-BG")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea(.all)

                // Main Content
                VStack(spacing: 0) {
                    Spacer()

                    // Logo Section
                    logoSection

                    Spacer()
                        .frame(height: 50)

                    // Input Fields Section
                    inputFieldsSection

                    Spacer()
                        .frame(height: 32)

                    // Login Button
                    loginButton

                    Spacer()
                        .frame(height: 24)

                    // "or" separator
                    Text("or")
                        .font(Typography.regular14)
                        .tracking(LetterSpacing.regular14)
                        .foregroundColor(.white)

                    Spacer()
                        .frame(height: 24)

                    // Social Login Buttons
                    socialLoginButtons

                    Spacer()
                        .frame(height: 40)

                    // Create Account Link
                    createAccountLink

                    Spacer()

                    // Terms and Privacy Links
                    termsAndPrivacyLinks

                    Spacer()
                        .frame(height: 20)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Logo Section
    private var logoSection: some View {
        VStack(spacing: 8) {
            Image("Logo-R")
                .resizable()
                .scaledToFit()
                .frame(height: 60)
                .colorInvert()
                .brightness(1)

            Text("For the masters of the universe")
                .font(Typography.bold12)
                .tracking(LetterSpacing.bold12)
                .foregroundColor(Color(red: 0.90, green: 0.90, blue: 0.90))
        }
    }

    // MARK: - Input Fields Section
    private var inputFieldsSection: some View {
        VStack(spacing: 16) {
            // Email Field
            emailTextField

            // Password Field
            passwordTextField

            // Forgot Password + Error Message (fixed height container)
            ZStack {
                // Forgot Password (always visible)
                HStack {
                    Spacer()
                    Button(action: {
                        // TODO: Handle forgot password
                    }) {
                        Text("Forgot password?")
                            .font(Typography.regular12)
                            .tracking(LetterSpacing.regular12)
                            .foregroundColor(Color(red: 0.64, green: 0.64, blue: 0.64))
                    }
                }

                // Error Message (overlay, doesn't affect layout)
                if let errorMessage = errorMessage {
                    Text(LocalizedStringKey(errorMessage))
                        .font(Typography.regular12)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .offset(y: 28)
                }
            }
            .frame(height: 20)
        }
        .padding(.horizontal, 38)
    }

    // MARK: - Email TextField
    private var emailTextField: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25))
                    .frame(height: 49)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(emailError != nil ? Color.red : Color.white, lineWidth: 0.5)
                    )

                TextField("", text: $email, prompt: Text("Email or phone number").foregroundColor(.white.opacity(0.7)))
                    .foregroundColor(.white)
                    .font(Typography.regular14)
                    .tracking(LetterSpacing.regular14)
                    .padding(.horizontal, 16)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("loginEmailTextField")
                    .focused($focusedField, equals: .email)
                    .onChange(of: email) { _, newValue in
                        validateEmailRealtime(newValue)
                    }
            }

            if let error = emailError {
                Text(LocalizedStringKey(error))
                    .font(Typography.thin11)
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
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25))
                    .frame(height: 49)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(passwordError != nil ? Color.red : Color.white, lineWidth: 0.5)
                    )

                HStack {
                    if showPassword {
                        TextField("", text: $password, prompt: Text("Password").foregroundColor(.white.opacity(0.7)))
                            .foregroundColor(.white)
                            .font(Typography.regular14)
                            .tracking(LetterSpacing.regular14)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("loginPasswordTextField")
                            .focused($focusedField, equals: .password)
                    } else {
                        SecureField("", text: $password, prompt: Text("Password").foregroundColor(.white.opacity(0.7)))
                            .foregroundColor(.white)
                            .font(Typography.regular14)
                            .tracking(LetterSpacing.regular14)
                            .accessibilityIdentifier("loginPasswordTextField")
                            .focused($focusedField, equals: .password)
                    }

                    Button(action: {
                        showPassword.toggle()
                    }) {
                        Image(systemName: showPassword ? "eye" : "eye.slash")
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 24, height: 24)
                    }
                }
                .padding(.horizontal, 16)
            }

            if let error = passwordError {
                Text(LocalizedStringKey(error))
                    .font(Typography.thin11)
                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Login Button
    private var loginButton: some View {
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
                Text("Log in")
                    .font(Typography.heavy16)
                    .tracking(LetterSpacing.heavy16)
                    .foregroundColor(.black)
            }
            .frame(width: 300, height: 49)
            .background(.white)
            .cornerRadius(31.50)
        }
        .disabled(isLoading || isGoogleLoading || isAppleLoading)
        .accessibilityIdentifier("signInButton")
    }

    // MARK: - Social Login Buttons
    private var socialLoginButtons: some View {
        VStack(spacing: 16) {
            // Continue with Google
            Button(action: {
                Task {
                    await handleGoogleSignIn()
                }
            }) {
                HStack(spacing: 12) {
                    // Google "G" logo
                    Text("G")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)

                    if isGoogleLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }

                    Text("Continue with Google")
                        .font(Typography.heavy16)
                        .tracking(LetterSpacing.heavy16)
                        .foregroundColor(.white)
                }
                .frame(width: 300, height: 49)
                .background(Color.clear)
                .cornerRadius(65)
                .overlay(
                    RoundedRectangle(cornerRadius: 65)
                        .stroke(.white, lineWidth: 0.5)
                )
            }
            .disabled(isLoading || isGoogleLoading || isAppleLoading)
            .accessibilityIdentifier("googleSignInButton")

            // Continue with Apple
            Button(action: {
                Task {
                    await handleAppleSignIn()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "apple.logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundColor(.white)

                    if isAppleLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }

                    Text("Continue with Apple")
                        .font(Typography.heavy16)
                        .tracking(LetterSpacing.heavy16)
                        .foregroundColor(.white)
                }
                .frame(width: 300, height: 49)
                .background(Color.clear)
                .cornerRadius(65)
                .overlay(
                    RoundedRectangle(cornerRadius: 65)
                        .stroke(.white, lineWidth: 0.5)
                )
            }
            .disabled(isLoading || isGoogleLoading || isAppleLoading)
            .accessibilityIdentifier("appleSignInButton")
        }
    }

    // MARK: - Create Account Link
    private var createAccountLink: some View {
        HStack(spacing: 4) {
            Text("New to Icered?")
                .font(Typography.regular14)
                .tracking(LetterSpacing.regular14)
                .foregroundColor(.white)

            Button(action: {
                currentPage = .createAccount
            }) {
                Text("Create an Account")
                    .font(Typography.semibold14)
                    .tracking(LetterSpacing.semibold14)
                    .foregroundColor(.white)
                    .underline()
            }
            .accessibilityIdentifier("createAccountButton")
        }
    }

    // MARK: - Terms and Privacy Links
    private var termsAndPrivacyLinks: some View {
        HStack(spacing: 16) {
            Button(action: {
                // TODO: Show Terms and Conditions
            }) {
                Text("Terms and Conditions")
                    .font(Typography.thin11)
                    .tracking(LetterSpacing.thin11)
                    .underline()
                    .foregroundColor(.white)
            }

            Button(action: {
                // TODO: Show Privacy Statement
            }) {
                Text("Privacy Statement")
                    .font(Typography.thin11)
                    .tracking(LetterSpacing.thin11)
                    .underline()
                    .foregroundColor(.white)
            }
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

// MARK: - Preview

#Preview {
    LoginView(currentPage: .constant(.login))
        .environmentObject(AuthenticationManager.shared)
}
