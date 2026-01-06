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
    @State private var selectedCountry: CountryCodeData?
    @State private var otpCode = ""
    @State private var verificationToken = ""
    @State private var isLoading = false
    @State private var isDetectingRegion = true
    @State private var errorMessage: String?
    @State private var showNotRegisteredAlert = false
    @State private var showCountryPicker = false
    @State private var resendCountdown: Int = 0
    @State private var resendTimer: Timer?
    @State private var countrySearchText = ""

    enum LoginStep {
        case phoneInput
        case otpVerification
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
        .onDisappear {
            resendTimer?.invalidate()
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
                .font(.system(size: 50.f))
                .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                .padding(.bottom, 20)

            // Description
            Text("Enter your phone number to receive a verification code")
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
                    .textContentType(.telephoneNumber)
                    .autocorrectionDisabled()
                    .onChange(of: phoneNumber) { _, newValue in
                        applyPhoneFormatting(newValue)
                    }
                    .onChange(of: selectedCountry) { _, _ in
                        applyPhoneFormatting(phoneNumber)
                    }
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

            // Register link
            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                    .foregroundColor(.gray)

                Button(action: {
                    currentPage = .phoneRegistration
                }) {
                    Text("Register")
                        .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
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
                .font(.system(size: 50.f))
                .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                .padding(.bottom, 20)

            // Description
            Text("Enter the 6-digit code sent to\n\(displayPhoneNumber)")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
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
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
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
                        .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
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
                        .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                        .foregroundColor(.gray)
                } else {
                    Text("Resend Code")
                        .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                }
            }
            .disabled(isLoading || resendCountdown > 0)
            .padding(.top, 10)
        }
    }

    // MARK: - Computed Properties

    private var fullPhoneNumber: String {
        guard let country = selectedCountry else { return phoneDigits }
        return "\(country.dialCode)\(phoneDigits)"
    }

    private var isPhoneValid: Bool {
        guard let country = selectedCountry else { return false }
        return phoneDigits.count >= country.minLength && phoneDigits.count <= country.maxLength
    }

    private var phoneDigits: String {
        phoneNumber.filter { $0.isNumber }
    }

    private var displayPhoneNumber: String {
        guard let country = selectedCountry else { return phoneNumber }
        let formatted = formatPhoneDigits(phoneDigits)
        if formatted.isEmpty {
            return country.dialCode
        }
        return "\(country.dialCode) \(formatted)"
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

        if let country = selectedCountry {
            regionService.savePreferredCountry(country)
        }

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

    private func applyPhoneFormatting(_ newValue: String) {
        let digits = limitPhoneDigits(newValue.filter { $0.isNumber })
        let formatted = formatPhoneDigits(digits)
        if formatted != newValue {
            phoneNumber = formatted
        }
    }

    private func limitPhoneDigits(_ digits: String) -> String {
        guard let country = selectedCountry else { return digits }
        return String(digits.prefix(country.maxLength))
    }

    private func formatPhoneDigits(_ digits: String) -> String {
        guard let format = selectedCountry?.phoneFormat, !format.isEmpty else {
            return digits
        }

        var result = ""
        var index = digits.startIndex

        for token in format {
            if index == digits.endIndex { break }
            if token == "X" {
                result.append(digits[index])
                index = digits.index(after: index)
            } else {
                result.append(token)
            }
        }

        return result
    }
}

// MARK: - Country Picker Sheet

struct CountryPickerSheet: View {
    @Binding var selectedCountry: CountryCodeData?
    @Binding var searchText: String
    @Binding var isPresented: Bool

    private let regionService = RegionDetectionService.shared

    var filteredCountries: [CountryCodeData] {
        regionService.searchCountries(searchText)
    }

    var priorityCountries: [CountryCodeData] {
        regionService.getPriorityCountries()
    }
    
    var recentCountries: [CountryCodeData] {
        regionService.getRecentCountries()
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search country or code", text: $searchText)
                            .foregroundColor(.white)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Country list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Priority sections (when not searching)
                            if searchText.isEmpty {
                                if !recentCountries.isEmpty {
                                    Section {
                                        ForEach(recentCountries) { country in
                                            countryRow(country)
                                        }
                                    } header: {
                                        sectionHeader("Recent")
                                    }
                                }

                                Section {
                                    let filteredPriority = priorityCountries.filter { !recentCountries.contains($0) }
                                    ForEach(filteredPriority) { country in
                                        countryRow(country)
                                    }
                                } header: {
                                    sectionHeader("Popular")
                                }

                                Section {
                                    let excluded = Set(recentCountries + priorityCountries)
                                    ForEach(filteredCountries.filter { !excluded.contains($0) }) { country in
                                        countryRow(country)
                                    }
                                } header: {
                                    sectionHeader("All Countries")
                                }
                            } else {
                                ForEach(filteredCountries) { country in
                                    countryRow(country)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.top, 8)
    }

    private func countryRow(_ country: CountryCodeData) -> some View {
        Button(action: {
            selectedCountry = country
            searchText = ""
            regionService.savePreferredCountry(country)
            isPresented = false
        }) {
            HStack(spacing: 12) {
                Text(country.flag)
                    .font(.system(size: 24))

                VStack(alignment: .leading, spacing: 2) {
                    Text(country.name)
                        .font(Font.custom("SFProDisplay-Regular", size: 16.f))
                        .foregroundColor(.white)
                    Text(country.localizedName)
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(.gray)
                }

                Spacer()

                Text(country.dialCode)
                    .font(Font.custom("SFProDisplay-Medium", size: 16.f))
                    .foregroundColor(.gray)

                if selectedCountry?.id == country.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Divider()
            .background(Color.white.opacity(0.1))
    }
}

// MARK: - Preview

#Preview {
    PhoneLoginView(currentPage: .constant(.phoneLogin))
        .environmentObject(AuthenticationManager.shared)
}
