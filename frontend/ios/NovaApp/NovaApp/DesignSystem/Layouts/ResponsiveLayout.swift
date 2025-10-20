import SwiftUI

// MARK: - Responsive Grid
struct ResponsiveGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let spacing: CGFloat
    let minItemWidth: CGFloat
    @ViewBuilder let content: (Item) -> Content

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    private var columns: [GridItem] {
        let columnCount: Int
        if horizontalSizeClass == .regular {
            // iPad or landscape
            columnCount = 3
        } else {
            // iPhone portrait
            columnCount = verticalSizeClass == .regular ? 3 : 4
        }

        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

// MARK: - Responsive Container
struct ResponsiveContainer<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    private var maxWidth: CGFloat {
        horizontalSizeClass == .regular ? 800 : .infinity
    }

    var body: some View {
        content
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, horizontalSizeClass == .regular ? Theme.Spacing.xl : Theme.Spacing.md)
    }
}

// MARK: - Adaptive Padding
extension View {
    func adaptivePadding() -> some View {
        modifier(AdaptivePaddingModifier())
    }
}

struct AdaptivePaddingModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    func body(content: Content) -> some View {
        content
            .padding(horizontalSizeClass == .regular ? Theme.Spacing.xl : Theme.Spacing.md)
    }
}

// MARK: - Screen Size Helper
enum ScreenSize {
    static var width: CGFloat {
        UIScreen.main.bounds.width
    }

    static var height: CGFloat {
        UIScreen.main.bounds.height
    }

    static var isSmall: Bool {
        width <= 375
    }

    static var isMedium: Bool {
        width > 375 && width <= 414
    }

    static var isLarge: Bool {
        width > 414
    }
}

// MARK: - Preview
#Preview {
    struct PreviewItem: Identifiable {
        let id = UUID()
        let color: Color
    }

    let items = [
        PreviewItem(color: .red),
        PreviewItem(color: .blue),
        PreviewItem(color: .green),
        PreviewItem(color: .orange),
        PreviewItem(color: .purple),
        PreviewItem(color: .pink)
    ]

    return ScrollView {
        ResponsiveContainer {
            ResponsiveGrid(items: items, spacing: 12, minItemWidth: 100) { item in
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.color)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}
