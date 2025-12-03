import SwiftUI

struct AuthenticationView: View {
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Logo
            VStack(spacing: 12) {
                Image(systemName: "camera.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)

                Text("Nova Social")
                    .font(.largeTitle)
                    .fontWeight(.bold)
            }
            .padding(.top, 60)
            .padding(.bottom, 40)

            // Tab Selector
            Picker("Auth Type", selection: $selectedTab) {
                Text("Login").tag(0)
                Text("Register").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 20)

            // Content
            TabView(selection: $selectedTab) {
                LoginView()
                    .tag(0)

                RegisterView()
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            Spacer()
        }
    }
}

#Preview {
    AuthenticationView()
}
