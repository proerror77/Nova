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
    @State private var selectedCountry: CountryCodeData?
    @State private var otpCode = ""
    @State private var verificationToken = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var isDetectingRegion = true
    @State private var errorMessage: String?
    @State private var showCountryPicker = false
    @State private var countrySearchText = ""
    @State private var codeExpiresIn: Int = 300  // 5 minutes default

    enum RegistrationStep {
        case phoneInput
        case otpVerification
        case profileSetup
    }

    // MARK: - Services

    private let regionService = RegionDetectionService.shared

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
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(
                selectedCountry: $selectedCountry,
                searchText: $countrySearchText,
                isPresented: $showCountryPicker
            )
        }
        .onAppear {
            detectRegion()
        }
    }

    // MARK: - Region Detection

    private func detectRegion() {
        guard selectedCountry == nil else { return }

        Task {
            let detected = await regionService.detectCountryCode()
            await MainActor.run {
                selectedCountry = detected
                isDetectingRegion = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: handleBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20.f))
                    .foregroundColor(.white)
            }

            Spacer()

            Text(headerTitle)
                .font(Font.custom("SFProDisplay-Semibold", size: 18.f))
                .foregroundColor(.white)

            Spacer()

            // Placeholder for alignment
            Image(systemName: "chevron.left")
                .font(.system(size: 20.f))
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
                .font(.system(size: 50.f))
                .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                .padding(.bottom, 20)

            // Description
            Text("We'll send you a verification code to confirm your phone number")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            // Phone input
            HStack(spacing: 12) {
                // Country code picker with flag
                Button(action: { showCountryPicker = true }) {
                    HStack(spacing: 6) {
                        if isDetectingRegion {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else if let country = selectedCountry {
                            Text(country.flag)
                                .font(.system(size: 20))
                            Text(country.dialCode)
                                .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                                .foregroundColor(.white)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12.f))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                }

                // Phone number field
                TextField("", text: $phoneNumber, prompt: Text("Phone Number").foregroundColor(.gray))
                    .font(Font.custom("SFProDisplay-Regular", size: 16.f))
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
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
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
                        .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(isPhoneValid ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.gray)
                .cornerRadius(25)
            }
            .disabled(!isPhoneValid || isLoading || isDetectingRegion)
            .padding(.top, 20)
        }
    }

    // MARK: - OTP Verification Section

    private var otpVerificationSection: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 50.f))
                .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                .padding(.bottom, 20)

            // Description
            Text("Enter the 6-digit code sent to\n\(fullPhoneNumber)")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
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
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
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
                    .font(Font.custom("SFProDisplay-Medium", size: 14.f))
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
                .font(Font.custom("SFProDisplay-Bold", size: 20.f))
                .foregroundColor(.white)
                .padding(.bottom, 10)

            // Username field
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                    .foregroundColor(.gray)

                TextField("", text: $username, prompt: Text("Choose a username").foregroundColor(.gray))
                    .font(Font.custom("SFProDisplay-Regular", size: 16.f))
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
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                    .foregroundColor(.gray)

                TextField("", text: $displayName, prompt: Text("How should we call you?").foregroundColor(.gray))
                    .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }

            // Password field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                    .foregroundColor(.gray)

                SecureField("", text: $password, prompt: Text("Create a password").foregroundColor(.gray))
                    .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }

            // Confirm password field
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                    .foregroundColor(.gray)

                SecureField("", text: $confirmPassword, prompt: Text("Confirm your password").foregroundColor(.gray))
                    .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
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
                        .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
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
        guard let country = selectedCountry else { return phoneNumber }
        return "\(country.dialCode)\(phoneNumber)"
    }

    private var isPhoneValid: Bool {
        guard let country = selectedCountry else { return false }
        let digits = phoneNumber.filter { $0.isNumber }
        return digits.count >= country.minLength && digits.count <= country.maxLength
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

            // Set flag to show welcome screen for first-time registration
            UserDefaults.standard.set(true, forKey: "shouldShowWelcome")

            // Navigate to welcome (will then go to home after showing)
            await MainActor.run {
                currentPage = .welcome
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
                            .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
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
