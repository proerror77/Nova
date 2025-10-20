//
//  AccessibilityHelpers.swift
//  NovaSocial
//
//  Created by Nova Team
//  Accessibility utilities and protocols for WCAG 2.1 compliance
//

import SwiftUI
import UIKit

// MARK: - Accessibility Protocols

/// Protocol for views that provide custom accessibility support
protocol AccessibilityDescribable {
    var accessibilityLabel: String { get }
    var accessibilityHint: String? { get }
    var accessibilityValue: String? { get }
    var accessibilityTraits: AccessibilityTraits { get }
}

/// Protocol for views that support custom accessibility actions
protocol AccessibilityActionable {
    var customAccessibilityActions: [AccessibilityAction] { get }
}

// MARK: - Accessibility Constants

enum AccessibilityConstants {
    /// Minimum touch target size (WCAG 2.5.5 - Target Size)
    static let minTouchTargetSize: CGFloat = 44

    /// Minimum spacing between interactive elements
    static let minInterElementSpacing: CGFloat = 8

    /// Minimum contrast ratios (WCAG 1.4.3)
    enum ContrastRatio {
        static let normalText: Double = 4.5  // For text < 18pt
        static let largeText: Double = 3.0   // For text >= 18pt or bold >= 14pt
        static let uiComponents: Double = 3.0 // For UI components
    }

    /// Typography minimums (WCAG 1.4.8)
    enum Typography {
        static let minFontSize: CGFloat = 16
        static let minLineHeight: CGFloat = 1.5
        static let minLetterSpacing: CGFloat = 0.12
        static let minParagraphSpacing: CGFloat = 2.0
    }

    /// Animation safety (WCAG 2.3.1)
    static let maxFlashFrequency: Double = 3.0 // Hz
}

// MARK: - Accessibility Helpers

struct AccessibilityHelper {

    // MARK: - VoiceOver Detection

    /// Check if VoiceOver is currently running
    static var isVoiceOverRunning: Bool {
        UIAccessibility.isVoiceOverRunning
    }

