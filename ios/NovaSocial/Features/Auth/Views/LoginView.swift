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
    @State private var isPasskeyLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var showErrorView = false

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
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                    .clipped()
                    .ignoresSafeArea(.all, edges: .all)

                // Main Content
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
                                    await handleLogin()
                                },
                                onDismiss: {
                                    showErrorView = false
                                    errorMessage = nil
                                }
                            )
                            Spacer()
                        }
                    } else {
                        // Logo Section
                        logoSection

                        Spacer()
                            .frame(height: 77.h)

                        // Input Fields Section
                        inputFieldsSection

                        Spacer()
                            .frame(height: 65.s)

                        // Login Button
                        loginButton
                            .padding(.horizontal, 38.w)

                        Spacer()
                            .frame(height: 28.s)

                        // Or Separator
                        Text("or")
                            .font(.system(size: 16.f))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)

                        Spacer()
                    }
                }

                // Social Login Buttons + Create Account Link (距离底部 98pt)
                VStack(spacing: 0) {
                    Spacer()
                    socialLoginButtons
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 45)
                    createAccountLink
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 79.w)
                        .padding(.bottom, 98)
                }

                // Terms and Privacy Links (固定在底部 28pt)
                VStack {
                    Spacer()
                    termsAndPrivacyLinks
                        .padding(.bottom, 28)
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
        VStack(spacing: 8.s) {
            Image("Logo-R")
                .resizable()
                .scaledToFit()
                .frame(width: 84.s, height: 52.s)
                .colorInvert()
                .brightness(1)

            Text("For the masters of the universe")
                .font(.system(size: 12.f).weight(.medium))
                .tracking(0.24)
                .foregroundColor(Color(red: 0.90, green: 0.90, blue: 0.90))
        }
        .padding(.top, 104.h)
    }

    // MARK: - Input Fields Section
    private var inputFieldsSection: some View {
        VStack(spacing: 0) {
            // Email Field
            emailTextField

            Spacer()
                .frame(height: 16.s)

            // Password Field
            passwordTextField

            Spacer()
                .frame(height: 11.h)

            // Forgot Password + Error Message (fixed height container)
            ZStack {
                // Forgot Password (always visible)
                HStack {
                    Spacer()
                    Button(action: {
                        currentPage = .forgotPassword
                    }) {
                        Text("Forgot password?")
                            .font(.system(size: 14.f))
                            .tracking(0.28)
                            .foregroundColor(Color(red: 0.97, green: 0.97, blue: 0.97))
                    }
                }

                // Error Message (overlay, doesn't affect layout)
                if let errorMessage = errorMessage {
                    Text(LocalizedStringKey(errorMessage))
                        .font(Typography.regular12)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .offset(y: 28.h)
                }
            }
            .frame(height: 20.h)
        }
        .padding(.horizontal, 38.w)
    }

    // MARK: - Email TextField
    private var emailTextField: some View {
        VStack(alignment: .leading, spacing: 4.s) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6.s)
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25))
                    .frame(height: 48.h)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6.s)
                            .stroke(emailError != nil ? Color.red : Color.white, lineWidth: 0.5)
                    )

                TextField("", text: $email, prompt: Text("Email or phone number")
                    .font(.system(size: 14.f))
                    .foregroundColor(.white))
                    .foregroundColor(.white)
                    .font(.system(size: 14.f))
                    .tracking(0.28)
                    .padding(.horizontal, 16.w)
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
                    .padding(.leading, 4.w)
            }
        }
    }

    // MARK: - Password TextField
    private var passwordTextField: some View {
        VStack(alignment: .leading, spacing: 4.s) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6.s)
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25))
                    .frame(height: 48.h)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6.s)
                            .stroke(passwordError != nil ? Color.red : Color.white, lineWidth: 0.5)
                    )

                HStack {
                    if showPassword {
                        TextField("", text: $password, prompt: Text("Password")
                            .font(.system(size: 14.f))
                            .foregroundColor(.white))
                            .foregroundColor(.white)
                            .font(.system(size: 14.f))
                            .tracking(0.28)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("loginPasswordTextField")
                            .focused($focusedField, equals: .password)
                    } else {
                        SecureField("", text: $password, prompt: Text("Password")
                            .font(.system(size: 14.f))
                            .foregroundColor(.white))
                            .foregroundColor(.white)
                            .font(.system(size: 14.f))
                            .tracking(0.28)
                            .accessibilityIdentifier("loginPasswordTextField")
                            .focused($focusedField, equals: .password)
                    }

                    Button(action: {
                        showPassword.toggle()
                    }) {
                        Image(systemName: showPassword ? "eye" : "eye.slash")
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 24.s, height: 24.s)
                    }
                }
                .padding(.horizontal, 16.w)
            }

            if let error = passwordError {
                Text(LocalizedStringKey(error))
                    .font(Typography.thin11)
                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                    .padding(.leading, 4.w)
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
            HStack(spacing: 8.s) {
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
            .frame(maxWidth: .infinity)
            .frame(height: 48.h)
            .background(.white)
            .cornerRadius(31.5.s)
        }
        .disabled(isLoading)
        .accessibilityIdentifier("signInButton")
    }

    // MARK: - Social Login Buttons
    private var socialLoginButtons: some View {
        ZStack {
            // Google Button
            Button(action: {
                Task {
                    await handleGoogleSignIn()
                }
            }) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 0.5)
                            .frame(width: 50.s, height: 50.s)
                        Image("Google-logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24.s, height: 24.s)
                    }
                    Text("Google")
                        .font(.system(size: 10.f))
                        .foregroundColor(.white)
                        .padding(.top, 8.s)
                }
            }
            .disabled(isLoading || isGoogleLoading || isAppleLoading || isPasskeyLoading)
            .offset(x: -78.w, y: 0)
            .accessibilityIdentifier("googleSignInButton")

            // Apple Button
            Button(action: {
                Task {
                    await handleAppleSignIn()
                }
            }) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 0.5)
                            .frame(width: 50.s, height: 50.s)
                        Image(systemName: "apple.logo")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white)
                            .frame(width: 24.s, height: 24.s)
                    }
                    Text("Apple")
                        .font(.system(size: 10.f))
                        .foregroundColor(.white)
                        .padding(.top, 8.s)
                }
            }
            .disabled(isLoading || isGoogleLoading || isAppleLoading || isPasskeyLoading)
            .offset(x: 0, y: 0)
            .accessibilityIdentifier("appleSignInButton")

            // Passkey Button
            if #available(iOS 16.0, *) {
                Button(action: {
                    Task {
                        await handlePasskeySignIn()
                    }
                }) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 0.5)
                                .frame(width: 50.s, height: 50.s)
                            Image("Passkey-icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24.s, height: 24.s)
                        }
                        Text("Passkey")
                            .font(.system(size: 10.f))
                            .foregroundColor(.white)
                            .padding(.top, 8.s)
                    }
                }
                .disabled(isLoading || isGoogleLoading || isAppleLoading || isPasskeyLoading)
                .offset(x: 78.w, y: 0)
                .accessibilityIdentifier("passkeySignInButton")
            }
        }
        .frame(width: 206.w, height: 70.h)
    }

    // MARK: - Create Account Link
    private var createAccountLink: some View {
        HStack(spacing: 4) {
            Text("New to Icered?")
                .font(Typography.regular14)
                .tracking(LetterSpacing.regular14)
                .foregroundColor(.white)

            Button(action: {
                currentPage = .inviteCode
            }) {
                Text("Create an Account")
                    .font(Typography.semibold14)
                    .tracking(LetterSpacing.semibold14)
                    .foregroundColor(.white)
                    .underline()
            }
            .accessibilityIdentifier("createAccountButton")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Terms and Privacy Links
    private var termsAndPrivacyLinks: some View {
        ZStack {
            Button(action: {
                // TODO: Show Terms and Conditions
            }) {
                Text("Terms and Conditions")
                    .font(.system(size: 10))
                    .underline()
                    .foregroundColor(.white)
            }
            .offset(x: -45, y: 0)

            Button(action: {
                // TODO: Show Privacy Statement
            }) {
                Text("Privacy Statement")
                    .font(.system(size: 10))
                    .underline()
                    .foregroundColor(.white)
            }
            .offset(x: 52.50, y: 0)
        }
        .frame(width: 181, height: 12)
    }

    // MARK: - Actions

    private func handleLogin() async {
        guard validateLogin() else { return }

        isLoading = true
        errorMessage = nil
        showErrorView = false

        do {
            _ = try await authManager.login(
                username: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            // Success - AuthenticationManager will update isAuthenticated
        } catch {
            // Provide user-friendly error messages
            if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                errorMessage = "Invalid email or password. Please check your credentials and try again."
                showErrorView = true
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                errorMessage = "Unable to connect to the server. Please check your internet connection and try again."
                showErrorView = true
            } else {
                errorMessage = "Login failed. Please try again later."
                showErrorView = true
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
        } catch let error as OAuthError {
            // Check for invite code required
            if error.requiresInviteCode {
                // Navigate to invite code page - SSO will retry after validation
                currentPage = .inviteCode
            } else if case .userCancelled = error {
                // User cancelled, no error message needed
            } else {
                errorMessage = error.localizedDescription
            }
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
        } catch let error as OAuthError {
            // Check for invite code required
            if error.requiresInviteCode {
                // Navigate to invite code page - SSO will retry after validation
                currentPage = .inviteCode
            } else if case .userCancelled = error {
                // User cancelled, no error message needed
            } else {
                errorMessage = error.localizedDescription
            }
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

    @available(iOS 16.0, *)
    private func handlePasskeySignIn() async {
        isPasskeyLoading = true
        errorMessage = nil

        do {
            let result = try await PasskeyService.shared.authenticateWithPasskey(userId: nil, anchor: nil)
            // Handle successful passkey authentication
            try await authManager.handlePasskeyAuthentication(result)
        } catch {
            let errorDesc = error.localizedDescription.lowercased()
            if errorDesc.contains("cancel") {
                // User cancelled, no error message needed
            } else {
                errorMessage = "Passkey authentication failed. Please try again."
                #if DEBUG
                print("[LoginView] Passkey error: \(error)")
                #endif
            }
        }

        isPasskeyLoading = false
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
