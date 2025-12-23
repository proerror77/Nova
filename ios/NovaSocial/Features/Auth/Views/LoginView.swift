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
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea(.all)

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
                            .frame(height: 32)

                        // Login Button
                        loginButton
                            .padding(.horizontal, 38.w)

                        Spacer()
                            .frame(height: 24)

                        // "or" separator
                        Text("or")
                            .font(Font.custom("SF Pro Display", size: 16.f))
                            .foregroundColor(.white)

                        Spacer()
                            .frame(height: 12.s)

                        // Social Login Buttons
                        socialLoginButtons
                            .padding(.horizontal, 38.w)

                        Spacer()
                            .frame(height: 40)

                        // Create Account Link
                        createAccountLink

                        Spacer()

                        // Terms and Privacy Links
                        termsAndPrivacyLinks
                            .padding(.bottom, 28.h)
                    }
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
                .font(Font.custom("SF Pro Display", size: 12.f).weight(.medium))
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
                        // TODO: Handle forgot password
                    }) {
                        Text("Forgot password?")
                            .font(Font.custom("SF Pro Display", size: 14.f))
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
                    .font(Font.custom("SF Pro Display", size: 14.f))
                    .foregroundColor(.white))
                    .foregroundColor(.white)
                    .font(Font.custom("SF Pro Display", size: 14.f))
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
                            .font(Font.custom("SF Pro Display", size: 14.f))
                            .foregroundColor(.white))
                            .foregroundColor(.white)
                            .font(Font.custom("SF Pro Display", size: 14.f))
                            .tracking(0.28)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("loginPasswordTextField")
                            .focused($focusedField, equals: .password)
                    } else {
                        SecureField("", text: $password, prompt: Text("Password")
                            .font(Font.custom("SF Pro Display", size: 14.f))
                            .foregroundColor(.white))
                            .foregroundColor(.white)
                            .font(Font.custom("SF Pro Display", size: 14.f))
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
        .disabled(isLoading || isGoogleLoading || isAppleLoading)
        .accessibilityIdentifier("signInButton")
    }

    // MARK: - Social Login Buttons
    private var socialLoginButtons: some View {
        VStack(spacing: 10.s) {
            // Continue with Passkey
            if #available(iOS 16.0, *) {
                Button(action: {
                    Task {
                        await handlePasskeySignIn()
                    }
                }) {
                    ZStack {
                        // 文字居中
                        HStack(spacing: 8.s) {
                            if isPasskeyLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text("Continue with Passkey")
                                .font(.system(size: 16.f, weight: .heavy, design: .default))
                                .tracking(0.32)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        
                        // 图标固定在左侧
                        HStack {
                            ZStack {
                                Image("Passkey-icon")
                                    .resizable()
                                    .scaledToFit()
                            }
                            .frame(width: 24.s, height: 24.s)
                            Spacer()
                        }
                        .padding(.leading, 22.w)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48.h)
                    .background(Color.clear)
                    .cornerRadius(31.5.s)
                    .overlay(
                        RoundedRectangle(cornerRadius: 31.5.s)
                            .stroke(.white, lineWidth: 0.5)
                    )
                }
                .disabled(isLoading || isGoogleLoading || isAppleLoading || isPasskeyLoading)
                .accessibilityIdentifier("passkeySignInButton")
            }

            // Continue with Google
            Button(action: {
                Task {
                    await handleGoogleSignIn()
                }
            }) {
                ZStack {
                    // 文字居中
                    HStack(spacing: 8.s) {
                        if isGoogleLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text("Continue with Google")
                            .font(.system(size: 16.f, weight: .heavy, design: .default))
                            .tracking(0.32)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // 图标固定在左侧
                    HStack {
                        ZStack {
                            Image("Google-logo")
                                .resizable()
                                .scaledToFit()
                        }
                        .frame(width: 24.s, height: 24.s)
                        Spacer()
                    }
                    .padding(.leading, 22.w)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48.h)
                .background(Color.clear)
                .cornerRadius(31.5.s)
                .overlay(
                    RoundedRectangle(cornerRadius: 31.5.s)
                        .stroke(.white, lineWidth: 0.5)
                )
            }
            .disabled(isLoading || isGoogleLoading || isAppleLoading || isPasskeyLoading)
            .accessibilityIdentifier("googleSignInButton")

            // Continue with Apple
            Button(action: {
                Task {
                    await handleAppleSignIn()
                }
            }) {
                ZStack {
                    // 文字居中
                    HStack(spacing: 8.s) {
                        if isAppleLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text("Continue with Apple")
                            .font(.system(size: 16.f, weight: .heavy, design: .default))
                            .tracking(0.32)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    // 图标固定在左侧
                    HStack {
                        ZStack {
                            Image(systemName: "apple.logo")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.white)
                        }
                        .frame(width: 24.s, height: 24.s)
                        Spacer()
                    }
                    .padding(.leading, 22.w)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48.h)
                .background(Color.clear)
                .cornerRadius(31.5.s)
                .overlay(
                    RoundedRectangle(cornerRadius: 31.5.s)
                        .stroke(.white, lineWidth: 0.5)
                )
            }
            .disabled(isLoading || isGoogleLoading || isAppleLoading || isPasskeyLoading)
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
        HStack(spacing: 5.w) {
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
        .padding(.leading, 94.w)
        .frame(maxWidth: .infinity, alignment: .leading)
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
