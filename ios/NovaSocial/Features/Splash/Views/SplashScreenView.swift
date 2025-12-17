import SwiftUI

struct SplashScreenView: View {
    @Binding var currentPage: AppPage
    @EnvironmentObject private var authManager: AuthenticationManager
    @State private var isActive = false
    @State private var statusMessage = "Loading..."

    var body: some View {
        ZStack {
            // 背景色
            DesignTokens.accentColor
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Icered 图标
                Image("Icered-icon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .foregroundColor(.white)
                
                #if DEBUG
                // Debug status message (only in debug builds)
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                #endif
            }
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
            statusMessage = "Validating session..."
            print("[Splash] 📱 User appears authenticated, validating session...")
            
            // Proactively validate the session
            let isValid = await authManager.validateSession()
            
            // Ensure minimum splash duration
            let elapsed = Date().timeIntervalSince(splashStartTime)
            if elapsed < minimumSplashDuration {
                try? await Task.sleep(for: .seconds(minimumSplashDuration - elapsed))
            }
            
            if isValid && authManager.isAuthenticated {
                print("[Splash] ✅ Session valid, navigating to home")
                statusMessage = "Welcome back!"
                currentPage = .home
            } else {
                print("[Splash] ❌ Session invalid, navigating to login")
                statusMessage = "Session expired"
                // Small delay to show the message
                try? await Task.sleep(for: .seconds(0.3))
                currentPage = .login
            }
        } else {
            print("[Splash] ℹ️ Not authenticated, navigating to login")
            statusMessage = "Please login"
            
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
