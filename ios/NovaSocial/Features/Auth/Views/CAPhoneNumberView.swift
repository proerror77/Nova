import SwiftUI

/// CreateAccount/PhoneNumber - 创建账号流程中的手机号输入页面
struct CAPhoneNumberView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager

    // MARK: - State
    @State private var phoneNumber = ""
    @State private var selectedCountry: CountryCodeData?
    @State private var isLoading = false
    @State private var isDetectingRegion = true
    @State private var errorMessage: String?
    @State private var showCountryPicker = false
    @State private var countrySearchText = ""
    @FocusState private var isInputFocused: Bool

    // MARK: - Services
    private let regionService = RegionDetectionService.shared

    // MARK: - Computed Properties

    private var phoneDigits: String {
        phoneNumber.filter { $0.isNumber }
    }

    private var fullPhoneNumber: String {
        guard let country = selectedCountry else { return phoneDigits }
        return "\(country.dialCode)\(phoneDigits)"
    }

    private var isPhoneValid: Bool {
        guard let country = selectedCountry else { return false }
        return phoneDigits.count >= country.minLength && phoneDigits.count <= country.maxLength
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background - Linear Gradient (same as InviteCodeView)
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
                Spacer().frame(height: 114.h)
                logoSection
                Spacer().frame(height: 43.h)
                titleSection
                Spacer().frame(height: 55.h)
                phoneInputSection
                errorMessageView
                Spacer().frame(height: 24.h)
                continueButton
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Back Button Header - Figma: 距顶部44pt, padding 8pt, 高度64pt
            VStack(spacing: 0) {
                Spacer().frame(height: 44.h)  // 状态栏高度
                HStack(spacing: 8.s) {
                    Button(action: { currentPage = .createAccount }) {
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
        }
        .contentShape(Rectangle())
        .onTapGesture { isInputFocused = false }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
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
        Text("Enter your mobile number")
            .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
            .foregroundColor(.white)
    }

    private var phoneInputSection: some View {
        HStack(spacing: 12.s) {
            // Country code picker with flag
            Button(action: { showCountryPicker = true }) {
                HStack(spacing: 6.s) {
                    if isDetectingRegion {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else if let country = selectedCountry {
                        Text(country.flag)
                            .font(.system(size: 20.f))
                        Text(country.dialCode)
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(.white)
                    } else {
                        Text("🌍")
                            .font(.system(size: 20.f))
                        Text("+1")
                            .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                            .foregroundColor(.white)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10.f))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.vertical, 14.s)
            }

            // Phone number TextField
            TextField("", text: $phoneNumber, prompt: Text("Mobile number").foregroundColor(.white.opacity(0.5)))
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(.white)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .autocorrectionDisabled()
                .focused($isInputFocused)
                .onChange(of: phoneNumber) { _, newValue in
                    applyPhoneFormatting(newValue)
                }
                .onChange(of: selectedCountry) { _, _ in
                    applyPhoneFormatting(phoneNumber)
                }
        }
        .padding(.leading, 16.s)
        .padding(.trailing, 16.s)
        .frame(width: 301.w, height: 52.h)
        .background(Color.white.opacity(0.20))
        .cornerRadius(5.s)
        .overlay(
            RoundedRectangle(cornerRadius: 5.s)
                .stroke(.white, lineWidth: 0.50)
        )
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

    private var continueButton: some View {
        VStack(spacing: 8.h) {
            Button(action: { Task { await sendVerificationCode() } }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.9)
                    }
                    Text("Next")
                        .font(Font.custom("SFProDisplay-Bold", size: 16.f))
                        .foregroundColor(.black)
                }
                .frame(width: 301.w, height: 47.h)
                .background(.white)
                .cornerRadius(50.s)
            }
            .disabled(!isPhoneValid || isLoading || isDetectingRegion)

            // Loading hint when detecting region
            if isDetectingRegion {
                HStack(spacing: 6.s) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.6)
                    Text("Detecting your region...")
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.top, 4.h)
            }
        }
    }

    // MARK: - Actions

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

    private func sendVerificationCode() async {
        guard isPhoneValid else { return }

        isLoading = true
        errorMessage = nil

        // Save user's selected country
        if let country = selectedCountry {
            regionService.savePreferredCountry(country)
        }

        do {
            let response = try await PhoneAuthService.shared.sendVerificationCode(phoneNumber: fullPhoneNumber)

            if response.success {
                // Navigate to verification code entry page
                await MainActor.run {
                    currentPage = .phoneEnterCode(phoneNumber: fullPhoneNumber)
                }
            } else {
                errorMessage = response.message ?? "Failed to send verification code"
            }
        } catch let phoneError as PhoneAuthError {
            #if DEBUG
            print("[CAPhoneNumberView] Send code error: \(phoneError)")
            #endif
            switch phoneError {
            case .rateLimited:
                errorMessage = "Too many attempts. Please wait before trying again."
            case .invalidPhoneNumber:
                errorMessage = "Invalid phone number. Please check and try again."
            case .networkError:
                errorMessage = "Unable to connect. Please check your internet connection."
            case .serverError(let message):
                errorMessage = message
            default:
                errorMessage = phoneError.localizedDescription
            }
        } catch {
            #if DEBUG
            print("[CAPhoneNumberView] Unexpected error: \(error)")
            #endif
            errorMessage = "An unexpected error occurred. Please try again."
        }

        isLoading = false
    }

    // MARK: - Phone Formatting

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

// MARK: - Preview

#Preview {
    CAPhoneNumberView(currentPage: .constant(.createAccount))
        .environmentObject(AuthenticationManager.shared)
}
