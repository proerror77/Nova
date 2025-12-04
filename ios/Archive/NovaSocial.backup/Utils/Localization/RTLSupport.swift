import SwiftUI

// MARK: - RTL-Aware Alignment
extension HorizontalAlignment {
    /// Returns leading alignment in LTR, trailing in RTL
    static var rtlLeading: HorizontalAlignment {
        LocalizationManager.shared.isRTL ? .trailing : .leading
    }

    /// Returns trailing alignment in LTR, leading in RTL
    static var rtlTrailing: HorizontalAlignment {
        LocalizationManager.shared.isRTL ? .leading : .trailing
    }
}

extension Alignment {
    /// Returns leading alignment in LTR, trailing in RTL
    static var rtlLeading: Alignment {
        LocalizationManager.shared.isRTL ? .trailing : .leading
    }

    /// Returns trailing alignment in LTR, leading in RTL
    static var rtlTrailing: Alignment {
        LocalizationManager.shared.isRTL ? .leading : .trailing
    }

    /// Returns topLeading in LTR, topTrailing in RTL
    static var rtlTopLeading: Alignment {
        LocalizationManager.shared.isRTL ? .topTrailing : .topLeading
    }

    /// Returns topTrailing in LTR, topLeading in RTL
    static var rtlTopTrailing: Alignment {
        LocalizationManager.shared.isRTL ? .topLeading : .topTrailing
    }

    /// Returns bottomLeading in LTR, bottomTrailing in RTL
    static var rtlBottomLeading: Alignment {
        LocalizationManager.shared.isRTL ? .bottomTrailing : .bottomLeading
    }

    /// Returns bottomTrailing in LTR, bottomLeading in RTL
    static var rtlBottomTrailing: Alignment {
        LocalizationManager.shared.isRTL ? .bottomLeading : .bottomTrailing
    }
}

extension TextAlignment {
    /// Returns leading alignment in LTR, trailing in RTL
    static var rtlLeading: TextAlignment {
        LocalizationManager.shared.isRTL ? .trailing : .leading
    }

    /// Returns trailing alignment in LTR, leading in RTL
    static var rtlTrailing: TextAlignment {
        LocalizationManager.shared.isRTL ? .leading : .trailing
    }
}

// MARK: - RTL-Aware Edge Insets
extension EdgeInsets {
    /// Create edge insets with RTL-aware leading/trailing
    static func rtl(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) -> EdgeInsets {
        if LocalizationManager.shared.isRTL {
            return EdgeInsets(top: top, leading: trailing, bottom: bottom, trailing: leading)
        } else {
            return EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
        }
    }
}

// MARK: - RTL-Aware Padding
extension View {
    /// Apply RTL-aware leading padding
    func rtlLeadingPadding(_ length: CGFloat) -> some View {
        if LocalizationManager.shared.isRTL {
            return AnyView(self.padding(.trailing, length))
        } else {
            return AnyView(self.padding(.leading, length))
        }
    }

    /// Apply RTL-aware trailing padding
    func rtlTrailingPadding(_ length: CGFloat) -> some View {
        if LocalizationManager.shared.isRTL {
            return AnyView(self.padding(.leading, length))
        } else {
            return AnyView(self.padding(.trailing, length))
        }
    }

    /// Apply RTL-aware horizontal padding
    func rtlHorizontalPadding(_ length: CGFloat) -> some View {
        self.padding(.horizontal, length)
    }

    /// Apply RTL-aware edge insets
    func rtlPadding(_ insets: EdgeInsets) -> some View {
        if LocalizationManager.shared.isRTL {
            return AnyView(self.padding(EdgeInsets(
                top: insets.top,
                leading: insets.trailing,
                bottom: insets.bottom,
                trailing: insets.leading
            )))
        } else {
            return AnyView(self.padding(insets))
        }
    }
}

// MARK: - RTL-Aware Image Mirroring
extension View {
    /// Mirror the view horizontally for RTL languages
    /// Use this for directional icons (arrows, chevrons, etc.)
    func rtlMirrored() -> some View {
        if LocalizationManager.shared.isRTL {
            return AnyView(self.scaleEffect(x: -1, y: 1))
        } else {
            return AnyView(self)
        }
    }

