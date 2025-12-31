import SwiftUI

struct SplashScreenView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var isActive = false

    var body: some View {
        ZStack {
            // 背景色
            DesignTokens.accentColor
                .ignoresSafeArea()

            // ICERED 图标
            Image("ICERED-icon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 220, height: 220)
                .foregroundColor(.white)
        }
        .task {
            await validateAndNavigate()
        }
    }
    
    /// Validate session and navigate to appropriate page
    private func validateAndNavigate() async {
        print("╔════════════════════════════════════════════════════════════")
        print("║ [Splash] 🚀 APP LAUNCH - Starting session validation")
        print("╚════════════════════════════════════════════════════════════")
        
        // Minimum splash display time
        let splashStartTime = Date()
        let minimumSplashDuration: TimeInterval = 1.5
        
        // Check if user has saved auth credentials
        if authManager.isAuthenticated {
            print("[Splash] 📱 User appears authenticated, validating session...")
            
            // Proactively validate the session
            let isValid = await authManager.validateSession()
            
            // Ensure minimum splash duration
            let elapsed = Date().timeIntervalSince(splashStartTime)
            if elapsed < minimumSplashDuration {
                try? await Task.sleep(for: .seconds(minimumSplashDuration - elapsed))
            }
            
            if isValid && authManager.isAuthenticated {
                // Check if this is first-time registration (should show welcome)
                if UserDefaults.standard.bool(forKey: "shouldShowWelcome") {
                    print("[Splash] ✅ Session valid, first-time user, navigating to welcome")
                    currentPage = .welcome
                } else {
                    print("[Splash] ✅ Session valid, returning user, navigating to home")
                    currentPage = .home
                }
            } else {
                print("[Splash] ❌ Session invalid, navigating to login")
                currentPage = .login
            }
        } else {
            print("[Splash] ℹ️ Not authenticated, navigating to login")
            
            // Ensure minimum splash duration
            let elapsed = Date().timeIntervalSince(splashStartTime)
            if elapsed < minimumSplashDuration {
                try? await Task.sleep(for: .seconds(minimumSplashDuration - elapsed))
            }
            
            currentPage = .login
        }
        
        print("[Splash] 🏁 Navigation complete -> \(currentPage)")
    }
}

// MARK: - Previews

#Preview("Splash - Default") {
    SplashScreenView(currentPage: .constant(.splash))
        .environmentObject(AuthenticationManager.shared)
}

#Preview("Splash - Dark Mode") {
    SplashScreenView(currentPage: .constant(.splash))
        .environmentObject(AuthenticationManager.shared)
        .preferredColorScheme(.dark)
}
