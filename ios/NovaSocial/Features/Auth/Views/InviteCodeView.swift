import SwiftUI

struct InviteCodeView: View {
    @Binding var currentPage: AppPage
    @State private var inviteCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    // Waitlist email collection
    @State private var showWaitlistForm = false
    @State private var waitlistEmail = ""
    @State private var isSubmittingWaitlist = false
    @State private var waitlistSuccess = false
    @State private var waitlistError: String?
    @FocusState private var isEmailFocused: Bool

    // Access AuthenticationManager for pending SSO retry
    @EnvironmentObject private var authManager: AuthenticationManager

    /// 整体内容垂直偏移（负值上移，正值下移）
    private let contentVerticalOffset: CGFloat = -50

    private var isInviteCodeValid: Bool { inviteCode.count == 6 }

    /// Whether we're retrying a pending SSO flow
    private var isPendingSSO: Bool { authManager.hasPendingSSO }

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

            // Content
            VStack(spacing: 0) {
                Spacer().frame(height: 167.h)
                logoSection
                Spacer().frame(height: 20.h)  // 167 + 52 + 20 = 239
                titleSection
                Spacer().frame(height: 30.h)  // 351 - 287 - 34(副标题高度) ≈ 30
                inviteCodeInput.padding(.horizontal, 37.w)
                errorMessageView
                Spacer().frame(height: 24.h)  // 423 - 351 - 48 = 24
                doneButton.padding(.horizontal, 37.w)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Back Button - 左上角
            VStack {
                HStack {
                    Button(action: {
                        // Clear pending SSO state when going back
                        authManager.clearPendingSSOState()
                        currentPage = .login
                    }) {
                        Image("back-white")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24.s, height: 24.s)
                    }
                    .padding(.leading, 16.w)
                    .padding(.top, 56.h)
                    Spacer()
                }
                Spacer()
            }

