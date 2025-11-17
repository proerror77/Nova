//
//  AccessibleButton.swift
//  NovaSocial
//
//  Created by Nova Team
//  Accessible button component with WCAG 2.1 compliance
//

import SwiftUI

/// Accessible button with proper touch target, contrast, and VoiceOver support
struct AccessibleButton: View {

    // MARK: - Configuration

    let label: String
    let icon: String?
    let action: () -> Void

    var accessibilityLabel: String?
    var accessibilityHint: String?
    var style: ButtonStyle = .primary
    var size: ButtonSize = .medium
    var isLoading: Bool = false
    var isDisabled: Bool = false

    // MARK: - Button Styles

    enum ButtonStyle {
        case primary
        case secondary
        case destructive
        case text

        var backgroundColor: Color {
            switch self {
            case .primary: return .blue
            case .secondary: return Color(.systemGray5)
            case .destructive: return .red
            case .text: return .clear
            }
        }

        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .primary
            case .destructive: return .white
            case .text: return .blue
            }
        }

        var borderColor: Color? {
            switch self {
            case .secondary: return Color(.systemGray3)
            case .text: return nil
            default: return nil
            }
        }
    }

    // MARK: - Button Sizes

    enum ButtonSize {
        case small
        case medium
        case large

        var height: CGFloat {
            switch self {
            case .small: return AccessibilityConstants.minTouchTargetSize
            case .medium: return 50
            case .large: return 56
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 16
            case .large: return 18
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 24
            case .large: return 32
            }
        }
    }

    // MARK: - Body

    var body: some View {
        Button(action: {
            if !isDisabled && !isLoading {
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                action()
            }
        }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: style.foregroundColor))
                        .accessibilityHidden(true)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: size.fontSize))
                        .accessibilityHidden(true)
                }

                Text(label)
                    .font(.system(size: size.fontSize, weight: .semibold))
            }
            .foregroundColor(style.foregroundColor)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(isDisabled ? Color(.systemGray4) : style.backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style.borderColor ?? .clear, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.6 : 1.0)
        }
        .disabled(isDisabled || isLoading)
        // Accessibility
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityHint(accessibilityHint ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityRemoveTraits(isDisabled ? [] : .isButton)
        .accessibilityValue(isLoading ? "Loading" : "")
        .accessibilityIdentifier("button.\(label.lowercased().replacingOccurrences(of: " ", with: "."))")
        // Ensure minimum touch target
        .frame(minHeight: AccessibilityConstants.minTouchTargetSize)
    }
}

// MARK: - Convenience Initializers

extension AccessibleButton {

    init(
        _ label: String,
        icon: String? = nil,
        style: ButtonStyle = .primary,
        size: ButtonSize = .medium,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.action = action
        self.style = style
        self.size = size
    }

    func accessibilityLabel(_ label: String) -> AccessibleButton {
        var button = self
        button.accessibilityLabel = label
        return button
    }

    func accessibilityHint(_ hint: String) -> AccessibleButton {
        var button = self
        button.accessibilityHint = hint
        return button
    }

    func loading(_ isLoading: Bool) -> AccessibleButton {
        var button = self
        button.isLoading = isLoading
        return button
    }

    func disabled(_ isDisabled: Bool) -> AccessibleButton {
        var button = self
        button.isDisabled = isDisabled
        return button
    }
}

// MARK: - Icon Button

struct AccessibleIconButton: View {

    let icon: String
    let action: () -> Void

    var accessibilityLabel: String
    var accessibilityHint: String?
    var size: CGFloat = 24
    var color: Color = .primary

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundColor(color)
                .frame(
                    width: AccessibilityConstants.minTouchTargetSize,
                    height: AccessibilityConstants.minTouchTargetSize
                )
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Preview

#if DEBUG
struct AccessibleButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Primary buttons
            AccessibleButton("Sign In", icon: "person.fill", style: .primary) {
                print("Sign in tapped")
            }

            AccessibleButton("Cancel", style: .secondary) {
                print("Cancel tapped")
            }

            AccessibleButton("Delete", icon: "trash", style: .destructive) {
                print("Delete tapped")
            }

            AccessibleButton("Learn More", style: .text) {
                print("Learn more tapped")
            }

            // Loading state
            AccessibleButton("Processing", style: .primary) {
                print("Processing")
            }
            .loading(true)

            // Disabled state
            AccessibleButton("Disabled", style: .primary) {
                print("Should not fire")
            }
            .disabled(true)

            // Icon button
            AccessibleIconButton(
                icon: "heart.fill",
                action: { print("Like tapped") },
                accessibilityLabel: "Like post",
                color: .red
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
