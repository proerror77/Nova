import SwiftUI

/// Theme switcher control for settings
struct ThemeSwitcher: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Appearance")
                .font(Theme.Typography.h6)
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.md) {
                ThemeOption(
                    title: "Light",
                    icon: "sun.max.fill",
                    isSelected: appState.colorScheme == .light,
                    onTap: {
                        appState.setColorScheme(.light)
                    }
                )

                ThemeOption(
                    title: "Dark",
                    icon: "moon.fill",
                    isSelected: appState.colorScheme == .dark,
                    onTap: {
                        appState.setColorScheme(.dark)
                    }
                )

                ThemeOption(
                    title: "Auto",
                    icon: "circle.lefthalf.filled",
                    isSelected: appState.colorScheme == nil,
                    onTap: {
                        appState.setColorScheme(nil)
                    }
                )
            }
        }
    }
}

struct ThemeOption: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            withAnimation(.quickSpring) {
                onTap()
            }
        }) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: Theme.IconSize.lg))
                    .foregroundColor(isSelected ? Theme.Colors.onPrimary : Theme.Colors.textPrimary)

                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(isSelected ? Theme.Colors.onPrimary : Theme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                isSelected ? Theme.Colors.primary : Theme.Colors.surface
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .stroke(
                        isSelected ? Theme.Colors.primary : Theme.Colors.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .cornerRadius(Theme.CornerRadius.md)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ThemeSwitcher()
        .environmentObject(AppState.shared)
        .padding()
}
