//
//  ThemeShowcaseView.swift
//  NovaDesignDemo
//
//  Display all 8 theme combinations in a grid
//  Copyright © 2025 Nova. All rights reserved.
//

import SwiftUI

struct ThemeShowcaseView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(Theme.allCombinations, id: \.themeId) { theme in
                        ThemePreviewCard(theme: theme)
                    }
                }
                .padding()
            }
            .navigationTitle("All Themes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Theme Preview Card

struct ThemePreviewCard: View {
    let theme: Theme

    var body: some View {
        VStack(spacing: theme.space.sm) {
            // Header
            Text("\(theme.skin.displayName)")
                .font(theme.type.labelSM)
                .foregroundColor(theme.colors.fgPrimary)

            Text(theme.dark ? "Dark" : "Light")
                .font(theme.type.labelSM)
                .foregroundColor(theme.colors.fgSecondary)

            // Color Swatches
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    colorSquare(theme.colors.brandPrimary)
                    colorSquare(theme.colors.bgSurface)
                    colorSquare(theme.colors.fgPrimary)
                }

                HStack(spacing: 4) {
                    colorSquare(theme.colors.stateSuccess)
                    colorSquare(theme.colors.stateWarning)
                    colorSquare(theme.colors.stateDanger)
                }
            }

            // Mini PostCard
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(theme.colors.brandPrimary)
                        .frame(width: 16, height: 16)

                    Text("Sample Post")
                        .font(.system(size: 8))
                        .foregroundColor(theme.colors.fgPrimary)
                }

                Text("Demo content showing the theme")
                    .font(.system(size: 7))
                    .foregroundColor(theme.colors.fgSecondary)
                    .lineLimit(2)
            }
            .padding(6)
            .background(theme.colors.bgSurface)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.colors.borderSubtle, lineWidth: 0.5)
            )
        }
        .padding(theme.space.md)
        .background(theme.colors.bgElevated)
        .cornerRadius(theme.radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.md)
                .stroke(theme.colors.borderStrong, lineWidth: 1)
        )
        .preferredColorScheme(theme.dark ? .dark : .light)
    }

    private func colorSquare(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 20, height: 20)
    }
}

// MARK: - Preview

#if DEBUG
struct ThemeShowcaseView_Previews: PreviewProvider {
    static var previews: some View {
        ThemeShowcaseView()
    }
}
#endif
