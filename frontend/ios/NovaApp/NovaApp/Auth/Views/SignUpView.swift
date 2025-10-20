import SwiftUI

/// A02 - Sign Up Screen (template)
struct SignUpView: View {
    let onSignInTap: () -> Void
    @EnvironmentObject var authService: AuthService
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Text("Sign Up View - Template")
            .font(Theme.Typography.h2)
    }
}
