import SwiftUI

/// 创建页面
struct CreateView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("创建")
                    .font(DesignSystem.Typography.title1)
                    .foregroundColor(DesignSystem.Colors.textDark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.background)
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    CreateView()
}
