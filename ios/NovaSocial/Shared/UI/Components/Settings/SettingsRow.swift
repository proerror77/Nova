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
                    .font(Font.custom("SFProDisplay-Regular", size: 18.f))
                    .foregroundColor(DesignTokens.accentColor)
                    .frame(width: 24)

                Text(title)
                    .font(Font.custom("SFProDisplay-Medium", size: 14.f))
                    .foregroundColor(DesignTokens.textPrimary)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(Font.custom("SFProDisplay-Regular", size: 12.f))
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
