import SwiftUI

// MARK: - Login View

struct LoginView: View {
    // MARK: - Bindings
    @Binding var currentPage: AppPage

    // MARK: - State
    @State private var isLoginMode = true
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false

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

                        // EMAIL Label
                        Text(isLoginMode ? "EMAIL" : "USERNAME")
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                            .lineSpacing(20)
                            .foregroundColor(.white)
                            .offset(x: -139.50, y: -70)

                        // PASSWORD Label
                        Text("PASSWORD")
                            .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                            .lineSpacing(20)
                            .foregroundColor(.white)
                            .offset(x: -123.50, y: -1)

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

                        // Skip to Home (临时开发用)
                        Button(action: {
                            currentPage = .home
                        }) {
                            Text("Skip")
                                .font(Font.custom("Helvetica Neue", size: 14).weight(.light))
                                .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                        }
                        .offset(x: 0, y: 270)

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
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .foregroundColor(.clear)
                                .frame(width: 343, height: 49)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .inset(by: 0.20)
                                        .stroke(.white, lineWidth: 0.20)
                                )

                            if isLoginMode {
                                TextField("", text: $email)
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                            } else {
                                TextField("", text: $username)
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                            }
                        }
                        .offset(x: 0, y: -69.50)

                        // Password Input Field
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .foregroundColor(.clear)
                                .frame(width: 343, height: 49)
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .inset(by: 0.20)
                                        .stroke(.white, lineWidth: 0.20)
                                )

                            if showPassword {
                                TextField("", text: $password)
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .padding(.trailing, 60)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("", text: $password)
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .padding(.trailing, 60)
                            }
                        }
                        .offset(x: 0, y: -0.50)

                        // Additional field for registration: Email (when in register mode)
                        if !isLoginMode {
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .foregroundColor(.clear)
                                    .frame(width: 343, height: 49)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .inset(by: 0.20)
                                            .stroke(.white, lineWidth: 0.20)
                                    )

                                TextField("", text: $email)
                                    .foregroundColor(.white)
                                    .font(Font.custom("Helvetica Neue", size: 14))
                                    .padding(.horizontal, 16)
                                    .autocapitalization(.none)
                                    .keyboardType(.emailAddress)
                                    .autocorrectionDisabled()
                            }
                            .offset(x: 0, y: -138)

                            Text("EMAIL")
                                .font(Font.custom("Helvetica Neue", size: 12).weight(.light))
                                .lineSpacing(20)
                                .foregroundColor(.white)
                                .offset(x: -139.50, y: -138)
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
            // Success - Navigate to home page
            await MainActor.run {
                currentPage = .home
            }
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
            // Success - Navigate to home page
            await MainActor.run {
                currentPage = .home
            }
        } catch {
            errorMessage = "Registration failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func toggleMode() {
        isLoginMode.toggle()
        errorMessage = nil
        // Clear fields when switching modes
        email = ""
        username = ""
        password = ""
        displayName = ""
    }

    // MARK: - Validation

    private func validateLogin() -> Bool {
        if email.isEmpty {
            errorMessage = "Please enter your email"
            return false
        }

        if password.isEmpty {
            errorMessage = "Please enter your password"
            return false
        }

        return true
    }

    private func validateRegister() -> Bool {
        if username.isEmpty {
            errorMessage = "Please enter a username"
            return false
        }

        if email.isEmpty {
            errorMessage = "Please enter an email"
            return false
        }

        if password.isEmpty {
            errorMessage = "Please enter a password"
            return false
        }

        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters"
            return false
        }

        return true
    }
}

// MARK: - Preview

#Preview {
    LoginView(currentPage: .constant(.login))
}
