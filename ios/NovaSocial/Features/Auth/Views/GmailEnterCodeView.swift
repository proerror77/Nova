import SwiftUI

/// Gmail Enter Code View - Email Verification
/// Verification code entry screen for email registration and login flow
struct GmailEnterCodeView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager

    /// The email address for verification
    let email: String

    /// Mode: registration or login (default: registration for backward compatibility)
    var mode: Mode = .registration

    enum Mode {
        case registration
        case login
    }
    
    // MARK: - State
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var countdown: Int = 60
    @State private var canResend = false
    @State private var verificationToken = ""
    @FocusState private var isInputFocused: Bool
    
    /// Timer for countdown
    @State private var timer: Timer?
    
    private var isCodeValid: Bool { verificationCode.count == 6 }
    
    /// Masked email for display (e.g., "***@gmail.com")
    private var maskedEmail: String {
        guard let atIndex = email.firstIndex(of: "@") else { return email }
        let domain = String(email[atIndex...])
        return "***\(domain)"
    }
    
    var body: some View {
        ZStack {
            // Background - Linear Gradient
            LinearGradient(
                colors: [
                    Color(red: 0.027, green: 0.106, blue: 0.212),  // #071B36
                    Color(red: 0.271, green: 0.310, blue: 0.388)   // #454F63
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Content - 响应式垂直布局
            VStack(spacing: 0) {
                Spacer().frame(height: 114.h)  // 顶部间距
                logoSection
                Spacer().frame(height: 43.h)
                titleSection
                Spacer().frame(height: 30.h)
                codeInputSection.padding(.horizontal, 37.w)
                errorMessageView
                Spacer().frame(height: 24.h)
                verifyButton  // 按钮有固定宽度 301.w，自动居中
                Spacer(minLength: 100.h)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Back Button Header - Figma: 距顶部44pt, padding 8pt, 高度64pt
            VStack(spacing: 0) {
                Spacer().frame(height: 44.h)  // 状态栏高度
                HStack(spacing: 8.s) {
                    Button(action: {
                        // Navigate back based on mode
                        if mode == .login {
                            currentPage = .login
                        } else {
                            currentPage = .createAccountPhoneNumber
                        }
                    }) {
                        ZStack {
                            Image("back-white")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24.s, height: 24.s)
                        }
                        .frame(width: 40.s, height: 40.s)
                        .cornerRadius(100.s)
                    }
                    .frame(width: 48.s, height: 48.s)
                    Spacer()
                }
                .padding(.horizontal, 8.s)
                .frame(height: 64.h)
                Spacer()
            }

            // Bottom Notice - Resend code section
            GeometryReader { geometry in
                VStack(spacing: 8.h) {
                    Button(action: {
                        Task { await resendCode() }
                    }) {
                        Text("Resend code")
                            .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
                            .tracking(0.28)
                            .foregroundColor(.white)
                            .underline()
                    }
                    .disabled(!canResend || isLoading)

                    if !canResend {
                        Text("You can request a new code in \(countdown) seconds.")
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .tracking(0.28)
                            .foregroundColor(Color(red: 0.75, green: 0.75, blue: 0.75))
                    }
                }
                .frame(maxWidth: .infinity)
                .position(x: geometry.size.width / 2, y: geometry.size.height - 308.h)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .onAppear {
            startCountdown()
            isInputFocused = true
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Components
    
    private var logoSection: some View {
        ZStack {
            Image("Login-Icon")
                .resizable()
                .scaledToFit()
        }
        .frame(width: 84.w, height: 52.h)
    }
    
    private var titleSection: some View {
        VStack(spacing: 12.h) {
            Text("Enter your confirmation code")
                .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                .foregroundColor(.white)
            
            Text("A verification code was sent to \(maskedEmail).")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .tracking(0.28)
                .foregroundColor(Color(red: 0.75, green: 0.75, blue: 0.75))
        }
    }
    
    private var codeInputSection: some View {
        ZStack {
            // Hidden text field for input - 6 digit code
            TextField("", text: $verificationCode)
                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                .foregroundColor(.clear)
                .accentColor(.clear)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                .focused($isInputFocused)
                .onChange(of: verificationCode) { _, newValue in
                    // Only allow digits, max 6
                    let filtered = newValue.filter { $0.isNumber }
                    verificationCode = String(filtered.prefix(6))
                    
                    // Auto-verify when 6 digits entered
                    if verificationCode.count == 6 {
                        Task { await verifyCode() }
                    }
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)
            
            // 6 individual input boxes - matching Figma design
            HStack(spacing: 10.s) {
                ForEach(0..<6, id: \.self) { index in
                    codeBox(at: index)
                }
            }
        }
        .onTapGesture { isInputFocused = true }
    }
    
    /// Single code input box
    private func codeBox(at index: Int) -> some View {
        let characters = Array(verificationCode)
        let character = index < characters.count ? String(characters[index]) : ""
        let isCurrentIndex = index == verificationCode.count && isInputFocused
        
        return ZStack {
            // Display entered character
            Text(character)
                .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                .foregroundColor(.white)
        }
        .frame(width: 40.w, height: 49.h)
        .cornerRadius(12.s)
        .overlay(
            RoundedRectangle(cornerRadius: 12.s)
                .inset(by: 0.5)
                .stroke(
                    isCurrentIndex ? Color.white : Color(red: 0.41, green: 0.41, blue: 0.41),
                    lineWidth: 0.5
                )
        )
    }
    
    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage {
            Text(LocalizedStringKey(errorMessage))
                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40.w)
                .padding(.top, 12.h)
        }
    }
    
    private var verifyButton: some View {
        Button(action: { Task { await verifyCode() } }) {
            HStack(spacing: 10.s) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                }
                Text("Verify")
                    .font(Font.custom("SFProDisplay-Bold", size: 16.f))
                    .foregroundColor(.black)
            }
            .frame(width: 301.w, height: 48.h)
            .background(Color.white)
            .cornerRadius(50.s)
        }
        .disabled(!isCodeValid || isLoading)
    }
    
    // MARK: - Timer
    
    private func startCountdown() {
        countdown = 60
        canResend = false
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if countdown > 0 {
                countdown -= 1
            } else {
                canResend = true
                timer?.invalidate()
            }
        }
    }
    
    // MARK: - API Actions
    
    private func verifyCode() async {
        guard isCodeValid else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await EmailAuthService.shared.verifyCode(
                email: email,
                code: verificationCode
            )
            
            if response.success, let token = response.verificationToken {
                verificationToken = token
                // Store verification token with timestamp for next step
                authManager.setEmailVerificationToken(token, email: email)

                // Handle based on mode
                if mode == .login {
                    // Login flow: call loginWithEmail API
                    await performLogin(verificationToken: token)
                } else {
                    // Registration flow: navigate to invite code page
                    await MainActor.run {
                        currentPage = .inviteCode
                    }
                }
            } else {
                errorMessage = response.message ?? "Verification failed"
                verificationCode = ""
            }
        } catch let emailError as EmailAuthError {
            #if DEBUG
            print("[GmailEnterCodeView] Verification error: \(emailError)")
            #endif
            switch emailError {
            case .invalidCode:
                errorMessage = "Invalid code. Please check and try again."
            case .codeExpired:
                errorMessage = "Code has expired. Please request a new code."
            case .rateLimited:
                errorMessage = "Too many attempts. Please wait before trying again."
            case .networkError:
                errorMessage = "Unable to connect. Please check your internet connection."
            case .serverError(let message):
                errorMessage = message
            default:
                errorMessage = emailError.localizedDescription
            }
            verificationCode = ""
        } catch {
            #if DEBUG
            print("[GmailEnterCodeView] Unexpected error: \(error)")
            #endif
            errorMessage = "An unexpected error occurred. Please try again."
            verificationCode = ""
        }
        
        isLoading = false
    }
    
    private func resendCode() async {
        guard canResend else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await EmailAuthService.shared.sendVerificationCode(email: email)
            
            if response.success {
                // Restart countdown
                await MainActor.run {
                    startCountdown()
                }
            } else {
                errorMessage = response.message ?? "Failed to resend code"
            }
        } catch let emailError as EmailAuthError {
            #if DEBUG
            print("[GmailEnterCodeView] Resend error: \(emailError)")
            #endif
            switch emailError {
            case .rateLimited:
                errorMessage = "Too many attempts. Please wait before trying again."
            case .networkError:
                errorMessage = "Unable to connect. Please check your internet connection."
            default:
                errorMessage = emailError.localizedDescription
            }
        } catch {
            #if DEBUG
            print("[GmailEnterCodeView] Unexpected resend error: \(error)")
            #endif
            errorMessage = "Failed to resend code. Please try again."
        }

        isLoading = false
    }

    /// Perform login with verified email
    private func performLogin(verificationToken: String) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await EmailAuthService.shared.loginWithEmail(
                email: email,
                verificationToken: verificationToken
            )

            #if DEBUG
            print("[GmailEnterCodeView] Login successful: userId=\(response.userId)")
            #endif

            // Create user profile from response
            let user = response.user ?? UserProfile(
                id: response.userId,
                username: "user_\(response.userId.prefix(8))",
                email: email,
                displayName: nil,
                bio: nil,
                avatarUrl: nil,
                coverUrl: nil,
                website: nil,
                location: nil,
                isVerified: false,
                isPrivate: false,
                isBanned: false,
                followerCount: 0,
                followingCount: 0,
                postCount: 0,
                createdAt: nil,
                updatedAt: nil,
                deletedAt: nil,
                firstName: nil,
                lastName: nil,
                dateOfBirth: nil,
                gender: nil
            )

            // Save authentication
            await MainActor.run {
                authManager.authToken = response.token
                authManager.currentUser = user
                authManager.isAuthenticated = true
                APIClient.shared.setAuthToken(response.token)

                // Save to keychain
                _ = KeychainService.shared.save(response.token, for: .authToken)
                _ = KeychainService.shared.save(user.id, for: .userId)
                if let refreshToken = response.refreshToken {
                    _ = KeychainService.shared.save(refreshToken, for: .refreshToken)
                }
            }

            // Login successful - AuthenticationManager will trigger navigation

        } catch EmailAuthError.emailNotRegistered {
            errorMessage = "No account found with this email. Please sign up first."
        } catch let emailError as EmailAuthError {
            #if DEBUG
            print("[GmailEnterCodeView] Login error: \(emailError)")
            #endif
            switch emailError {
            case .networkError:
                errorMessage = "Unable to connect. Please check your internet connection."
            case .serverError(let message):
                errorMessage = message
            default:
                errorMessage = emailError.localizedDescription
            }
        } catch {
            #if DEBUG
            print("[GmailEnterCodeView] Unexpected login error: \(error)")
            #endif
            errorMessage = "Login failed. Please try again."
        }

        isLoading = false
    }
}

#Preview {
    GmailEnterCodeView(
        currentPage: .constant(.gmailEnterCode(email: "user@gmail.com")),
        email: "user@gmail.com"
    )
    .environmentObject(AuthenticationManager.shared)
}
