import SwiftUI

/// 消息页面
struct MessageView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Text("消息")
                    .font(DesignSystem.Typography.title1)
                    .foregroundColor(DesignSystem.Colors.textDark)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignSystem.Colors.background)
            .navigationTitle("Message")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    MessageView()
}
