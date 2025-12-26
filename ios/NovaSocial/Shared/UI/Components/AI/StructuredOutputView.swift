import SwiftUI

// MARK: - Structured Output View

/// Container for various structured AI output components
struct StructuredOutputView {
    // This struct acts as a namespace for nested view types
}

// MARK: - Hashtag Pills

extension StructuredOutputView {

    /// Displays hashtags as tappable pill buttons
    struct HashtagPills: View {

        let hashtags: [String]
        var isLoading: Bool = false
        var selectedHashtags: Set<String> = []
        var onSelect: ((String) -> Void)?

        var body: some View {
            FlowLayout(spacing: 8) {
                ForEach(hashtags, id: \.self) { hashtag in
                    HashtagPill(
                        text: hashtag,
                        isSelected: selectedHashtags.contains(hashtag),
                        isLoading: isLoading
                    ) {
                        onSelect?(hashtag)
                    }
                }

                if isLoading {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonPill()
                    }
                }
            }
        }
    }

    /// Single hashtag pill button
    struct HashtagPill: View {

        let text: String
        var isSelected: Bool = false
        var isLoading: Bool = false
        var onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                Text("#\(text)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : .accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(backgroundColor)
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.accentColor.opacity(isSelected ? 0 : 0.5), lineWidth: 1)
                    )
            }
            .disabled(isLoading)
            .opacity(isLoading ? 0.5 : 1)
        }

        private var backgroundColor: Color {
            if isLoading {
                return Color.gray.opacity(0.3)
            }
            return isSelected ? Color.accentColor : Color.accentColor.opacity(0.1)
        }
    }

    /// Skeleton loading pill
    struct SkeletonPill: View {

        @State private var isAnimating = false

        var body: some View {
            Capsule()
                .fill(Color.gray.opacity(0.2))
                .frame(width: CGFloat.random(in: 60...100), height: 28)
                .shimmer(isActive: isAnimating)
                .onAppear {
                    isAnimating = true
                }
        }
    }
}

// MARK: - Suggestion Cards

extension StructuredOutputView {

    /// Displays suggestions as numbered cards
    struct SuggestionCards: View {

        let suggestions: [String]
        var isLoading: Bool = false
        var onSelect: ((Int, String) -> Void)?

        var body: some View {
            VStack(spacing: 8) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    SuggestionCard(
                        text: suggestion,
                        index: index + 1,
                        isLoading: isLoading
                    ) {
                        onSelect?(index, suggestion)
                    }
                }

                if isLoading {
                    ForEach(0..<2, id: \.self) { _ in
                        SkeletonCard()
                    }
                }
            }
        }
    }

    /// Single suggestion card
    struct SuggestionCard: View {

        let text: String
        let index: Int
        var isLoading: Bool = false
        var onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accentColor))

                    Text(text)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
            }
            .disabled(isLoading)
        }
    }

    /// Skeleton loading card
    struct SkeletonCard: View {

        @State private var isAnimating = false

        var body: some View {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 14)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 14)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .shimmer(isActive: isAnimating)
            .onAppear {
                isAnimating = true
            }
        }
    }
}

// MARK: - Quick Reply Buttons

extension StructuredOutputView {

    /// Displays quick reply options as buttons
    struct QuickReplyButtons: View {

        let replies: [String]
        var onSelect: ((String) -> Void)?

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(replies, id: \.self) { reply in
                        Button {
                            onSelect?(reply)
                        } label: {
                            Text(reply)
                                .font(.system(size: 14))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .strokeBorder(Color.accentColor, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Shimmer Effect

extension View {

    /// Applies a shimmer loading effect
    func shimmer(isActive: Bool) -> some View {
        self.overlay(
            GeometryReader { geometry in
                if isActive {
                    ShimmerView()
                        .frame(width: geometry.size.width * 2)
                        .offset(x: isActive ? geometry.size.width : -geometry.size.width)
                }
            }
        )
        .clipped()
    }
}

struct ShimmerView: View {

    @State private var offset: CGFloat = -1

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                .clear,
                .white.opacity(0.3),
                .clear
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: offset * 100)
        .onAppear {
            withAnimation(
                Animation.linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                offset = 1
            }
        }
    }
}

// MARK: - Previews

#Preview("Hashtag Pills") {
    VStack(spacing: 20) {
        StructuredOutputView.HashtagPills(
            hashtags: ["fashion", "style", "ootd", "summer", "trending"],
            selectedHashtags: ["fashion", "ootd"]
        ) { hashtag in
            print("Selected: \(hashtag)")
        }

        StructuredOutputView.HashtagPills(
            hashtags: ["loading"],
            isLoading: true
        )
    }
    .padding()
}

#Preview("Suggestion Cards") {
    StructuredOutputView.SuggestionCards(
        suggestions: [
            "Add more descriptive hashtags to increase visibility",
            "Consider posting during peak hours (6-9 PM)",
            "Include a call-to-action to boost engagement"
        ]
    ) { index, suggestion in
        print("Selected \(index): \(suggestion)")
    }
    .padding()
}

#Preview("Quick Replies") {
    StructuredOutputView.QuickReplyButtons(
        replies: ["Thanks!", "Love it!", "Tell me more"]
    ) { reply in
        print("Selected: \(reply)")
    }
    .padding()
}
