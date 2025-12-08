import SwiftUI

struct WelcomeView: View {
    @Binding var currentPage: AppPage
    @State private var inviteCode: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isInviteCodeValid: Bool {
        inviteCode.count == 8
    }

    var body: some View {
        ZStack {
            // 背景图片
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
                    // Logo
                    Image("Mountain-W")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 80)
                        .offset(x: 0, y: -160)

                    // Title
                    Text("Enter invite code")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: -0.50, y: -89)

                    // Subtitle
                    Text("lf you have an invite code\nEnter it below.")
                        .font(Font.custom("Helvetica Neue", size: 14).weight(.light))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                        .offset(x: -0.50, y: -36)

                    // Invite code input field (styled as pill)
                    ZStack {
                        // Hidden TextField for input
                        TextField("", text: $inviteCode)
                            .font(Font.custom("Helvetica Neue", size: 16).weight(.light))
                            .foregroundColor(.clear)
                            .accentColor(.clear)
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .frame(width: 343, height: 46)
                            .onChange(of: inviteCode) { oldValue, newValue in
                                // Limit to 8 characters
                                if newValue.count > 8 {
                                    inviteCode = String(newValue.prefix(8))
                                }
                                // Convert to uppercase
                                inviteCode = inviteCode.uppercased()
                            }

                        // Display text with cursor indicator
                        HStack(spacing: 0) {
                            Text(inviteCode.isEmpty ? "" : inviteCode)
                                .font(Font.custom("Helvetica Neue", size: 16).weight(.light))
                                .tracking(4)
                                .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                            // Only show cursor when not at max length
                            if inviteCode.count < 8 {
                                Text("—")
                                    .font(Font.custom("Helvetica Neue", size: 16).weight(.light))
                                    .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: 343, height: 46)
                    .background(Color(red: 0.27, green: 0.27, blue: 0.27).opacity(0.45))
                    .cornerRadius(43)
                    .overlay(
                        RoundedRectangle(cornerRadius: 43)
                            .inset(by: 0.20)
                            .stroke(Color(red: 0.53, green: 0.53, blue: 0.53), lineWidth: 0.20)
                    )
                    .offset(x: 0, y: 36)

                    // Done Button
                    Button(action: {
                        Task {
                            await validateInviteCode()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text("Done")
                                .font(Font.custom("Helvetica Neue", size: 16).weight(.medium))
                                .lineSpacing(20)
                                .foregroundColor(.white)
                        }
                        .frame(width: 343, height: 46)
                        .background(isInviteCodeValid ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color(red: 0.87, green: 0.11, blue: 0.26).opacity(0.5))
                        .cornerRadius(43)
                    }
                    .disabled(!isInviteCodeValid || isLoading)
                    .offset(x: 0, y: 106)

                    // Go back - 返回 Login 页面
                    Button(action: {
                        currentPage = .login
                    }) {
                        Text("Go back")
                            .font(Font.custom("Helvetica Neue", size: 14).weight(.medium))
                            .underline()
                            .foregroundColor(Color(red: 0.77, green: 0.77, blue: 0.77))
                    }
                    .offset(x: -0.50, y: 169.50)

                    // Error Message
                    if let errorMessage = errorMessage {
                        Text(LocalizedStringKey(errorMessage))
                            .font(Font.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .offset(x: 0, y: 220)
                    }
                }
                .frame(width: 343, height: 450)
                .offset(y: -40) // 统一调整所有内容的垂直位置（负值向上，正值向下）

                Spacer()
                Spacer()
            }
            .ignoresSafeArea(.keyboard)
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    // MARK: - Validation

    private func validateInviteCode() async {
        guard isInviteCodeValid else { return }

        isLoading = true
        errorMessage = nil

        do {
            // Call backend API to validate invite code
            let client = APIClient.shared
            let endpoint = "\(APIConfig.Invitations.validate)?code=\(inviteCode.uppercased())"

            #if DEBUG
            print("[WelcomeView] Validating invite code: \(inviteCode.uppercased())")
            print("[WelcomeView] API endpoint: \(endpoint)")
            print("[WelcomeView] Base URL: \(APIConfig.current.baseURL)")
            #endif

            // Note: APIClient uses .convertFromSnakeCase, so property names
            // will automatically map from snake_case (is_valid -> isValid)
            struct ValidateResponse: Codable {
                let isValid: Bool
                let issuerUsername: String?
                let expiresAt: Int64?
                let error: String?
            }

            let response: ValidateResponse = try await client.request(
                endpoint: endpoint,
                method: "GET"
            )

            #if DEBUG
            print("[WelcomeView] API response - isValid: \(response.isValid), issuer: \(response.issuerUsername ?? "nil"), error: \(response.error ?? "nil")")
            #endif

            if response.isValid {
                // Valid invite code - navigate to create account
                await MainActor.run {
                    currentPage = .createAccount
                }
            } else {
                // Invalid invite code
                errorMessage = response.error ?? "Invalid_invite_code_generic"
            }
        } catch {
            // Handle network errors
            #if DEBUG
            print("[WelcomeView] Invite code validation error: \(error)")
            print("[WelcomeView] Error details: \(error.localizedDescription)")
            print("[WelcomeView] Error type: \(type(of: error))")
            #endif

                if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                    errorMessage = "Network_error"
                } else {
                    errorMessage = "Invalid_invite_code_generic"
                }
        }

        isLoading = false
    }
}

#Preview {
    WelcomeView(currentPage: .constant(.welcome))
}
