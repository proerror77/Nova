import SwiftUI

struct SettingsRow: View {
    let icon: String
    let title: String
    var showChevron: Bool = false
    var action: (() -> Void)?

    var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(Typography.regular18)
                    .foregroundColor(DesignTokens.accentColor)
                    .frame(width: 24)

                Text(title)
                    .font(Typography.semibold14)
                    .foregroundColor(DesignTokens.textPrimary)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(Typography.regular12)
                        .foregroundColor(DesignTokens.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

#Preview {
    SettingsRow(icon: "person.circle", title: "Preview", showChevron: true)
}
