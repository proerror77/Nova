import SwiftUI

// MARK: - Phone Registration View

/// Multi-step phone registration flow
/// Step 1: Enter phone number
/// Step 2: Verify OTP code
/// Step 3: Complete profile (username, password)
struct PhoneRegistrationView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @Binding var currentPage: AppPage

    // MARK: - State
    @State private var currentStep: RegistrationStep = .phoneInput
    @State private var phoneNumber = ""
    @State private var selectedCountryCode = "+1"
    @State private var otpCode = ""
    @State private var verificationToken = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var codeExpiresIn: Int = 300  // 5 minutes default

    enum RegistrationStep {
        case phoneInput
        case otpVerification
        case profileSetup
    }

    // Common country codes
    let countryCodes = [
        ("+1", "US/CA"),
        ("+44", "UK"),
        ("+86", "CN"),
        ("+886", "TW"),
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
                        case .profileSetup:
                            profileSetupSection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                }

                Spacer()
            }
        }
        .navigationBarHidden(true)
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
            return "Enter Phone Number"
        case .otpVerification:
            return "Verify Code"
        case .profileSetup:
            return "Complete Profile"
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
            Text("We'll send you a verification code to confirm your phone number")
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

            // Continue button
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
                        Task { await verifyCode() }
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

            // Resend code button
            Button(action: {
                Task { await sendVerificationCode() }
            }) {
                Text("Resend Code")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
            }
            .disabled(isLoading)
            .padding(.top, 20)
        }
    }

    // MARK: - Profile Setup Section

    private var profileSetupSection: some View {
        VStack(spacing: 20) {
            // Description
            Text("Create your account")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 10)

            // Username field
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)

                TextField("", text: $username, prompt: Text("Choose a username").foregroundColor(.gray))
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }

            // Display name field (optional)
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Name (optional)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)

                TextField("", text: $displayName, prompt: Text("How should we call you?").foregroundColor(.gray))
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }

            // Password field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)

                SecureField("", text: $password, prompt: Text("Create a password").foregroundColor(.gray))
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }

            // Confirm password field
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)

                SecureField("", text: $confirmPassword, prompt: Text("Confirm your password").foregroundColor(.gray))
                    .font(.system(size: 16))
                    .foregroundColor(.white)
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

            // Register button
            Button(action: {
                Task { await completeRegistration() }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text("Create Account")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isProfileValid ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.gray)
                .cornerRadius(25)
            }
            .disabled(!isProfileValid || isLoading)
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

    private var isProfileValid: Bool {
        username.count >= 3 &&
        password.count >= 6 &&
        password == confirmPassword
    }

    // MARK: - Actions

    private func handleBack() {
        switch currentStep {
        case .phoneInput:
            // Navigate back to create account page
            currentPage = .createAccount
        case .otpVerification:
            currentStep = .phoneInput
            otpCode = ""
            errorMessage = nil
        case .profileSetup:
            currentStep = .otpVerification
            errorMessage = nil
        }
    }

    private func sendVerificationCode() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await PhoneAuthService.shared.sendVerificationCode(phoneNumber: fullPhoneNumber)
            if response.success {
                if let expiresIn = response.expiresIn {
                    codeExpiresIn = expiresIn
                }
                await MainActor.run {
                    currentStep = .otpVerification
                }
            } else {
                errorMessage = response.message ?? "Failed to send code"
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func verifyCode() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await PhoneAuthService.shared.verifyCode(
                phoneNumber: fullPhoneNumber,
                code: otpCode
            )
            if response.success, let token = response.verificationToken {
                verificationToken = token
                await MainActor.run {
                    currentStep = .profileSetup
                }
            } else {
                errorMessage = response.message ?? "Verification failed"
                otpCode = ""
            }
        } catch {
            errorMessage = error.localizedDescription
            otpCode = ""
        }

        isLoading = false
    }

    private func completeRegistration() async {
        guard validateProfile() else { return }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await PhoneAuthService.shared.registerWithPhone(
                phoneNumber: fullPhoneNumber,
                verificationToken: verificationToken,
                username: username,
                password: password,
                displayName: displayName.isEmpty ? nil : displayName
            )

            // Save auth tokens
            if let user = response.user {
                authManager.updateCurrentUser(user)
            }

            // Navigate to home
            await MainActor.run {
                currentPage = .home
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func validateProfile() -> Bool {
        if username.count < 3 {
            errorMessage = "Username must be at least 3 characters"
            return false
        }

        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters"
            return false
        }

        if password != confirmPassword {
            errorMessage = "Passwords do not match"
            return false
        }

        return true
    }
}

// MARK: - OTP Input View

struct OTPInputView: View {
    @Binding var code: String
    let codeLength: Int

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Hidden text field for input
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0)
                .onChange(of: code) { _, newValue in
                    // Limit to codeLength digits
                    if newValue.count > codeLength {
                        code = String(newValue.prefix(codeLength))
                    }
                    // Only allow digits
                    code = code.filter { $0.isNumber }
                }

            // Display boxes
            HStack(spacing: 10) {
                ForEach(0..<codeLength, id: \.self) { index in
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(boxBorderColor(at: index), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .frame(width: 45, height: 55)

                        Text(digit(at: index))
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
            }
            .onTapGesture {
                isFocused = true
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    private func digit(at index: Int) -> String {
        guard index < code.count else { return "" }
        let stringIndex = code.index(code.startIndex, offsetBy: index)
        return String(code[stringIndex])
    }

    private func boxBorderColor(at index: Int) -> Color {
        if index < code.count {
            return Color(red: 0.87, green: 0.11, blue: 0.26)
        } else if index == code.count && isFocused {
            return .white
        } else {
            return .gray.opacity(0.5)
        }
    }
}

// MARK: - Preview

#Preview {
    PhoneRegistrationView(currentPage: .constant(.createAccount))
        .environmentObject(AuthenticationManager.shared)
}
