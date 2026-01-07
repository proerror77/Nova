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
                Spacer().frame(height: 24.h)
                continueButton
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Back Button - 左上角
            VStack {
                HStack {
                    Button(action: {
                        currentPage = .createAccount
                    }) {
                        Image("back-white")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24.s, height: 24.s)
                    }
                    Spacer()
                }
                .padding(.leading, 20.w)
                .padding(.top, 64.h)
                
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
            .font(Font.custom("SF Pro Display", size: 24.f).weight(.semibold))
            .foregroundColor(.white)
    }

    private var phoneInputSection: some View {
        HStack(spacing: 10) {
            Text("US +1   Mobile number ")
                .font(Font.custom("SF Pro Display", size: 14.f))
                .tracking(0.28)
                .foregroundColor(.white)
            Spacer()
        }
        .padding(16.s)
        .frame(width: 301.w)
        .background(Color(red: 1, green: 1, blue: 1).opacity(0.20))
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
        Button(action: { Task { await sendVerificationCode() } }) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.9)
                }
                Text("Next")
                    .font(Font.custom("SF Pro Display", size: 16.f).weight(.bold))
                    .foregroundColor(.black)
            }
            .frame(width: 301.w, height: 47.h)
            .background(.white)
            .cornerRadius(50.s)
        }
        .disabled(!isPhoneValid || isLoading || isDetectingRegion)
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
        // ⚠️ TODO: 这里需要调用后端 API 发送验证码
        // 如需实现，请告知我后端接口的详细信息
        isLoading = true
        errorMessage = nil

        // 保存用户选择的国家
        if let country = selectedCountry {
            regionService.savePreferredCountry(country)
        }

        // 模拟延迟 - 实际实现需要调用后端
        try? await Task.sleep(for: .milliseconds(500))

        // TODO: 导航到验证码输入页面
        // currentPage = .phoneVerification

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
