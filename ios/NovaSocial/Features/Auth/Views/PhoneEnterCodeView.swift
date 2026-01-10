import SwiftUI

/// Phone Number Enter Code View - (PN) EnterCode
/// Verification code entry screen for phone number registration flow
struct PhoneEnterCodeView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager
    
    /// The full phone number (with country code) for verification
    let phoneNumber: String
    
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
    
    /// Masked phone number for display (e.g., "***8664")
    private var maskedPhoneNumber: String {
        guard phoneNumber.count >= 4 else { return phoneNumber }
        let lastFour = String(phoneNumber.suffix(4))
        return "***\(lastFour)"
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
            // 基准设计: iPhone 13 Mini (375 x 812)
            // 适配: iPhone SE (375 x 667) 到 iPhone 14 Pro Max (430 x 932)
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
                    Button(action: { currentPage = .createAccountPhoneNumber }) {
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
            // NOTE: Avoid GeometryReader here because it can sit on top of the whole screen and
            // intercept taps in the simulator, preventing the OTP field from focusing.
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
            .padding(.bottom, 308.h)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .onAppear {
            startCountdown()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                isInputFocused = true
            }
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
        VStack(spacing: 19.h) {  // 287 - 239 - 29(标题高度) ≈ 19
            Text("Enter your confirmation code")
                .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                .foregroundColor(Color(red: 0.97, green: 0.97, blue: 0.97))

            Text("An SMS was sent to \(maskedPhoneNumber).")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .tracking(0.28)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(red: 0.75, green: 0.75, blue: 0.75))
        }
    }

    private var codeInputSection: some View {
        ZStack {
            // 隐藏的输入框 - 6 位数字验证码
            TextField("", text: $verificationCode)
                .font(Font.custom("SFProDisplay-Light", size: 16.f))
                .foregroundColor(.clear)
                .accentColor(.clear)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .autocorrectionDisabled()
                .focused($isInputFocused)
                .onChange(of: verificationCode) { _, newValue in
                    // 只允许数字，最多 6 位
                    let filtered = newValue.filter { $0.isNumber }
                    verificationCode = String(filtered.prefix(6))
                    
                    // Auto-verify when 6 digits entered
                    if verificationCode.count == 6 {
                        Task { await verifyCode() }
                    }
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)

            // 6 个独立的输入框 - 固定间距
            // Figma 基准: 6个框 × 40pt + 5个间距 × 10pt = 290pt
            // 可用宽度: 375 - 37*2 = 301pt
            HStack(spacing: 10.s) {
                ForEach(0..<6, id: \.self) { index in
                    codeBox(at: index)
                }
            }
            .frame(height: 49.s)
        }
        .onTapGesture {
            Task { @MainActor in
                isInputFocused = false
                await Task.yield()
                isInputFocused = true
            }
        }
    }

    /// 单个验证码输入框 - Figma: 40.14×49, cornerRadius 12, stroke 0.5
    private func codeBox(at index: Int) -> some View {
        let characters = Array(verificationCode)
        let character = index < characters.count ? String(characters[index]) : ""
        let hasCharacter = index < characters.count  // 已输入字符 -> 白色边框

        return ZStack {
            // 显示输入的字符
            Text(character)
                .font(Font.custom("SFProDisplay-Semibold", size: 24.f))
                .foregroundColor(Color(red: 0.97, green: 0.97, blue: 0.97))
        }
        .frame(width: 40.s, height: 49.s)
        .cornerRadius(12.s)
        .overlay(
            RoundedRectangle(cornerRadius: 12.s)
                .stroke(
                    hasCharacter ? Color.white : Color(red: 0.41, green: 0.41, blue: 0.41),
                    lineWidth: 0.5
                )
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

    private var verifyButton: some View {
        Button(action: { Task { await verifyCode() } }) {
            HStack(spacing: 10.s) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.03, green: 0.11, blue: 0.21)))
                        .scaleEffect(0.9)
                }
                Text("Verify")
                    .font(Font.custom("SF Pro Display", size: 16.f).weight(.bold))
                    .foregroundColor(Color(red: 0.03, green: 0.11, blue: 0.21))
            }
            .frame(width: 301.w, height: 48.h)
            .background(Color(red: 1, green: 1, blue: 1))
            .cornerRadius(50.s)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isCodeValid && !isLoading)
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
            let response = try await PhoneAuthService.shared.verifyCode(
                phoneNumber: phoneNumber,
                code: verificationCode
            )
            
            if response.success, let token = response.verificationToken {
                verificationToken = token
                // Store verification token with timestamp for next step
                authManager.setPhoneVerificationToken(token, phoneNumber: phoneNumber)

                // Navigate to invite code page
                await MainActor.run {
                    currentPage = .inviteCode
                }
            } else {
                errorMessage = response.message ?? "Verification failed"
                verificationCode = ""
            }
        } catch let phoneError as PhoneAuthError {
            #if DEBUG
            print("[PNEnterCodeView] Verification error: \(phoneError)")
            #endif
            switch phoneError {
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
                errorMessage = phoneError.localizedDescription
            }
            verificationCode = ""
        } catch {
            #if DEBUG
            print("[PNEnterCodeView] Unexpected error: \(error)")
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
            let response = try await PhoneAuthService.shared.sendVerificationCode(phoneNumber: phoneNumber)
            
            if response.success {
                // Restart countdown
                await MainActor.run {
                    startCountdown()
                }
            } else {
                errorMessage = response.message ?? "Failed to resend code"
            }
        } catch let phoneError as PhoneAuthError {
            #if DEBUG
            print("[PNEnterCodeView] Resend error: \(phoneError)")
            #endif
            switch phoneError {
            case .rateLimited:
                errorMessage = "Too many attempts. Please wait before trying again."
            case .networkError:
                errorMessage = "Unable to connect. Please check your internet connection."
            default:
                errorMessage = phoneError.localizedDescription
            }
        } catch {
            #if DEBUG
            print("[PNEnterCodeView] Unexpected resend error: \(error)")
            #endif
            errorMessage = "Failed to resend code. Please try again."
        }
        
        isLoading = false
    }
}

#Preview {
    PhoneEnterCodeView(
        currentPage: .constant(.phoneEnterCode(phoneNumber: "+14155558664")),
        phoneNumber: "+14155558664"
    )
    .environmentObject(AuthenticationManager.shared)
}
