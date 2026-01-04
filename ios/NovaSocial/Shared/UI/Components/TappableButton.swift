import SwiftUI

// MARK: - Tappable Button Style

/// A reusable view modifier that creates a tappable button with consistent styling
/// Used for interactive elements like like, comment, bookmark buttons
struct TappableButtonStyle: ViewModifier {
    let action: () -> Void
    var verticalPadding: CGFloat = DesignTokens.spacing12
    var horizontalPadding: CGFloat = DesignTokens.spacing12
    
    func body(content: Content) -> some View {
        content
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .background(Color.white.opacity(0.001)) // Invisible but tappable
            .contentShape(Rectangle())
            .onTapGesture {
                action()
            }
    }
}

// MARK: - View Extension

extension View {
    /// Makes the view tappable with consistent padding and hit area
    /// - Parameters:
    ///   - verticalPadding: Vertical padding (default: 12)
    ///   - horizontalPadding: Horizontal padding (default: 12)
    ///   - action: The action to perform when tapped
    func tappableButton(
        verticalPadding: CGFloat = DesignTokens.spacing12,
        horizontalPadding: CGFloat = DesignTokens.spacing12,
        action: @escaping () -> Void
    ) -> some View {
        modifier(TappableButtonStyle(
            action: action,
            verticalPadding: verticalPadding,
            horizontalPadding: horizontalPadding
        ))
    }
}

// MARK: - Icon Button

/// A standardized icon button for social actions (like, comment, bookmark, share)
struct IconButton: View {
    let icon: String
    let count: Int?
    let isActive: Bool
    let activeColor: Color
    let inactiveColor: Color
    let action: () -> Void
    
    init(
        icon: String,
        count: Int? = nil,
        isActive: Bool = false,
        activeColor: Color = DesignTokens.iconActive,
        inactiveColor: Color = DesignTokens.iconInactive,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.count = count
        self.isActive = isActive
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.action = action
    }
    
    var body: some View {
        HStack(spacing: DesignTokens.spacing6) {
            Image(systemName: icon)
                .font(Font.custom("SFProDisplay-Regular", size: 18.f))
            
            if let count = count {
                Text("\(count)")
                    .font(.system(size: DesignTokens.fontCaption + 1))
            }
        }
        .foregroundColor(isActive ? activeColor : inactiveColor)
        .tappableButton(action: action)
    }
}

// MARK: - Preview

#Preview("Icon Buttons") {
    VStack(spacing: 20) {
        HStack(spacing: 0) {
            IconButton(icon: "heart", count: 42, isActive: false) {
                print("Like tapped")
            }
            
            IconButton(icon: "heart.fill", count: 43, isActive: true) {
                print("Unlike tapped")
            }
            
            IconButton(icon: "bubble.right", count: 12) {
                print("Comment tapped")
            }
            
            IconButton(icon: "bookmark", isActive: false) {
                print("Bookmark tapped")
            }
            
            IconButton(icon: "bookmark.fill", isActive: true) {
                print("Unbookmark tapped")
            }
        }
    }
    .padding()
}
