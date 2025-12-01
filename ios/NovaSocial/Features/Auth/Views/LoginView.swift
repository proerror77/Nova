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
    @State private var errorMessage: String?
    @State private var showPassword = false

    // MARK: - Validation State
    @State private var emailError: String?
    @State private var passwordError: String?

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
                                await handleLogin()
                            }
                        }) {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                                Text("Sign In")
                                    .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                                    .lineSpacing(20)
                                    .foregroundColor(.white)
                            }
                            .frame(width: 343, height: 46)
                            .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .cornerRadius(31.50)
                        }
                        .disabled(isLoading || isGoogleLoading)
                        .offset(x: 0, y: 87)

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
                                } else {
                                    // Google Logo
                                    Image(systemName: "g.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.red)
                                }
                                Text("Continue with Google")
                                    .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                                    .foregroundColor(.black)
                            }
                            .frame(width: 343, height: 46)
                            .background(Color.white)
                            .cornerRadius(31.50)
                        }
                        .disabled(isLoading || isGoogleLoading)
                        .offset(x: 0, y: 145)

                        // "or you can" text
                        Text("or you can")
                            .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                            .lineSpacing(20)
                            .foregroundColor(.white)
                            .offset(x: 0.50, y: 208)

                        // Create Account Button - 跳转到 CreateAccountView
                        Button(action: {
                            currentPage = .createAccount
                        }) {
                            HStack(spacing: 8) {
                                Text("Create An Account")
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
                        .offset(x: 0, y: 265)

                        // Skip Button - 跳过登录直接进入Home（临时登录模式）
                        Button(action: {
                            // 设置临时登录状态
                            AuthenticationManager.shared.setGuestMode()
                            currentPage = .home
                        }) {
                            Text("Skip")
                                .font(Font.custom("Helvetica Neue", size: 14).weight(.light))
                                .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                                .underline()
                        }
                        .offset(x: 0, y: 330)

                        // Skip Button - 跳过登录直接进入Home（临时登录模式）
                        Button(action: {
                            // 设置临时登录状态
                            AuthenticationManager.shared.setGuestMode()
                            currentPage = .home
                        }) {
                            Text("Skip")
                                .font(Font.custom("Helvetica Neue", size: 14).weight(.light))
                                .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                                .underline()
                        }
                        .offset(x: 0, y: 280)

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
                            .frame(width: 343, height: 49)

                            // Inline error for email - fixed height to prevent layout shift
                            Text(emailError ?? " ")
                                .font(Font.custom("Helvetica Neue", size: 11))
                                .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                                .padding(.leading, 4)
                                .opacity(emailError != nil ? 1 : 0)
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
                                } else {
                                    SecureField("", text: $password, prompt: Text("Enter your password").foregroundColor(Color.white.opacity(0.4)))
                                        .foregroundColor(.white)
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .padding(.horizontal, 16)
                                        .padding(.trailing, 60)
                                }
                            }
                            .frame(width: 343, height: 49)

                            // Inline error for password - fixed height to prevent layout shift
                            Text(passwordError ?? " ")
                                .font(Font.custom("Helvetica Neue", size: 11))
                                .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                                .padding(.leading, 4)
                                .opacity(passwordError != nil ? 1 : 0)
                        }
                        .offset(x: 0, y: -0.50)

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
            _ = try await authManager.login(
                username: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            // Success - AuthenticationManager will update isAuthenticated
        } catch {
            // Provide user-friendly error messages
            if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                errorMessage = "Invalid email or password. Please try again."
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                errorMessage = "Network error. Please check your connection."
            } else {
                errorMessage = "Login failed. Please try again."
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
}
