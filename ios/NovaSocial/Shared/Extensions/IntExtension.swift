import Foundation

/// Extension for formatting numbers in human-readable format
/// Used for social engagement counts (likes, comments, shares, followers)
extension Int {
    /// Returns a compact string representation of the number
    /// - Examples: 999 -> "999", 1234 -> "1.2K", 1500000 -> "1.5M"
    var abbreviated: String {
        if self >= 1_000_000 {
            let formatted = Double(self) / 1_000_000
            // Remove .0 suffix for whole numbers
            if formatted.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0fM", formatted)
            }
            return String(format: "%.1fM", formatted)
        } else if self >= 1_000 {
            let formatted = Double(self) / 1_000
            // Remove .0 suffix for whole numbers
            if formatted.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0fK", formatted)
            }
            return String(format: "%.1fK", formatted)
        }
        return "\(self)"
    }

    /// Returns a compact string representation with more precision for larger numbers
    /// - Examples: 1234567 -> "1.23M"
    var abbreviatedPrecise: String {
        if self >= 1_000_000 {
            return String(format: "%.2fM", Double(self) / 1_000_000)
        } else if self >= 1_000 {
            return String(format: "%.1fK", Double(self) / 1_000)
        }
        return "\(self)"
    }
}
