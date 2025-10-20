//
//  ContentView.swift
//  NovaDesignDemo
//
//  Main view with theme switcher
//  Copyright © 2025 Nova. All rights reserved.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) var systemColorScheme
    @State private var selectedSkin: BrandSkin = .brandA
    @State private var isDark: Bool = false

    var currentTheme: Theme {
        Theme(skin: selectedSkin, dark: isDark)
    }

    var body: some View {
        NavigationView {
            ZStack {
                currentTheme.colors.bgSurface
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: currentTheme.space.xl) {
                        // Theme Switcher
                        themeSwitcher

                        // Color Palette Section
                        colorPaletteSection

                        // Typography Section
                        typographySection

                        // Spacing Section
                        spacingSection

                        // Component Examples
                        componentExamplesSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Nova Design System")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(isDark ? .dark : .light)
            .environment(\.theme, currentTheme)
        }
    }

    // MARK: - Theme Switcher

    private var themeSwitcher: some View {
        VStack(spacing: currentTheme.space.md) {
            Text("Theme Controls")
                .font(currentTheme.type.titleLG)
                .foregroundColor(currentTheme.colors.fgPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: currentTheme.space.sm) {
                // Brand Selector
                Picker("Brand", selection: $selectedSkin) {
                    ForEach(BrandSkin.allCases) { skin in
                        Text(skin.displayName).tag(skin)
                    }
                }
                .pickerStyle(.segmented)

                // Dark Mode Toggle
                Toggle(isOn: $isDark) {
                    HStack {
                        Image(systemName: isDark ? "moon.fill" : "sun.max.fill")
                        Text(isDark ? "Dark Mode" : "Light Mode")
                    }
                    .font(currentTheme.type.bodyMD)
                    .foregroundColor(currentTheme.colors.fgPrimary)
                }
                .tint(currentTheme.colors.brandPrimary)
            }
            .padding(currentTheme.space.md)
            .background(currentTheme.colors.bgElevated)
            .cornerRadius(currentTheme.radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: currentTheme.radius.md)
                    .stroke(currentTheme.colors.borderSubtle, lineWidth: 1)
            )
        }
    }

    // MARK: - Color Palette Section

    private var colorPaletteSection: some View {
        VStack(alignment: .leading, spacing: currentTheme.space.md) {
            Text("Color Palette")
                .font(currentTheme.type.titleLG)
                .foregroundColor(currentTheme.colors.fgPrimary)

            VStack(spacing: currentTheme.space.sm) {
                colorSwatch(name: "bgSurface", color: currentTheme.colors.bgSurface)
                colorSwatch(name: "bgElevated", color: currentTheme.colors.bgElevated)
                colorSwatch(name: "fgPrimary", color: currentTheme.colors.fgPrimary)
                colorSwatch(name: "fgSecondary", color: currentTheme.colors.fgSecondary)
                colorSwatch(name: "brandPrimary", color: currentTheme.colors.brandPrimary)
                colorSwatch(name: "brandOn", color: currentTheme.colors.brandOn)
                colorSwatch(name: "borderSubtle", color: currentTheme.colors.borderSubtle)
                colorSwatch(name: "borderStrong", color: currentTheme.colors.borderStrong)
                colorSwatch(name: "stateSuccess", color: currentTheme.colors.stateSuccess)
                colorSwatch(name: "stateWarning", color: currentTheme.colors.stateWarning)
                colorSwatch(name: "stateDanger", color: currentTheme.colors.stateDanger)
            }
        }
    }

    private func colorSwatch(name: String, color: Color) -> some View {
        HStack {
            RoundedRectangle(cornerRadius: currentTheme.radius.sm)
                .fill(color)
                .frame(width: 60, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: currentTheme.radius.sm)
                        .stroke(currentTheme.colors.borderSubtle, lineWidth: 1)
                )

            Text(name)
                .font(currentTheme.type.bodyMD)
                .foregroundColor(currentTheme.colors.fgPrimary)

            Spacer()
        }
        .padding(currentTheme.space.sm)
        .background(currentTheme.colors.bgElevated)
        .cornerRadius(currentTheme.radius.sm)
    }

    // MARK: - Typography Section

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: currentTheme.space.md) {
            Text("Typography")
                .font(currentTheme.type.titleLG)
                .foregroundColor(currentTheme.colors.fgPrimary)

            VStack(alignment: .leading, spacing: currentTheme.space.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title Large (22pt / Bold)")
                        .font(currentTheme.type.titleLG)
                        .foregroundColor(currentTheme.colors.fgPrimary)

                    Text("titleLG - Used for page titles and headers")
                        .font(currentTheme.type.labelSM)
                        .foregroundColor(currentTheme.colors.fgSecondary)
                }
                .padding(currentTheme.space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(currentTheme.colors.bgElevated)
                .cornerRadius(currentTheme.radius.sm)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Body Medium (15pt / Regular)")
                        .font(currentTheme.type.bodyMD)
                        .foregroundColor(currentTheme.colors.fgPrimary)

                    Text("bodyMD - Used for body text and paragraphs")
                        .font(currentTheme.type.labelSM)
                        .foregroundColor(currentTheme.colors.fgSecondary)
                }
                .padding(currentTheme.space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(currentTheme.colors.bgElevated)
                .cornerRadius(currentTheme.radius.sm)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Label Small (12pt / Semibold)")
                        .font(currentTheme.type.labelSM)
                        .foregroundColor(currentTheme.colors.fgPrimary)

                    Text("labelSM - Used for labels, captions, and metadata")
                        .font(currentTheme.type.labelSM)
                        .foregroundColor(currentTheme.colors.fgSecondary)
                }
                .padding(currentTheme.space.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(currentTheme.colors.bgElevated)
                .cornerRadius(currentTheme.radius.sm)
            }
        }
    }

    // MARK: - Spacing Section

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: currentTheme.space.md) {
            Text("Spacing Scale")
                .font(currentTheme.type.titleLG)
                .foregroundColor(currentTheme.colors.fgPrimary)

            VStack(spacing: currentTheme.space.sm) {
                spacingBar(name: "xs (4pt)", size: currentTheme.space.xs)
                spacingBar(name: "sm (8pt)", size: currentTheme.space.sm)
                spacingBar(name: "md (12pt)", size: currentTheme.space.md)
                spacingBar(name: "lg (16pt)", size: currentTheme.space.lg)
                spacingBar(name: "xl (24pt)", size: currentTheme.space.xl)
                spacingBar(name: "xxl (32pt)", size: currentTheme.space.xxl)
            }
        }
    }

    private func spacingBar(name: String, size: CGFloat) -> some View {
        HStack(spacing: currentTheme.space.sm) {
            Text(name)
                .font(currentTheme.type.bodyMD)
                .foregroundColor(currentTheme.colors.fgPrimary)
                .frame(width: 100, alignment: .leading)

            RoundedRectangle(cornerRadius: 4)
                .fill(currentTheme.colors.brandPrimary)
                .frame(width: size, height: 20)

            Spacer()
        }
        .padding(currentTheme.space.sm)
        .background(currentTheme.colors.bgElevated)
        .cornerRadius(currentTheme.radius.sm)
    }

    // MARK: - Component Examples Section

    private var componentExamplesSection: some View {
        VStack(alignment: .leading, spacing: currentTheme.space.md) {
            Text("Component Examples")
                .font(currentTheme.type.titleLG)
                .foregroundColor(currentTheme.colors.fgPrimary)

            // PostCard Example
            PostCard(
                author: "Jane Cooper",
                content: "Just shipped a new feature! The design system makes everything so much easier to build. 🚀",
                timestamp: "2h ago",
                imageName: "photo"
            )

            // Button Examples
            buttonExamples

            // State Examples
            stateExamples
        }
    }

    private var buttonExamples: some View {
        VStack(spacing: currentTheme.space.md) {
            Text("Buttons")
                .font(currentTheme.type.bodyMD)
                .foregroundColor(currentTheme.colors.fgPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Primary Button
            Button(action: {}) {
                Text("Primary Button")
                    .font(currentTheme.type.bodyMD)
                    .foregroundColor(currentTheme.colors.brandOn)
                    .frame(maxWidth: .infinity)
                    .padding(currentTheme.space.md)
                    .background(currentTheme.colors.brandPrimary)
                    .cornerRadius(currentTheme.radius.md)
            }

            // Secondary Button
            Button(action: {}) {
                Text("Secondary Button")
                    .font(currentTheme.type.bodyMD)
                    .foregroundColor(currentTheme.colors.fgPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(currentTheme.space.md)
                    .background(currentTheme.colors.bgElevated)
                    .cornerRadius(currentTheme.radius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: currentTheme.radius.md)
                            .stroke(currentTheme.colors.borderStrong, lineWidth: 1)
                    )
            }
        }
        .padding(currentTheme.space.md)
        .background(currentTheme.colors.bgElevated)
        .cornerRadius(currentTheme.radius.md)
    }

    private var stateExamples: some View {
        VStack(spacing: currentTheme.space.md) {
            Text("State Colors")
                .font(currentTheme.type.bodyMD)
                .foregroundColor(currentTheme.colors.fgPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            stateBox(icon: "checkmark.circle.fill", text: "Success", color: currentTheme.colors.stateSuccess)
            stateBox(icon: "exclamationmark.triangle.fill", text: "Warning", color: currentTheme.colors.stateWarning)
            stateBox(icon: "xmark.circle.fill", text: "Danger", color: currentTheme.colors.stateDanger)
        }
        .padding(currentTheme.space.md)
        .background(currentTheme.colors.bgElevated)
        .cornerRadius(currentTheme.radius.md)
    }

    private func stateBox(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: currentTheme.space.sm) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: currentTheme.metric.iconLG))

            Text(text)
                .font(currentTheme.type.bodyMD)
                .foregroundColor(currentTheme.colors.fgPrimary)

            Spacer()
        }
        .padding(currentTheme.space.md)
        .background(color.opacity(0.1))
        .cornerRadius(currentTheme.radius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: currentTheme.radius.sm)
                .stroke(color, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
