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
                    Group {
                        // Invite Code Modal Background
                        Rectangle()
                            .foregroundColor(.clear)
                            .frame(width: 343, height: 343)
                            .background(Color(red: 0.16, green: 0.16, blue: 0.16))
                            .cornerRadius(30)
                            .offset(x: 0, y: -90)
                            .shadow(
                                color: Color(red: 0, green: 0, blue: 0, opacity: 0.25), radius: 4, y: 4
                            )

                        Text("Icered is invite only")
                            .font(Font.custom("Inter", size: 24).weight(.bold))
                            .lineSpacing(45.29)
                            .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                            .offset(x: 1, y: -143.50)

                        Text("lf you have an invite code, enter it below.")
                            .font(Font.custom("Helvetica Neue", size: 14).weight(.light))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            .offset(x: 0.50, y: -120)

                        // Invite code input field
                        ZStack {
                            Rectangle()
                                .foregroundColor(.clear)
                                .frame(width: 261, height: 39)
                                .background(Color(red: 0.25, green: 0.25, blue: 0.25).opacity(0.51))
                                .cornerRadius(6)

                            TextField("", text: $inviteCode)
                                .font(Font.custom("Helvetica Neue", size: 16))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .frame(width: 241)
                                .onChange(of: inviteCode) { oldValue, newValue in
                                    // Limit to 8 characters
                                    if newValue.count > 8 {
                                        inviteCode = String(newValue.prefix(8))
                                    }
                                    // Convert to uppercase
                                    inviteCode = inviteCode.uppercased()
                                }
                        }
                        .offset(x: 0, y: -65)

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
                            .frame(width: 101, height: 46)
                            .background(isInviteCodeValid ? Color(red: 0.87, green: 0.11, blue: 0.26) : Color.gray.opacity(0.5))
                            .cornerRadius(64)
                        }
                        .disabled(!isInviteCodeValid || isLoading)
                        .offset(x: 0, y: -2.50)

                        HStack(spacing: 0) {
                            Text("Notify me when access opens")
                                .font(Font.custom("Helvetica Neue", size: 14).weight(.light))
                                .lineSpacing(20)
                                .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                        }
                        .offset(x: 0.50, y: 50.50)

                        // Error Message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(Font.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                                .offset(x: 0, y: 30)
                        }
                    }
                }
                .frame(width: 375, height: 812)

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
                // Valid invite code - navigate to login
                await MainActor.run {
                    currentPage = .login
                }
            } else {
                // Invalid invite code
                errorMessage = response.error ?? "Invalid invite code. Please try again."
            }
        } catch {
            // Handle network errors
            #if DEBUG
            print("[WelcomeView] Invite code validation error: \(error)")
            print("[WelcomeView] Error details: \(error.localizedDescription)")
            print("[WelcomeView] Error type: \(type(of: error))")
            #endif

            if error.localizedDescription.contains("network") || error.localizedDescription.contains("connection") {
                errorMessage = "Network error. Please check your connection."
            } else {
                errorMessage = "Invalid invite code. Please try again."
            }
        }

        isLoading = false
    }
}

#Preview {
    WelcomeView(currentPage: .constant(.welcome))
}
