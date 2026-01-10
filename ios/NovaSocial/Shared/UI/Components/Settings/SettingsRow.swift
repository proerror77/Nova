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
            HStack(spacing: 10.w) {
                Image(systemName: icon)
                    .font(.system(size: 18.f, weight: .light))
                    .foregroundColor(DesignTokens.accentColor)
                    .frame(width: 24.s, height: 24.s)

                Text(title)
                    .font(Font.custom("SF Pro Display", size: 14.f).weight(.semibold))
                    .tracking(0.28)
                    .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12.f))
                        .foregroundColor(Color(red: 0.41, green: 0.41, blue: 0.41))
                        .frame(width: 24.s, height: 24.s)
                }
            }
        }
    }
}

#Preview {
    SettingsRow(icon: "person.circle", title: "Preview", showChevron: true)
}
