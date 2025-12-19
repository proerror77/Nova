import SwiftUI

// MARK: - Phone Login View

/// Two-step phone login flow
/// Step 1: Enter phone number
/// Step 2: Verify OTP code → Login
struct PhoneLoginView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Binding var currentPage: AppPage

    // MARK: - State
    @State private var currentStep: LoginStep = .phoneInput
    @State private var phoneNumber = ""
    @State private var selectedCountryCode = "+886"
    @State private var otpCode = ""
    @State private var verificationToken = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showNotRegisteredAlert = false
    @State private var resendCountdown: Int = 0
    @State private var resendTimer: Timer?

    enum LoginStep {
        case phoneInput
        case otpVerification
    }

    // Common country codes
    let countryCodes = [
        ("+886", "TW"),
        ("+1", "US/CA"),
        ("+44", "UK"),
        ("+86", "CN"),
        ("+852", "HK"),
        ("+81", "JP"),
        ("+82", "KR"),
        ("+65", "SG"),
        ("+61", "AU"),
        ("+49", "DE"),
        ("+33", "FR")
    ]

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                // Content based on step
                ScrollView {
                    VStack(spacing: 24) {
                        switch currentStep {
                        case .phoneInput:
                            phoneInputSection
                        case .otpVerification:
                            otpVerificationSection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                }

                Spacer()
            }
        }
        .navigationBarHidden(true)
        .alert("Phone Not Registered", isPresented: $showNotRegisteredAlert) {
            Button("Register") {
                currentPage = .phoneRegistration
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This phone number is not registered. Would you like to create an account?")
        }
        .onDisappear {
            resendTimer?.invalidate()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: handleBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
            }

            Spacer()

            Text(headerTitle)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            // Placeholder for alignment
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.clear)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var headerTitle: String {
        switch currentStep {
        case .phoneInput:
            return "Login with Phone"
        case .otpVerification:
            return "Verify Code"
        }
    }

    // MARK: - Phone Input Section

    private var phoneInputSection: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "phone.fill")
                .font(.system(size: 50))
                .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                .padding(.bottom, 20)

            // Description
            Text("Enter your phone number to receive a verification code")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Phone input
            HStack(spacing: 12) {
                // Country code picker
                Menu {
                    ForEach(countryCodes, id: \.0) { code, name in
                        Button("\(code) (\(name))") {
                            selectedCountryCode = code
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedCountryCode)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }

                // Phone number field
                TextField("", text: $phoneNumber, prompt: Text("Phone Number").foregroundColor(.gray))
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .keyboardType(.phonePad)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            // Send Code button
            Button(action: {
                Task { await sendVerificationCode() }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text("Send Code")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isPhoneValid ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.gray)
                .cornerRadius(25)
            }
            .disabled(!isPhoneValid || isLoading)
            .padding(.top, 20)

            // Register link
            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)

                Button(action: {
                    currentPage = .phoneRegistration
                }) {
                    Text("Register")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: - OTP Verification Section

    private var otpVerificationSection: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 50))
                .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                .padding(.bottom, 20)

            // Description
            Text("Enter the 6-digit code sent to\n\(fullPhoneNumber)")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            // OTP Input
            OTPInputView(code: $otpCode, codeLength: 6)
                .onChange(of: otpCode) { _, newValue in
                    if newValue.count == 6 {
                        Task { await verifyAndLogin() }
                    }
                }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            // Loading indicator
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            }

            // Verify button (optional, for manual submit)
            Button(action: {
                Task { await verifyAndLogin() }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text("Verify & Login")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(otpCode.count == 6 ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.gray)
                .cornerRadius(25)
            }
            .disabled(otpCode.count != 6 || isLoading)

            // Resend code button
            Button(action: {
                Task { await sendVerificationCode() }
            }) {
                if resendCountdown > 0 {
                    Text("Resend Code (\(resendCountdown)s)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                } else {
                    Text("Resend Code")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                }
            }
            .disabled(isLoading || resendCountdown > 0)
            .padding(.top, 10)
        }
    }

    // MARK: - Computed Properties

    private var fullPhoneNumber: String {
        "\(selectedCountryCode)\(phoneNumber)"
    }

    private var isPhoneValid: Bool {
        phoneNumber.count >= 7 && phoneNumber.allSatisfy { $0.isNumber }
    }

    // MARK: - Actions

    private func handleBack() {
        switch currentStep {
        case .phoneInput:
            currentPage = .login
        case .otpVerification:
            currentStep = .phoneInput
            otpCode = ""
            errorMessage = nil
            resendTimer?.invalidate()
            resendCountdown = 0
        }
    }

    private func sendVerificationCode() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await PhoneAuthService.shared.sendVerificationCode(phoneNumber: fullPhoneNumber)
            if response.success {
                await MainActor.run {
                    currentStep = .otpVerification
                    startResendCountdown()
                }
            } else {
                errorMessage = response.message ?? "Failed to send code"
            }
        } catch let error as PhoneAuthError {
            switch error {
            case .phoneNotRegistered:
                await MainActor.run {
                    showNotRegisteredAlert = true
                }
            case .rateLimited:
                errorMessage = "Too many attempts. Please try again later."
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func verifyAndLogin() async {
        isLoading = true
        errorMessage = nil

        do {
            // Step 1: Verify OTP code
            let verifyResponse = try await PhoneAuthService.shared.verifyCode(
                phoneNumber: fullPhoneNumber,
                code: otpCode
            )

            guard verifyResponse.success, let token = verifyResponse.verificationToken else {
                errorMessage = verifyResponse.message ?? "Verification failed"
                otpCode = ""
                isLoading = false
                return
            }

            verificationToken = token

            // Step 2: Login with verification token
            let loginResponse = try await PhoneAuthService.shared.loginWithPhone(
                phoneNumber: fullPhoneNumber,
                verificationToken: token
            )

            // Save auth tokens and update user
            if let user = loginResponse.user {
                authManager.updateCurrentUser(user)
            }

            // Navigate to home
            await MainActor.run {
                currentPage = .home
            }

        } catch let error as PhoneAuthError {
            switch error {
            case .phoneNotRegistered:
                await MainActor.run {
                    showNotRegisteredAlert = true
                }
            case .invalidCode:
                errorMessage = "Invalid verification code"
                otpCode = ""
            case .codeExpired:
                errorMessage = "Code expired. Please request a new one."
                otpCode = ""
            default:
                errorMessage = error.localizedDescription
                otpCode = ""
            }
        } catch {
            errorMessage = error.localizedDescription
            otpCode = ""
        }

        isLoading = false
    }

    private func startResendCountdown() {
        resendCountdown = 60
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if resendCountdown > 0 {
                resendCountdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PhoneLoginView(currentPage: .constant(.phoneLogin))
        .environmentObject(AuthenticationManager.shared)
}
