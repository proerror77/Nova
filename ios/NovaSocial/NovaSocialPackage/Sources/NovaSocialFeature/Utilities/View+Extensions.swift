import SwiftUI

// MARK: - Border Modifiers

extension View {
    /// Adds a bottom border to the view
    /// - Parameters:
    ///   - color: The color of the border (default: light gray)
    ///   - width: The width of the border line (default: 1)
    func borderBottom(color: Color = .gray.opacity(0.2), width: CGFloat = 1) -> some View {
        VStack(spacing: 0) {
            self
            Divider()
                .frame(height: width)
                .background(color)
        }
    }

    /// Adds a top border to the view
    /// - Parameters:
    ///   - color: The color of the border (default: light gray)
    ///   - width: The width of the border line (default: 1)
    func borderTop(color: Color = .gray.opacity(0.2), width: CGFloat = 1) -> some View {
        VStack(spacing: 0) {
            Divider()
                .frame(height: width)
                .background(color)
            self
        }
    }
}
