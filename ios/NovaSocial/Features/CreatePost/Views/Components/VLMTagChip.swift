import SwiftUI

/// Tag chip for VLM (Vision Language Model) generated tags
struct VLMTagChip: View {
    let tag: String
    let confidence: Float
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(tag)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : Color(red: 0.27, green: 0.27, blue: 0.27))

                // Confidence indicator (only show for high confidence)
                if confidence >= 0.8 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : Color(red: 0.82, green: 0.13, blue: 0.25).opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected
                        ? Color(red: 0.82, green: 0.13, blue: 0.25)
                        : Color(red: 0.91, green: 0.91, blue: 0.91))
            )
        }
        .buttonStyle(.plain)
    }
}
