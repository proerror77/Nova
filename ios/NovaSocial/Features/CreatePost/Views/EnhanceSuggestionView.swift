import SwiftUI

/// Modal view for displaying Alice's post enhancement suggestions
struct EnhanceSuggestionView: View {
    let suggestion: PostEnhancementSuggestion
    @Binding var isPresented: Bool
    let onApply: (String) -> Void

    @State private var selectedDescription: String = ""
    @State private var selectedHashtags: Set<String> = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // MARK: - Header
                    headerSection

                    // MARK: - Main Suggestion
                    mainSuggestionSection

                    // MARK: - Hashtags
                    if !suggestion.hashtags.isEmpty {
                        hashtagsSection
                    }

                    // MARK: - Trending Topics
                    if let trending = suggestion.trendingTopics, !trending.isEmpty {
                        trendingSection(topics: trending)
                    }

                    // MARK: - Alternative Descriptions
                    if !suggestion.alternativeDescriptions.isEmpty {
                        alternativesSection
                    }

                    // MARK: - Preview
                    previewSection

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.gray)
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image("alice-center-icon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("Alice's Suggestions")
                            .font(Font.custom("SFProDisplay-Semibold", size: 16.f))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        onApply(buildFinalText())
                    }
                    .font(Font.custom("SFProDisplay-Semibold", size: 14.f))
                    .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            selectedDescription = suggestion.description
            selectedHashtags = Set(suggestion.hashtags)
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("I analyzed your photo and here's what I suggest:")
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(.gray)
        }
    }

    // MARK: - Main Suggestion Section
    private var mainSuggestionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Caption")
                .font(Font.custom("SFProDisplay-Semibold", size: 12.f))
                .foregroundColor(.gray)
                .textCase(.uppercase)

            Button(action: {
                selectedDescription = suggestion.description
            }) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: selectedDescription == suggestion.description ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedDescription == suggestion.description ? .blue : .gray)
                        .font(Font.custom("SFProDisplay-Regular", size: 20.f))

                    Text(suggestion.description)
                        .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Hashtags Section
    private var hashtagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hashtags")
                .font(Font.custom("SFProDisplay-Semibold", size: 12.f))
                .foregroundColor(.gray)
                .textCase(.uppercase)

            FlowLayout(spacing: 8) {
                ForEach(suggestion.hashtags, id: \.self) { hashtag in
                    HashtagChip(
                        hashtag: hashtag,
                        isSelected: selectedHashtags.contains(hashtag),
                        onTap: {
                            if selectedHashtags.contains(hashtag) {
                                selectedHashtags.remove(hashtag)
                            } else {
                                selectedHashtags.insert(hashtag)
                            }
                        }
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
    }

    // MARK: - Trending Section
    private func trendingSection(topics: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                    .font(Font.custom("SFProDisplay-Regular", size: 12.f))
                Text("Trending Topics")
                    .font(Font.custom("SFProDisplay-Semibold", size: 12.f))
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(topics, id: \.self) { topic in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: 6, height: 6)
                        Text(topic)
                            .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                            .foregroundColor(.black.opacity(0.8))
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Alternatives Section
    private var alternativesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alternative Captions")
                .font(Font.custom("SFProDisplay-Semibold", size: 12.f))
                .foregroundColor(.gray)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ForEach(suggestion.alternativeDescriptions, id: \.self) { alt in
                    Button(action: {
                        selectedDescription = alt
                    }) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedDescription == alt ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selectedDescription == alt ? .blue : .gray)
                                .font(Font.custom("SFProDisplay-Regular", size: 18.f))

                            Text(alt)
                                .font(Font.custom("SFProDisplay-Regular", size: 13.f))
                                .foregroundColor(.black.opacity(0.8))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedDescription == alt ? Color.blue.opacity(0.05) : Color.white)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
        }
    }

    // MARK: - Preview Section
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(Font.custom("SFProDisplay-Semibold", size: 12.f))
                .foregroundColor(.gray)
                .textCase(.uppercase)

            Text(buildFinalText())
                .font(Font.custom("SFProDisplay-Regular", size: 14.f))
                .foregroundColor(.black)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - Build Final Text
    private func buildFinalText() -> String {
        var result = selectedDescription
        if !selectedHashtags.isEmpty {
            let hashtagString = selectedHashtags.sorted().map { "#\($0)" }.joined(separator: " ")
            result += "\n\n" + hashtagString
        }
        return result
    }
}

// MARK: - Hashtag Chip
struct HashtagChip: View {
    let hashtag: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text("#\(hashtag)")
                .font(Font.custom("SFProDisplay-Medium", size: 13.f))
                .foregroundColor(isSelected ? .white : .blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue : Color.blue.opacity(0.1))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Flow Layout for Hashtags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                self.size.width = max(self.size.width, x)
            }

            self.size.height = y + rowHeight
        }
    }
}

// MARK: - Preview
#Preview {
    EnhanceSuggestionView(
        suggestion: PostEnhancementSuggestion(
            description: "Beautiful sunny day at the beach! The waves are perfect and the sand is warm. Can't wait to dive in! 🌊☀️",
            hashtags: ["beach", "summer", "waves", "sunshine", "vacation", "travel"],
            trendingTopics: ["Summer 2024 Beach Vibes", "Best Beaches to Visit"],
            alternativeDescriptions: [
                "Nothing beats a day by the ocean. The sound of waves is so relaxing!",
                "Found my happy place today. Sun, sand, and good vibes only!"
            ]
        ),
        isPresented: .constant(true),
        onApply: { _ in }
    )
}