    /// Observe VoiceOver status changes
    static func observeVoiceOverStatus(onChange: @escaping (Bool) -> Void) -> NotificationToken {
        let token = NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            onChange(UIAccessibility.isVoiceOverRunning)
        }
        return NotificationToken(token: token)
    }

    // MARK: - Dynamic Type

    /// Check if user prefers larger text sizes
    static var preferredContentSizeCategory: UIContentSizeCategory {
        UIApplication.shared.preferredContentSizeCategory
    }

    /// Check if accessibility text sizes are enabled
    static var isAccessibilityCategory: Bool {
        UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
    }

    /// Observe Dynamic Type changes
    static func observeDynamicType(onChange: @escaping (UIContentSizeCategory) -> Void) -> NotificationToken {
        let token = NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            onChange(UIApplication.shared.preferredContentSizeCategory)
        }
        return NotificationToken(token: token)
    }

    // MARK: - Motion Preferences

    /// Check if user prefers reduced motion (WCAG 2.3.3)
    static var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// Observe Reduce Motion preference changes
    static func observeReduceMotion(onChange: @escaping (Bool) -> Void) -> NotificationToken {
        let token = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            onChange(UIAccessibility.isReduceMotionEnabled)
        }
        return NotificationToken(token: token)
    }

    // MARK: - Transparency Preferences

    /// Check if user prefers reduced transparency
    static var isReduceTransparencyEnabled: Bool {
        UIAccessibility.isReduceTransparencyEnabled
    }

    // MARK: - Contrast Preferences

    /// Check if user prefers increased contrast
    static var isDarkerSystemColorsEnabled: Bool {
        UIAccessibility.isDarkerSystemColorsEnabled
    }

    // MARK: - Touch Target Validation

    /// Validate if a touch target meets minimum size requirements
    static func validateTouchTarget(size: CGSize) -> Bool {
        size.width >= AccessibilityConstants.minTouchTargetSize &&
        size.height >= AccessibilityConstants.minTouchTargetSize
    }

    /// Get recommended padding to meet minimum touch target size
    static func recommendedPadding(for size: CGSize) -> EdgeInsets {
        let horizontalPadding = max(0, (AccessibilityConstants.minTouchTargetSize - size.width) / 2)
        let verticalPadding = max(0, (AccessibilityConstants.minTouchTargetSize - size.height) / 2)

        return EdgeInsets(
            top: verticalPadding,
            leading: horizontalPadding,
            bottom: verticalPadding,
            trailing: horizontalPadding
        )
    }

    // MARK: - Contrast Calculation

    /// Calculate relative luminance (WCAG formula)
    static func relativeLuminance(of color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0

        color.getRed(&red, green: &green, blue: &blue, alpha: nil)

        let r = red <= 0.03928 ? red / 12.92 : pow((red + 0.055) / 1.055, 2.4)
        let g = green <= 0.03928 ? green / 12.92 : pow((green + 0.055) / 1.055, 2.4)
        let b = blue <= 0.03928 ? blue / 12.92 : pow((blue + 0.055) / 1.055, 2.4)

        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// Calculate contrast ratio between two colors (WCAG 1.4.3)
    static func contrastRatio(foreground: UIColor, background: UIColor) -> Double {
        let l1 = relativeLuminance(of: foreground)
        let l2 = relativeLuminance(of: background)

        let lighter = max(l1, l2)
        let darker = min(l1, l2)

        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Check if contrast ratio meets WCAG AA standard
    static func meetsContrastRequirement(
        foreground: UIColor,
        background: UIColor,
        fontSize: CGFloat,
        isBold: Bool = false
    ) -> Bool {
        let ratio = contrastRatio(foreground: foreground, background: background)

        // Large text: >= 18pt or bold >= 14pt
        let isLargeText = fontSize >= 18 || (isBold && fontSize >= 14)
        let requiredRatio = isLargeText
            ? AccessibilityConstants.ContrastRatio.largeText
            : AccessibilityConstants.ContrastRatio.normalText

        return ratio >= requiredRatio
    }

    // MARK: - Accessibility Announcements

    /// Post an accessibility announcement for screen readers
    static func announce(_ message: String, priority: UIAccessibility.Notification = .announcement) {
        UIAccessibility.post(notification: priority, argument: message)
    }

    /// Announce a layout change
    static func announceLayoutChange(focusElement: Any? = nil) {
        UIAccessibility.post(notification: .layoutChanged, argument: focusElement)
    }

    /// Announce a screen change
    static func announceScreenChange(focusElement: Any? = nil) {
        UIAccessibility.post(notification: .screenChanged, argument: focusElement)
    }
}

// MARK: - Notification Token

/// Token for managing notification observers
class NotificationToken {
    private let token: NSObjectProtocol

    init(token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

// MARK: - SwiftUI View Extensions

extension View {

    // MARK: - Accessible Touch Target

    /// Ensure view meets minimum touch target size
    func accessibleTouchTarget() -> some View {
        self.frame(
            minWidth: AccessibilityConstants.minTouchTargetSize,
            minHeight: AccessibilityConstants.minTouchTargetSize
        )
    }

    /// Add padding to meet minimum touch target size
    func accessiblePadding(for size: CGSize) -> some View {
        let padding = AccessibilityHelper.recommendedPadding(for: size)
        return self.padding(EdgeInsets(
            top: padding.top,
            leading: padding.leading,
            bottom: padding.bottom,
            trailing: padding.trailing
        ))
    }

    // MARK: - Conditional Animations

    /// Apply animation only if user hasn't enabled reduce motion
    func accessibleAnimation<V: Equatable>(
        _ animation: Animation?,
        value: V
    ) -> some View {
        self.animation(
            AccessibilityHelper.isReduceMotionEnabled ? nil : animation,
            value: value
        )
    }

    /// Apply transition only if user hasn't enabled reduce motion
    func accessibleTransition(_ transition: AnyTransition) -> some View {
        self.transition(
            AccessibilityHelper.isReduceMotionEnabled ? .identity : transition
        )
    }

    // MARK: - Semantic Grouping

    /// Group related elements for accessibility
    func accessibilityGroup() -> some View {
        self.accessibilityElement(children: .combine)
    }

    /// Mark as decorative element (hidden from VoiceOver)
    func accessibilityDecorative() -> some View {
        self.accessibilityHidden(true)
    }

    // MARK: - Custom Actions

    /// Add accessibility actions for complex interactions
    func accessibilityActions(_ actions: [AccessibilityAction]) -> some View {
        var view = self
        for action in actions {
            view = view.accessibilityAction(named: action.name) {
                action.handler()
            } as! Self
        }
        return view
    }
}

// MARK: - Accessibility Action

struct AccessibilityAction {
    let name: String
    let handler: () -> Void
}

// MARK: - Keyboard Navigation Support

#if os(iOS)
extension UIResponder {

    /// Setup keyboard commands for accessibility
    static func setupAccessibilityKeyCommands() -> [UIKeyCommand] {
        return [
            // Navigation
            UIKeyCommand(
                title: "Next Element",
                action: #selector(nextAccessibilityElement),
                input: "\t",
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Previous Element",
                action: #selector(previousAccessibilityElement),
                input: "\t",
                modifierFlags: .shift
            ),
            // Actions
            UIKeyCommand(
                title: "Activate",
                action: #selector(activateAccessibilityElement),
                input: "\r",
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Escape",
                action: #selector(escapeAccessibilityElement),
                input: UIKeyCommand.inputEscape,
                modifierFlags: []
            )
        ]
    }

    @objc func nextAccessibilityElement() {
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    @objc func previousAccessibilityElement() {
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }

    @objc func activateAccessibilityElement() {
        // Override in subclasses
    }

    @objc func escapeAccessibilityElement() {
        // Override in subclasses
    }
}
#endif

// MARK: - Color Accessibility Extensions

extension Color {

    /// Get UIColor representation for contrast calculation
    var uiColor: UIColor {
        UIColor(self)
    }

    /// Check contrast ratio with another color
    func contrastRatio(with other: Color) -> Double {
        AccessibilityHelper.contrastRatio(
            foreground: self.uiColor,
            background: other.uiColor
        )
    }

    /// Check if contrast meets WCAG requirements
    func meetsContrast(
        with background: Color,
        fontSize: CGFloat,
        isBold: Bool = false
    ) -> Bool {
        AccessibilityHelper.meetsContrastRequirement(
            foreground: self.uiColor,
            background: background.uiColor,
            fontSize: fontSize,
            isBold: isBold
        )
    }
}

// MARK: - Dynamic Type Scaling

extension Font {

    /// Get scaled font that respects Dynamic Type
    static func scaledFont(
        name: String = "System",
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        if name == "System" {
            return .system(size: size, weight: weight)
                .dynamicTypeSize(.large...AccessibilityHelper.isAccessibilityCategory ? .accessibility5 : .xxxLarge)
        } else {
            return .custom(name, size: size, relativeTo: textStyle)
                .dynamicTypeSize(.large...AccessibilityHelper.isAccessibilityCategory ? .accessibility5 : .xxxLarge)
        }
    }
}

// MARK: - Accessibility Identifiers (for UI Testing)

enum AccessibilityIdentifiers {
    // MARK: - Authentication
    enum Auth {
        static let loginButton = "auth.login.button"
        static let signupButton = "auth.signup.button"
        static let emailField = "auth.email.field"
        static let passwordField = "auth.password.field"
        static let logoutButton = "auth.logout.button"
    }

    // MARK: - Feed
    enum Feed {
        static let scrollView = "feed.scrollview"
        static let postCell = "feed.post.cell"
        static let likeButton = "feed.post.like"
        static let commentButton = "feed.post.comment"
        static let shareButton = "feed.post.share"
        static let refreshControl = "feed.refresh"
    }

    // MARK: - Profile
    enum Profile {
        static let avatarImage = "profile.avatar"
        static let usernameLabel = "profile.username"
        static let bioLabel = "profile.bio"
        static let followButton = "profile.follow"
        static let editButton = "profile.edit"
        static let settingsButton = "profile.settings"
    }

    // MARK: - Search
    enum Search {
        static let searchField = "search.field"
        static let resultsTable = "search.results"
        static let filterButton = "search.filter"
        static let clearButton = "search.clear"
    }

    // MARK: - Notifications
    enum Notifications {
        static let list = "notifications.list"
        static let notificationCell = "notifications.cell"
        static let markReadButton = "notifications.markread"
    }
}
