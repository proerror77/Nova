import SwiftUI
import Kingfisher

/// Figma 设计的投票卡片 - "Hottest Banker in H.K."
struct PollCard: View {
    let title: String
    let subtitle: String
    let candidates: [PollCandidate]
    let onVote: (Int) -> Void

    @State private var selectedIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 标题部分
            VStack(spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.Colors.textDark)

                Text(subtitle)
                    .font(DesignSystem.Typography.subtitle)
                    .foregroundColor(DesignSystem.Colors.textMedium)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, DesignSystem.Spacing.lg)
            .padding(.horizontal, DesignSystem.Spacing.lg)

            // 候选人卡片
            VStack(spacing: DesignSystem.Spacing.lg) {
                ForEach(candidates.indices, id: \.self) { index in
                    candidateRow(candidates[index], index: index)
                }
            }
            .padding(DesignSystem.Spacing.lg)

            // 分页指示器
            HStack(spacing: 6) {
                ForEach(0 ..< 5, id: \.self) { index in
                    Circle()
                        .fill(
                            index == 0
                                ? DesignSystem.Colors.primary
                                : DesignSystem.Colors.divider
                        )
                        .frame(width: 4, height: 4)
                }
                Spacer()
                Text("view more")
                    .font(DesignSystem.Typography.label)
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
        .applyCardStyle()
    }

    private func candidateRow(_ candidate: PollCandidate, index: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // 排名徽章
            Text("\(index + 1)")
                .font(DesignSystem.Typography.subtitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 35, height: 35)
                .background(DesignSystem.Colors.primary)
                .cornerRadius(DesignSystem.CornerRadius.small)

            // 候选人信息
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(DesignSystem.Typography.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.Colors.textDark)

                Text(candidate.organization)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textMedium)
            }

            Spacer()

            // 投票数
            Text("\(candidate.votes)")
                .font(DesignSystem.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(DesignSystem.Colors.textMedium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedIndex = index
            onVote(index)
        }
    }
}

struct PollCandidate {
    let name: String
    let organization: String
    let votes: Int
    let imageURL: URL?
}

#Preview {
    VStack(spacing: 16) {
        PollCard(
            title: "Hottest Banker in H.K.",
            subtitle: "Corporate Poll",
            candidates: [
                PollCandidate(name: "Lucy Liu", organization: "Morgan Stanley", votes: 2293, imageURL: nil),
                PollCandidate(name: "Jane Smith", organization: "Goldman Sachs", votes: 1856, imageURL: nil),
                PollCandidate(name: "Emily Chen", organization: "JPMorgan", votes: 1624, imageURL: nil),
                PollCandidate(name: "Sarah Johnson", organization: "Bank of America", votes: 1432, imageURL: nil),
                PollCandidate(name: "Lisa Wong", organization: "HSBC", votes: 1289, imageURL: nil),
            ],
            onVote: { _ in }
        )
        Spacer()
    }
    .padding(DesignSystem.Spacing.lg)
    .background(DesignSystem.Colors.background)
}
