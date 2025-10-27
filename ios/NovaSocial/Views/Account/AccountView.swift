import SwiftUI

/// 账户页面
struct AccountView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("账户")
                    .font(DesignSystem.Typography.title1)
                    .foregroundColor(DesignSystem.Colors.textDark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.background)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AccountView()
}