    /// Apply RTL mirroring based on a condition
    func rtlMirrored(_ shouldMirror: Bool) -> some View {
        if shouldMirror && LocalizationManager.shared.isRTL {
            return AnyView(self.scaleEffect(x: -1, y: 1))
        } else {
            return AnyView(self)
        }
    }
}

// MARK: - RTL-Aware Navigation
extension View {
    /// Apply RTL-aware navigation transition
    func rtlNavigationTransition() -> some View {
        self.transition(
            LocalizationManager.shared.isRTL
                ? .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
                : .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        )
    }
}

// MARK: - RTL-Aware Rotation
extension View {
    /// Rotate the view based on RTL direction
    /// Useful for icons that should point in the opposite direction in RTL
    func rtlRotation(degrees: Double = 180) -> some View {
        if LocalizationManager.shared.isRTL {
            return AnyView(self.rotationEffect(.degrees(degrees)))
        } else {
            return AnyView(self)
        }
    }
}

// MARK: - RTL-Safe SF Symbols
/// Helper to get RTL-safe SF Symbol names
enum RTLSymbol {
    /// Directional symbols that should be mirrored in RTL
    enum Directional: String {
        case chevronLeft = "chevron.left"
        case chevronRight = "chevron.right"
        case arrowLeft = "arrow.left"
        case arrowRight = "arrow.right"
        case chevronBackward = "chevron.backward"
        case chevronForward = "chevron.forward"

        var name: String {
            // SwiftUI automatically mirrors these when using .environment(\.layoutDirection, .rightToLeft)
            return rawValue
        }

        var flipped: String {
            switch self {
            case .chevronLeft: return "chevron.right"
            case .chevronRight: return "chevron.left"
            case .arrowLeft: return "arrow.right"
            case .arrowRight: return "arrow.left"
            case .chevronBackward: return "chevron.forward"
            case .chevronForward: return "chevron.backward"
            }
        }

        var rtlName: String {
            LocalizationManager.shared.isRTL ? flipped : rawValue
        }
    }

    /// Non-directional symbols that should NOT be mirrored
    enum Static: String {
        case heart = "heart"
        case heartFill = "heart.fill"
        case star = "star"
        case starFill = "star.fill"
        case gear = "gear"
        case person = "person"
        case bell = "bell"
        case magnifyingglass = "magnifyingglass"

        var name: String { rawValue }
    }
}

// MARK: - RTL Preview Helper
struct RTLPreviewWrapper<Content: View>: View {
    let content: Content
    let isRTL: Bool

    init(isRTL: Bool = false, @ViewBuilder content: () -> Content) {
        self.isRTL = isRTL
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
            .environment(\.locale, isRTL ? Locale(identifier: "ar") : Locale(identifier: "en"))
    }
}

// MARK: - Example Usage in Preview
#if DEBUG
struct RTLSupportExamples: View {
    var body: some View {
        VStack(spacing: 20) {
            // RTL-aware alignment
            HStack {
                Text("Leading Text")
                    .frame(maxWidth: .infinity, alignment: .rtlLeading)
                Text("Trailing Text")
                    .frame(maxWidth: .infinity, alignment: .rtlTrailing)
            }

            // RTL-aware padding
            Text("RTL Leading Padding")
                .rtlLeadingPadding(20)
                .background(Color.blue.opacity(0.2))

            // RTL-aware mirroring
            Image(systemName: "chevron.right")
                .rtlMirrored()
                .font(.title)

            // RTL-safe symbols
            HStack {
                Image(systemName: RTLSymbol.Directional.chevronRight.rtlName)
                Text("Next")
                Image(systemName: RTLSymbol.Static.heart.name)
            }
        }
        .padding()
    }
}

#Preview("LTR") {
    RTLPreviewWrapper(isRTL: false) {
        RTLSupportExamples()
    }
}

#Preview("RTL") {
    RTLPreviewWrapper(isRTL: true) {
        RTLSupportExamples()
    }
}
#endif
