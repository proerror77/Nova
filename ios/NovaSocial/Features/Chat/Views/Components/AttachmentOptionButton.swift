import SwiftUI

/// Button for attachment options in chat
struct AttachmentOptionButton: View {
    let icon: String
    let title: String
    var color: Color = DesignTokens.accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(color)
                }
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.textMuted)
            }
            .frame(width: 70, height: 80)
        }
    }
}
