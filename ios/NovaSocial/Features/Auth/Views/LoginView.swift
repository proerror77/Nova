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
                // 使用固定高度替代Spacer，防止键盘推动布局
                Color.clear
                    .frame(height: max(0, (UIScreen.main.bounds.height - 812) / 2))

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
                        Text(LocalizedStringKey("Welcome_Title"))
                            .font(Font.custom("Helvetica Neue", size: 16).weight(.thin))
                            .lineSpacing(20)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .offset(x: 0.50, y: -180)

                        // Labels removed - placeholder text provides field hints

                        // Forgot password
                        Text(LocalizedStringKey("Forgot_Password"))
                            .font(Font.custom("Helvetica Neue", size: 10).weight(.light))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                            .offset(x: 132, y: 44)
                            .onTapGesture {
                                // TODO: Handle forgot password
                            }

                        // SHOW/HIDE password toggle
                        Text(showPassword ? LocalizedStringKey("Hide") : LocalizedStringKey("Show"))
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                            .lineSpacing(20)
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            .padding(.horizontal, 30)
                            .padding(.vertical, 24)
                            .contentShape(Rectangle())
                            .offset(x: 138.50, y: -10)
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
                                Text(LocalizedStringKey("Sign_In"))
                                    .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                                    .lineSpacing(20)
                                    .foregroundColor(.white)
                            }
                            .frame(width: 343, height: 46)
                            .background(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .cornerRadius(31.50)
                        }
                        .disabled(isLoading || isGoogleLoading)
                        .accessibilityIdentifier("signInButton")
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
                                    Image("GoogleLogo")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
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
                                Text(LocalizedStringKey("Create_An_Account"))
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
                        .accessibilityIdentifier("createAccountButton")
                        .offset(x: 0, y: 265)

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

                                TextField("", text: $email, prompt: Text(LocalizedStringKey("Enter_your_email")).foregroundColor(Color.white.opacity(0.4)))
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
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
                            .frame(width: 343, height: 49)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedField = .email
                            }

                            // Inline error for email - fixed height to prevent layout shift
                            Text(LocalizedStringKey(emailError ?? " "))
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
                                    TextField("", text: $password, prompt: Text(LocalizedStringKey("Enter_your_password")).foregroundColor(Color.white.opacity(0.4)))
                                        .foregroundColor(.white)
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .padding(.horizontal, 16)
                                        .padding(.trailing, 60)
                                        .autocapitalization(.none)
                                        .autocorrectionDisabled()
                                        .accessibilityIdentifier("loginPasswordTextField")
                                        .focused($focusedField, equals: .password)
                                } else {
                                    SecureField("", text: $password, prompt: Text(LocalizedStringKey("Enter_your_password")).foregroundColor(Color.white.opacity(0.4)))
                                        .foregroundColor(.white)
                                        .font(Font.custom("Helvetica Neue", size: 14))
                                        .padding(.horizontal, 16)
                                        .padding(.trailing, 60)
                                        .accessibilityIdentifier("loginPasswordTextField")
                                        .focused($focusedField, equals: .password)
                                }
                            }
                            .frame(width: 343, height: 49)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedField = .password
                            }

                            // Inline error for password - fixed height to prevent layout shift
                            Text(LocalizedStringKey(passwordError ?? " "))
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