            // Bottom Notice - "Don't have an invite?" link
            VStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showWaitlistForm = true
                        waitlistError = nil
                        waitlistSuccess = false
                    }
                }) {
                    HStack(spacing: 6.s) {
                        Image("NoticeW")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12.s, height: 12.s)
                        Text("Don't have an invite? Join the waitlist")
                            .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                            .tracking(0.24)
                            .foregroundColor(Color(red: 0.64, green: 0.64, blue: 0.64))
                            .underline()
                    }
                }
                .padding(.bottom, 35.h)
            }

            // Waitlist Email Collection Sheet
            if showWaitlistForm {
                waitlistOverlay
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
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
        VStack(spacing: 19.h) {  // 287 - 239 - 29(标题高度) ≈ 19
            Text("Icered is invite only")
                .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                .foregroundColor(Color(red: 0.97, green: 0.97, blue: 0.97))

            Text("lf you have an invite code\nEnter it below.")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .tracking(0.28)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(red: 0.75, green: 0.75, blue: 0.75))
        }
    }

    private var inviteCodeInput: some View {
        ZStack {
            // 隐藏的输入框 - 6 位數字邀請碼
            TextField("", text: $inviteCode)
                .font(Font.custom("SFProDisplay-Light", size: 16.f))
                .foregroundColor(.clear)
                .accentColor(.clear)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .autocorrectionDisabled()
                .focused($isInputFocused)
                .onChange(of: inviteCode) { _, newValue in
                    // 只允許數字，最多 6 位
                    let filtered = newValue.filter { $0.isNumber }
                    inviteCode = String(filtered.prefix(6))
                }

            // 显示的文字 - 6 位數字邀請碼
            HStack(spacing: 8.s) {
                Text(inviteCode.isEmpty ? "——————" : "\(inviteCode)\(String(repeating: "—", count: max(0, 6 - inviteCode.count)))")
                    .font(Font.custom("SFProDisplay-Light", size: 18.f))
                    .tracking(6)
                    .lineSpacing(20)
                    .foregroundColor(Color(red: 0.97, green: 0.97, blue: 0.97))
            }
            .allowsHitTesting(false)
        }
        .padding(EdgeInsets(top: 13.h, leading: 114.w, bottom: 13.h, trailing: 114.w))
        .frame(width: 300.w, height: 48.h)
        .background(Color(red: 0.85, green: 0.85, blue: 0.85).opacity(0.25))
        .cornerRadius(43.s)
        .overlay(
            RoundedRectangle(cornerRadius: 43.s)
                .inset(by: 0.50)
                .stroke(.white, lineWidth: 0.50)
        )
        .onTapGesture { isInputFocused = true }
    }

    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage {
            Text(LocalizedStringKey(errorMessage))
                .font(Typography.regular12)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40.w)
                .padding(.top, 12.h)
        }
    }

    private var doneButton: some View {
        Button(action: { Task { await validateInviteCode() } }) {
            HStack(spacing: 8.s) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                }
                Text("Submit")
                    .font(Font.custom("SFProDisplay-Heavy", size: 16.f))
                    .tracking(0.32)
                    .foregroundColor(.black)
            }
            .frame(width: 300.w, height: 48.h)
            .background(Color.white.opacity(isInviteCodeValid ? 1 : 0.5))
            .cornerRadius(43.s)
        }
        .disabled(!isInviteCodeValid || isLoading)
    }

    // MARK: - Waitlist Components

    private var waitlistOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showWaitlistForm = false
                        isEmailFocused = false
                    }
                }

            // Waitlist form card
            VStack(spacing: 20.h) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showWaitlistForm = false
                            isEmailFocused = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                if waitlistSuccess {
                    // Success state
                    VStack(spacing: 16.h) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)

                        Text("You're on the list!")
                            .font(Font.custom("SFProDisplay-Semibold", size: 20.f))
                            .foregroundColor(.white)

                        Text("We'll notify you when access opens.")
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)

                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                showWaitlistForm = false
                            }
                        }) {
                            Text("Done")
                                .font(Font.custom("SFProDisplay-Heavy", size: 16.f))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48.h)
                                .background(Color.white)
                                .cornerRadius(24.s)
                        }
                    }
                } else {
                    // Input state
                    VStack(spacing: 16.h) {
                        Text("Join the Waitlist")
                            .font(Font.custom("SFProDisplay-Semibold", size: 20.f))
                            .foregroundColor(.white)

                        Text("Enter your email and we'll notify you\nwhen access opens.")
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)

                        // Email input
                        TextField("", text: $waitlistEmail, prompt: Text("Email address")
                            .foregroundColor(.white.opacity(0.5)))
                            .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                            .foregroundColor(.white)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isEmailFocused)
                            .padding(.horizontal, 16.w)
                            .frame(height: 48.h)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(24.s)
                            .overlay(
                                RoundedRectangle(cornerRadius: 24.s)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )

                        // Error message
                        if let error = waitlistError {
                            Text(error)
                                .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                                .foregroundColor(.red)
                        }

                        // Submit button
                        Button(action: {
                            Task { await submitWaitlistEmail() }
                        }) {
                            HStack(spacing: 8.s) {
                                if isSubmittingWaitlist {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .scaleEffect(0.9)
                                }
                                Text("Join Waitlist")
                                    .font(Font.custom("SFProDisplay-Heavy", size: 16.f))
                                    .foregroundColor(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48.h)
                            .background(isValidEmail ? Color.white : Color.white.opacity(0.5))
                            .cornerRadius(24.s)
                        }
                        .disabled(!isValidEmail || isSubmittingWaitlist)
                    }
                }
            }
            .padding(24.s)
            .background(
                RoundedRectangle(cornerRadius: 20.s)
                    .fill(Color(red: 0.1, green: 0.15, blue: 0.25))
            )
            .padding(.horizontal, 32.w)
        }
    }

    private var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: waitlistEmail)
    }

    private func submitWaitlistEmail() async {
        guard isValidEmail else {
            waitlistError = "Please enter a valid email address"
            return
        }

        isSubmittingWaitlist = true
        waitlistError = nil

        do {
            struct WaitlistRequest: Codable {
                let email: String
            }

            struct WaitlistResponse: Codable {
                let success: Bool
                let message: String?
            }

            let request = WaitlistRequest(email: waitlistEmail)
            let _: WaitlistResponse = try await APIClient.shared.request(
                endpoint: APIConfig.Invitations.waitlist,
                method: "POST",
                body: request
            )

            await MainActor.run {
                waitlistSuccess = true
            }
        } catch {
            #if DEBUG
            print("[InviteCodeView] Waitlist submission error: \(error)")
            #endif
            await MainActor.run {
                waitlistError = "Failed to join waitlist. Please try again."
            }
        }

        isSubmittingWaitlist = false
    }

    // MARK: - Validation

    private func validateInviteCode() async {
        guard isInviteCodeValid else { return }

        isLoading = true
        errorMessage = nil

        do {
            struct ValidateResponse: Codable {
                let isValid: Bool
                let issuerUsername: String?
                let expiresAt: Int64?
                let error: String?
            }

            let endpoint = "\(APIConfig.Invitations.validate)?code=\(inviteCode)"
            let response: ValidateResponse = try await APIClient.shared.request(endpoint: endpoint, method: "GET")

            if response.isValid {
                // Store the validated invite code for use in registration
                await MainActor.run {
                    authManager.validatedInviteCode = inviteCode
                }

                // Check if we have a pending SSO flow to retry
                if isPendingSSO {
                    await retrySSOWithInviteCode()
                } else {
                    // Normal flow - go to create account
                    await MainActor.run { currentPage = .createAccount }
                }
            } else {
                errorMessage = response.error ?? "Invalid_invite_code_generic"
            }
        } catch {
            // Handle network errors with detailed APIError handling
            #if DEBUG
            print("[InviteCodeView] Invite code validation error: \(error)")
            print("[InviteCodeView] Error details: \(error.localizedDescription)")
            print("[InviteCodeView] Error type: \(type(of: error))")
            #endif

            if let apiError = error as? APIError {
                switch apiError {
                case .timeout, .noConnection, .networkError(_), .invalidResponse:
                    // Clear network-related errors
                    errorMessage = "Network_error"
                case .serverError(let statusCode, _):
                    if statusCode >= 500 {
                        // Backend / gateway unavailable (e.g. 503), treat as network issue
                        errorMessage = "Network_error"
                    } else {
                        // 4xx from server – treat as invalid code for now
                        errorMessage = "Invalid_invite_code_generic"
                    }
                case .notFound:
                    // Invite endpoint / code not found
                    errorMessage = "Invalid_invite_code_generic"
                default:
                    errorMessage = "Invalid_invite_code_generic"
                }
            } else if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                errorMessage = "Network_error"
            } else {
                errorMessage = "Invalid_invite_code_generic"
            }
        }

        isLoading = false
    }

    /// Retry pending SSO flow with the validated invite code
    @MainActor
    private func retrySSOWithInviteCode() async {
        do {
            let _ = try await authManager.retrySSOWithInviteCode(inviteCode)
            // Success - AuthenticationManager will update isAuthenticated
            // The auth state change will navigate away from this view
        } catch let error as OAuthError {
            if case .invalidInviteCode(let message) = error {
                errorMessage = message
            } else if error.requiresInviteCode {
                // Still requires invite code - shouldn't happen after validation
                errorMessage = "Invalid_invite_code_generic"
            } else if case .userCancelled = error {
                // User cancelled - go back to login
                authManager.clearPendingSSOState()
                currentPage = .login
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            #if DEBUG
            print("[InviteCodeView] SSO retry error: \(error)")
            #endif
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    InviteCodeView(currentPage: .constant(.inviteCode))
        .environmentObject(AuthenticationManager.shared)
}
