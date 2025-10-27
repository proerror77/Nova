import SwiftUI

/// Alice 页面（AI 助手或特殊功能）
struct AliceView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("Alice")
                    .font(DesignSystem.Typography.title1)
                    .foregroundColor(DesignSystem.Colors.textDark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.background)
            .navigationTitle("Alice")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    AliceView()
}
